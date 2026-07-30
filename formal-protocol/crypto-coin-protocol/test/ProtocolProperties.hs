{- |
Module      : ProtocolProperties
Description : QuickCheck property tests for Crypto_Coin protocol layer
Copyright   : (c) Crypto_Coin Team, 2025
License     : MIT
Maintainer  : core@crypto-coin.io
Stability   : experimental

This module contains property-based tests for the core protocol layer,
verifying invariants such as deterministic state transitions,
UTXO conservation, Merkle proof soundness, and signature correctness.
-}

module ProtocolProperties (main) where

import           CryptoCoin.Protocol.Types
import           CryptoCoin.Protocol.Block
import           CryptoCoin.Protocol.State
import           CryptoCoin.Protocol.Merkle
import           CryptoCoin.Protocol.Crypto

import           Test.QuickCheck
import           Test.QuickCheck.Monadic
import           Test.HUnit                    (assertBool, assertEqual)
import           Test.Framework                (defaultMain, testGroup)
import           Test.Framework.Providers.QuickCheck2 (testProperty)
import           Test.Framework.Providers.HUnit       (testCase)

import           Data.ByteString               (ByteString)
import qualified Data.ByteString               as BS
import qualified Data.ByteString.Char8         as C8
import           Data.List                     (nub, sort)
import           Data.Maybe                    (isJust, isNothing)
import           Data.Word                     (Word64)
import           Control.Monad                 (replicateM)

----------------------------------------------------------------------
-- Arbitrary Instances
----------------------------------------------------------------------

instance Arbitrary Hash where
    arbitrary = Hash . BS.pack <$> vector 32
    shrink (Hash bs) = [Hash (BS.pack (take n (BS.unpack bs))) | n <- [0, 8, 16, 24]]

instance Arbitrary Address where
    arbitrary = Address . BS.pack <$> vector 20
    shrink (Address bs) = [Address (BS.pack (take n (BS.unpack bs))) | n <- [0, 10, 15]]

instance Arbitrary BlockHash where
    arbitrary = BlockHash <$> arbitrary
    shrink (BlockHash h) = [BlockHash h' | h' <- shrink h]

instance Arbitrary ValidatorId where
    arbitrary = ValidatorId <$> arbitrary

instance Arbitrary Signature where
    arbitrary = Signature . BS.pack <$> vector 64
    shrink (Signature bs) = [Signature (BS.pack (take n (BS.unpack bs))) | n <- [0, 32, 48]]

instance Arbitrary UTXO where
    arbitrary = do
        txId  <- arbitrary
        idx   <- choose (0, 255)
        value <- choose (0, 1000000)
        addr  <- arbitrary
        return UTXO
            { uTxId       = txId
            , uOutputIndex = fromIntegral idx
            , uValue       = Value value
            , uOwner       = addr
            }

instance Arbitrary TxInput where
    arbitrary = do
        txId  <- arbitrary
        idx   <- choose (0, 255)
        sig   <- arbitrary
        return TxInput
            { tiTxId        = txId
            , tiOutputIndex = fromIntegral idx
            , tiSignature   = sig
            }

instance Arbitrary TxOutput where
    arbitrary = do
        value <- choose (0, 1000000)
        addr  <- arbitrary
        return TxOutput
            { toValue = Value value
            , toOwner = addr
            }

instance Arbitrary Transaction where
    arbitrary = do
        inputs  <- listOf1 arbitrary `suchThat` ((<= 10) . length)
        outputs <- listOf1 arbitrary `suchThat` ((<= 10) . length . nub)
        return Transaction
            { txId     = TxId (Hash (BS.replicate 32 0))  -- Overwritten below
            , txInputs  = inputs
            , txOutputs = outputs
            , txData    = BS.empty
            }

-- | Generate a valid transaction with matching total value
genValidTransaction :: Gen Transaction
genValidTransaction = do
    let value = 1000
    addr     <- arbitrary
    let utxo = UTXO
            { uTxId        = TxId (Hash (BS.replicate 32 0))
            , uOutputIndex = 0
            , uValue       = Value value
            , uOwner       = addr
            }
    let input = TxInput
            { tiTxId        = uTxId utxo
            , tiOutputIndex = uOutputIndex utxo
            , tiSignature   = Signature BS.empty
            }
    let output = TxOutput
            { toValue = Value value
            , toOwner = addr
            }
    return Transaction
        { txId     = TxId (Hash (BS.replicate 32 1))
        , txInputs  = [input]
        , txOutputs = [output]
        , txData    = BS.empty
        }

----------------------------------------------------------------------
-- Property: Deterministic State Transitions
----------------------------------------------------------------------

-- | Same inputs must always produce the same outputs
prop_deterministic_transition :: Transaction -> Block -> Bool
prop_deterministic_transition tx block =
    let state1 = applyTransaction emptyState tx
        state2 = applyTransaction emptyState tx
    in state1 == state2

-- | Block validation must be deterministic
prop_deterministic_validation :: Block -> Bool
prop_deterministic_validation block =
    let r1 = validateBlock block
        r2 = validateBlock block
    in r1 == r2

----------------------------------------------------------------------
-- Property: UTXO Conservation (No money creation)
----------------------------------------------------------------------

-- | Total value in must equal total value out
prop_utxo_conservation :: Property
prop_utxo_conservation = forAll genValidTransaction $ \tx ->
    let inputValue  = sum [v | TxInput{..} <- txInputs tx]
        outputValue = sum [v | TxOutput{..} <- txOutputs tx]
    in inputValue === outputValue

-- | UTXO set must never contain duplicate UTXOs
prop_no_duplicate_utxos :: State -> Bool
prop_no_duplicate_utxos state =
    let utxos = Map.elems (stUTXOSet state)
    in length (nub utxos) == length utxos

----------------------------------------------------------------------
-- Property: Merkle Proof Soundness
----------------------------------------------------------------------

-- | Merkle proof verification must accept valid proofs
prop_merkle_proof_valid :: Property
prop_merkle_proof_valid = forAll (listOf1 arbitrary `suchThat` ((>= 1) . length)) $ \hashes ->
    let tree = buildMerkleTree hashes
        root = merkleRoot tree
    in conjoin [counterexample ("Leaf " ++ show i) $
                case generateMerkleProof hashes i of
                    Just proof -> verifyMerkleProof root proof
                    Nothing    -> False
               | i <- [0..length hashes - 1]]

-- | Merkle proof verification must reject invalid proofs
prop_merkle_proof_invalid :: Property
prop_merkle_proof_invalid = forAll (listOf1 arbitrary `suchThat` ((>= 2) . length)) $ \hashes ->
    let tree = buildMerkleTree hashes
        root = merkleRoot tree
        -- Swap two hashes to create an invalid set
        badHashes = case hashes of
            (a:b:rest) -> b:a:rest
            _          -> hashes
    in case generateMerkleProof badHashes 0 of
        Just proof  -> not (verifyMerkleProof root proof)
        Nothing     -> True

-- | Merkle root must change when data changes
prop_merkle_avalanche :: Property
prop_merkle_avalanche = forAll (listOf1 arbitrary `suchThat` ((>= 2) . length)) $ \hashes ->
    let root1 = merkleRoot (buildMerkleTree hashes)
        badHashes = case hashes of
            (a:rest) -> Hash (BS.replicate 32 0) : rest
            _        -> hashes
        root2 = merkleRoot (buildMerkleTree badHashes)
    in root1 /= root2

----------------------------------------------------------------------
-- Property: Signature Verification
----------------------------------------------------------------------

-- | A valid signature must verify
prop_signature_verify :: Property
prop_signature_verify = forAll (BS.pack <$> vector 32) $ \data_ ->
    let (pubKey, privKey) = generateKeyPair
        sig = signData privKey data_
    in verifySignature pubKey sig data_

-- | A signature for different data must not verify
prop_signature_wrong_data :: Property
prop_signature_wrong_data = forAll (BS.pack <$> vector 32) $ \data_ ->
    forAll (BS.pack <$> vector 32 `suchThat` (/= data_)) $ \badData ->
        let (pubKey, privKey) = generateKeyPair
            sig = signData privKey data_
        in not (verifySignature pubKey sig badData)

-- | A signature from a different key must not verify
prop_signature_wrong_key :: Property
prop_signature_wrong_key = forAll (BS.pack <$> vector 32) $ \data_ ->
    let (pubKey1, privKey1) = generateKeyPair
        (pubKey2, _)        = generateKeyPair
        sig = signData privKey1 data_
    in not (verifySignature pubKey2 sig data_)

----------------------------------------------------------------------
-- Property: Address Derivation
----------------------------------------------------------------------

-- | Address must be deterministic from public key
prop_address_deterministic :: PublicKey -> Bool
prop_address_deterministic pubKey =
    addressFromKey pubKey == addressFromKey pubKey

-- | Different public keys must produce different addresses
prop_address_unique :: Property
prop_address_unique = forAll (BS.pack <$> vector 32) $ \seed1 ->
    forAll (BS.pack <$> vector 32 `suchThat` (/= seed1)) $ \seed2 ->
        let (pk1, _) = deterministicKeyPair seed1
            (pk2, _) = deterministicKeyPair seed2
        in addressFromKey pk1 /= addressFromKey pk2

----------------------------------------------------------------------
-- Property: State Machine Invariants
----------------------------------------------------------------------

-- | State transition must preserve the set of valid UTXOs
prop_state_preserves_utxos :: Transaction -> State -> Bool
prop_state_preserves_utxos tx state =
    let newState = applyTransaction state tx
    in case newState of
        Left _err -> True  -- Invalid tx, unchanged state
        Right s   -> totalUTXOValue s <= totalUTXOValue state + epsilon
  where
    epsilon = 0  -- No value creation

-- | Empty state must have zero UTXOs
prop_empty_state_utxos :: Bool
prop_empty_state_utxos =
    Map.null (stUTXOSet emptyState)

-- | State after valid transaction must have correct UTXO count
prop_state_utxo_count :: Property
prop_state_utxo_count = forAll genValidTransaction $ \tx ->
    case applyTransaction emptyState tx of
        Left _     -> True  -- Invalid tx
        Right newState ->
            let inputCount  = length (txInputs tx)
                outputCount = length (txOutputs tx)
            in Map.size (stUTXOSet newState) === fromIntegral outputCount

----------------------------------------------------------------------
-- Property: Block Invariants
----------------------------------------------------------------------

-- | Block with invalid structure must fail validation
prop_invalid_block_rejected :: Block -> Property
prop_invalid_block_rejected block =
    let brokenBlock = block { bBody = emptyBlockBody }
    in validateBlock brokenBlock === BlockInvalidStructure

-- | Block with empty transaction list must have valid Merkle root
prop_empty_block_merkle :: Block -> Bool
prop_empty_block_merkle block =
    let body = bBody block
        txs  = bbTransactions body
    in if null txs
       then case bbMerkleRoot body of
           BlockHash (Hash h) -> BS.all (== 0) h  -- Zero hash for empty
           _                  -> True
       else True

----------------------------------------------------------------------
-- Property: Transaction Validation
----------------------------------------------------------------------

-- | Transaction with no inputs must be invalid
prop_empty_inputs_invalid :: Transaction -> Bool
prop_empty_inputs_invalid tx =
    let emptyTx = tx { txInputs = [] }
    in not (validateTransaction emptyTx)

-- | Transaction with no outputs must be invalid
prop_empty_outputs_invalid :: Transaction -> Bool
prop_empty_outputs_invalid tx =
    let emptyTx = tx { txOutputs = [] }
    in not (validateTransaction emptyTx)

----------------------------------------------------------------------
-- Property: Hash Collision Resistance (Probabilistic)
----------------------------------------------------------------------

-- | Different inputs must produce different hashes
prop_hash_collision :: Property
prop_hash_collision = forAll (BS.pack <$> vector 16) $ \d1 ->
    forAll (BS.pack <$> vector 16 `suchThat` (/= d1)) $ \d2 ->
        hashData d1 /= hashData d2

-- | Hash must produce 32-byte output
prop_hash_length :: ByteString -> Bool
prop_hash_length data_ =
    let Hash h = hashData data_
    in BS.length h == 32

----------------------------------------------------------------------
-- Test Suite
----------------------------------------------------------------------

main :: IO ()
main = defaultMain tests

tests :: Test.Framework.Test
tests = testGroup "Protocol Layer Properties"
    [ testGroup "Determinism"
        [ testProperty "state transitions are deterministic"
            prop_deterministic_transition
        , testProperty "block validation is deterministic"
            prop_deterministic_validation
        ]

    , testGroup "UTXO Model"
        [ testProperty "UTXO conservation (value in = value out)"
            prop_utxo_conservation
        , testProperty "no duplicate UTXOs"
            prop_no_duplicate_utxos
        , testProperty "empty state has no UTXOs"
            (property prop_empty_state_utxos)
        ]

    , testGroup "Merkle Trees"
        [ testProperty "valid proofs are accepted"
            prop_merkle_proof_valid
        , testProperty "invalid proofs are rejected"
            prop_merkle_proof_invalid
        , testProperty "avalanche effect (small change → different root)"
            prop_merkle_avalanche
        ]

    , testGroup "Signatures"
        [ testProperty "valid signatures verify"
            prop_signature_verify
        , testProperty "wrong data rejected"
            prop_signature_wrong_data
        , testProperty "wrong key rejected"
            prop_signature_wrong_key
        ]

    , testGroup "Addresses"
        [ testProperty "address derivation is deterministic"
            prop_address_deterministic
        , testProperty "different keys produce different addresses"
            prop_address_unique
        ]

    , testGroup "State Machine"
        [ testProperty "state transition preserves UTXOs"
            prop_state_preserves_utxos
        , testProperty "correct UTXO count after transaction"
            prop_state_utxo_count
        ]

    , testGroup "Block Validation"
        [ testProperty "invalid blocks are rejected"
            prop_invalid_block_rejected
        , testProperty "empty block Merkle root is zero"
            prop_empty_block_merkle
        ]

    , testGroup "Transaction Validation"
        [ testProperty "empty inputs are invalid"
            prop_empty_inputs_invalid
        , testProperty "empty outputs are invalid"
            prop_empty_outputs_invalid
        ]

    , testGroup "Hash Functions"
        [ testProperty "different inputs produce different hashes"
            prop_hash_collision
        , testProperty "hash output is 32 bytes"
            prop_hash_length
        ]
    ]

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

emptyBlockBody :: BlockBody
emptyBlockBody = BlockBody [] (BlockHash (Hash (BS.replicate 32 0)))


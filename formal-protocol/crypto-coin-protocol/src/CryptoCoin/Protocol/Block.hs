{- |
Module      : CryptoCoin.Protocol.Block
Description : Block structure, validation, and hashing
Copyright   : (c) Crypto_Coin Team, 2025
License     : MIT
Maintainer  : core@crypto-coin.io
Stability   : experimental

This module defines block creation, validation rules, and the
deterministic block hashing mechanism. Blocks are the fundamental
unit of the blockchain, containing transactions and consensus votes.
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns      #-}

module CryptoCoin.Protocol.Block
    ( -- * Block Operations
      createBlock
    , createGenesisBlock
    , validateBlock
    , validateBlockHeader
    , validateBlockBody
    , hashBlock
    , hashBlockHeader
    , verifyBlockSignature
    , signBlock

      -- * Block Queries
    , blockTransactions
    , blockVotes
    , blockNumber
    , blockParentHash
    , blockValidator
    , blockTimestamp

      -- * Block Body Operations
    , computeMerkleRoot
    , computeStateRoot
    , bodyTransactionRoot
    , bodyVoteRoot
    ) where

import           CryptoCoin.Protocol.Types
import qualified CryptoCoin.Protocol.Merkle as Merkle
import qualified CryptoCoin.Protocol.Crypto  as Crypto

import           Data.ByteString            (ByteString)
import qualified Data.ByteString            as BS
import qualified Data.ByteString.Lazy       as BSL
import           Data.List                  (foldl')
import           Data.Maybe                 (isJust, fromMaybe)
import           Data.Word                  (Word64)
import           Data.Time.Clock.POSIX      (getPOSIXTime)

----------------------------------------------------------------------
-- Block Creation
----------------------------------------------------------------------

-- | Create a new block from a parent and a set of transactions/votes
createBlock
    :: BlockHeader        -- ^ Parent block header (for prev hash, number)
    -> SlotNumber         -- ^ Current slot number
    -> EpochNumber        -- ^ Current epoch number
    -> ValidatorId        -- ^ Block producer
    -> PrivateKey         -- ^ Signing key
    -> [Transaction]      -- ^ Transactions to include
    -> [Vote]             -- ^ Votes to include
    -> UTxOSet            -- ^ Current UTxO set (for state root)
    -> IO (Either ProtocolError Block)
createBlock parentHeader slot epoch validator privKey txs votes utxoSet = do
    timestamp <- getPOSIXTime
    let blockNumber = succ (bhBlockNumber parentHeader)
        txRoot     = computeMerkleRoot (map txHash txs)
        voteRoot   = computeMerkleRoot (map voteHash votes)
        bodyRoot   = Merkle.combineRoots txRoot voteRoot
        stateRoot  = computeStateRoot utxoSet
        nonce      = 0  -- Leader can set nonce for extra entropy

    let header = BlockHeader
            { bhParentHash  = hashBlockHeader parentHeader
            , bhBlockNumber = blockNumber
            , bhSlotNumber  = slot
            , bhEpochNumber = epoch
            , bhTimestamp   = timestamp
            , bhValidator   = validator
            , bhMerkleRoot  = bodyRoot
            , bhStateRoot   = stateRoot
            , bhNonce       = nonce
            , bhVersion     = 1
            , bhSignature   = Signature BS.empty  -- Placeholder
            }

    -- Sign the header
    sigResult <- signBlock privKey header
    case sigResult of
        Left err -> return $ Left err
        Right signature ->
            let signedHeader = header { bhSignature = signature }
                block = Block signedHeader (BlockBody txs votes)
            in return $ Right block

-- | Create the genesis block (block 0)
createGenesisBlock
    :: GenesisConfig      -- ^ Genesis configuration
    -> PrivateKey         -- ^ Genesis signing key
    -> IO (Either ProtocolError Block)
createGenesisBlock genesisConfig privKey = do
    timestamp <- getPOSIXTime
    let genTime = gcGenesisTime genesisConfig
        -- Use genesis time if available, otherwise current time
        actualTime = if genTime > 0 then genTime else timestamp

        -- Genesis header has parent hash = all zeros
        zeroHash    = Hash (BS.replicate 32 0)
        merkleRoot  = MerkleRoot zeroHash
        stateRoot   = computeGenesisStateRoot genesisConfig

        header = BlockHeader
            { bhParentHash  = zeroHash
            , bhBlockNumber = BlockNumber 0
            , bhSlotNumber  = SlotNumber 0
            , bhEpochNumber = EpochNumber 0
            , bhTimestamp   = actualTime
            , bhValidator   = ValidatorId (Address BS.empty)
            , bhMerkleRoot  = merkleRoot
            , bhStateRoot   = stateRoot
            , bhNonce       = 0
            , bhVersion     = 1
            , bhSignature   = Signature BS.empty
            }

    sigResult <- signBlock privKey header
    case sigResult of
        Left err -> return $ Left err
        Right signature ->
            let signedHeader = header { bhSignature = signature }
                block = Block signedHeader (BlockBody [] [])
            in return $ Right block

----------------------------------------------------------------------
-- Block Validation
----------------------------------------------------------------------

-- | Validate a complete block against the current chain state
validateBlock
    :: ChainState         -- ^ Current chain state
    -> Block              -- ^ Block to validate
    -> ProtocolParams     -- ^ Protocol parameters
    -> Either ValidationError Block
validateBlock chainState block params =
    let header = bHeader block
        body   = bBody block
     in do
        -- Validate structure and size
        validateBlockSize body params

        -- Validate header
        validateBlockHeader chainState header params

        -- Validate body (transactions, votes)
        validateBlockBody chainState body header

        -- Verify merkle root matches body
        let computedTxRoot   = computeMerkleRoot (map txHash (bbTransactions body))
            computedVoteRoot = computeMerkleRoot (map voteHash (bbVotes body))
            computedBodyRoot = Merkle.combineRoots computedTxRoot computedVoteRoot
        if computedBodyRoot /= bhMerkleRoot header
            then Left $ VEMerkleRootMismatch (bhMerkleRoot header) computedBodyRoot
            else Right block

-- | Validate block header only
validateBlockHeader
    :: ChainState
    -> BlockHeader
    -> ProtocolParams
    -> Either ValidationError BlockHeader
validateBlockHeader chainState header params = do
    -- Verify parent exists
    let tipHash = csTipHash chainState
    if bhParentHash header /= tipHash
        then Left $ VEInvalidBlockStructure "parent hash does not match chain tip"
        else Right ()

    -- Verify block number is sequential
    let tipNumber = csTipNumber chainState
    if bhBlockNumber header /= succ tipNumber
        then Left $ VEInvalidBlockStructure "block number is not sequential"
        else Right ()

    -- Verify signature
    let verificationResult = verifyBlockSignature header
    if not verificationResult
        then Left VEInvalidSignature
        else Right ()

    -- Verify version
    if bhVersion header /= 1
        then Left $ VEInvalidBlockStructure "unsupported block version"
        else Right ()

    return header

-- | Validate block body (transactions)
validateBlockBody
    :: ChainState
    -> BlockBody
    -> BlockHeader
    -> Either ValidationError BlockBody
validateBlockBody chainState body header =
    let txs  = bbTransactions body
        utxo = csUtxoSet chainState
     in do
        -- Validate each transaction
        mapM_ (validateTransaction utxo) txs

        -- Verify no double spends within the block
        let inputIds = concatMap (map tiUtxoId . txInputs) txs
        if length inputIds /= length (nubOrd inputIds)
            then Left $ VEInvalidBlockStructure "duplicate UTxO inputs in block"
            else Right ()

        return body
  where
    nubOrd :: Ord a => [a] -> [a]
    nubOrd = go Set.empty
      where
        go _ []     = []
        go s (x:xs)
            | x `Set.member` s = go s xs
            | otherwise        = x : go (Set.insert x s) xs

-- | Validate a single transaction against UTxO set
validateTransaction :: UTxOSet -> Transaction -> Either ValidationError Transaction
validateTransaction (UTxOSet utxoMap) tx = do
    -- Verify signature
    let txData = serializeForSigning tx
    if not (Crypto.verify (txPublicKey tx) (txSignature tx) txData)
        then Left VEInvalidSignature
        else Right ()

    -- Verify all inputs exist in UTxO set and are unspent
    mapM_ (validateInput utxoMap) (txInputs tx)

    -- Verify no UTxO is spent twice within the transaction
    let inputIds = map tiUtxoId (txInputs tx)
    if length inputIds /= length (Set.fromList inputIds)
        then Left $ VEDoubleSpend (head inputIds)
        else Right ()

    -- Verify total output value <= total input value (conservation)
    let totalInput  = sumInputs tx utxoMap
        totalOutput = sumOutputs tx
    if totalOutput > totalInput
        then Left $ VEInsufficientFunds totalInput totalOutput
        else Right ()

    return tx
  where
    validateInput :: Map UTxOId UTxO -> TxInput -> Either ValidationError ()
    validateInput utxoMap input =
        case Map.lookup (tiUtxoId input) utxoMap of
            Nothing -> Left $ VEDoubleSpend (tiUtxoId input)
            Just _  -> Right ()

    sumInputs :: Transaction -> Map UTxOId UTxO -> Amount
    sumInputs tx m = Amount $ foldl' go 0 (txInputs tx)
      where
        go acc input = case Map.lookup (tiUtxoId input) m of
            Just utxo -> acc + unAmount (uAmount utxo)
            Nothing   -> acc

    sumOutputs :: Transaction -> Amount
    sumOutputs tx = Amount $ foldl' (\acc o -> acc + unAmount (toAmount o)) 0 (txOutputs tx)

-- | Validate block size constraints
validateBlockSize :: BlockBody -> ProtocolParams -> Either ValidationError ()
validateBlockSize body params = do
    let serialized = serializeBody body
        actualSize = fromIntegral (BS.length serialized) :: Word32
    if actualSize > ppMaxBlockSize params
        then Left $ VEBlockTooLarge actualSize (ppMaxBlockSize params)
        else Right ()

----------------------------------------------------------------------
-- Block Hashing
----------------------------------------------------------------------

-- | Compute the hash of a complete block
hashBlock :: Block -> BlockHash
hashBlock block = hashBlockHeader (bHeader block)

-- | Compute the hash of a block header
hashBlockHeader :: BlockHeader -> BlockHash
hashBlockHeader = Crypto.hash . serializeHeader

----------------------------------------------------------------------
-- Block Signing & Verification
----------------------------------------------------------------------

-- | Sign a block header with the validator's private key
signBlock :: PrivateKey -> BlockHeader -> IO (Either ProtocolError Signature)
signBlock privKey header = do
    let headerBytes = serializeHeader header
    case Crypto.sign privKey headerBytes of
        Just sig -> return $ Right sig
        Nothing  -> return $ Left $ PECryptoError "signing failed"

-- | Verify a block header's signature
verifyBlockSignature :: BlockHeader -> Bool
verifyBlockSignature header =
    let pubKey = derivePublicKey (bhValidator header)
        sig    = bhSignature header
        data_  = serializeForSigning header
    in Crypto.verify pubKey sig data_

-- | Derive a public key from a validator ID (address)
derivePublicKey :: ValidatorId -> PublicKey
derivePublicKey (ValidatorId (Address addrBytes)) =
    PublicKey addrBytes

----------------------------------------------------------------------
-- Merkle Tree Operations
----------------------------------------------------------------------

-- | Compute the Merkle root of a list of hashes
computeMerkleRoot :: [Hash] -> MerkleRoot
computeMerkleRoot hashes =
    MerkleRoot (Merkle.computeRoot hashes)

-- | Compute the state root hash from UTxO set
computeStateRoot :: UTxOSet -> Hash
computeStateRoot (UTxOSet utxoMap) =
    let sortedEntries = Map.toAscList utxoMap
        entryHashes = map (\(uid, utxo) ->
            Crypto.hash (serializeUTxOEntry uid utxo)) sortedEntries
    in Merkle.computeRoot entryHashes

-- | Compute genesis state root
computeGenesisStateRoot :: GenesisConfig -> Hash
computeGenesisStateRoot gc =
    let initialEntries = map (\(addr, amt) ->
            let uid = UTxOId (TxId (Hash BS.empty), fromIntegral (length (fst3 (unzip3 [(addr, amt)]))))
            in Crypto.hash (serializeUTxOEntry uid (UTxO uid addr amt Nothing))) (gcInitialUtxos gc)
    in Merkle.computeRoot initialEntries
  where
    fst3 (x, _, _) = x
    unzip3 xs = (map (\(a, b) -> (a, b)) xs, [])

-- | Get transaction root from block body
bodyTransactionRoot :: BlockBody -> MerkleRoot
bodyTransactionRoot body =
    computeMerkleRoot (map txHash (bbTransactions body))

-- | Get vote root from block body
bodyVoteRoot :: BlockBody -> MerkleRoot
bodyVoteRoot body =
    computeMerkleRoot (map voteHash (bbVotes body))

----------------------------------------------------------------------
-- Block Queries
----------------------------------------------------------------------

blockTransactions :: Block -> [Transaction]
blockTransactions = bbTransactions . bBody

blockVotes :: Block -> [Vote]
blockVotes = bbVotes . bBody

blockNumber :: Block -> BlockNumber
blockNumber = bhBlockNumber . bHeader

blockParentHash :: Block -> BlockHash
blockParentHash = bhParentHash . bHeader

blockValidator :: Block -> ValidatorId
blockValidator = bhValidator . bHeader

blockTimestamp :: Block -> Timestamp
blockTimestamp = bhTimestamp . bHeader

----------------------------------------------------------------------
-- Serialization Helpers
----------------------------------------------------------------------

-- | Serialize a block header for hashing
serializeHeader :: BlockHeader -> ByteString
serializeHeader h = BS.concat
    [ serializeHash (bhParentHash h)
    , serializeWord64 (unBlockNumber (bhBlockNumber h))
    , serializeWord64 (unSlotNumber (bhSlotNumber h))
    , serializeWord64 (unEpochNumber (bhEpochNumber h))
    , serializeTimestamp (bhTimestamp h)
    , serializeValidatorId (bhValidator h)
    , serializeHash (unMerkleRoot (bhMerkleRoot h))
    , serializeHash (bhStateRoot h)
    , serializeWord64 (bhNonce h)
    , serializeWord32 (bhVersion h)
    ]

-- | Serialize a block header for signing (excludes signature field)
serializeForSigning :: BlockHeader -> ByteString
serializeForSigning h = BS.concat
    [ serializeHash (bhParentHash h)
    , serializeWord64 (unBlockNumber (bhBlockNumber h))
    , serializeWord64 (unSlotNumber (bhSlotNumber h))
    , serializeWord64 (unEpochNumber (bhEpochNumber h))
    , serializeTimestamp (bhTimestamp h)
    , serializeValidatorId (bhValidator h)
    , serializeHash (unMerkleRoot (bhMerkleRoot h))
    , serializeHash (bhStateRoot h)
    , serializeWord64 (bhNonce h)
    , serializeWord32 (bhVersion h)
    ]

-- | Serialize a transaction for signing
serializeForSigning :: Transaction -> ByteString
serializeForSigning tx = BS.concat
    [ serializeTxId (txId tx)
    , serializeInputs (txInputs tx)
    , serializeOutputs (txOutputs tx)
    , serializeWord64 (txNonce tx)
    , serializeAmount (txFee tx)
    ]

-- | Serialize a UTxO entry
serializeUTxOEntry :: UTxOId -> UTxO -> ByteString
serializeUTxOEntry uid utxo = BS.concat
    [ serializeUTxOId uid
    , serializeAddress (uAddress utxo)
    , serializeAmount (uAmount utxo)
    ]

-- | Serialize a vote for hashing
voteHash :: Vote -> Hash
voteHash vote = Crypto.hash (BS.concat
    [ serializeValidatorId (vValidator vote)
    , serializeHash (vBlockHash vote)
    , serializeWord64 (vRound vote)
    , serializeWord8 (fromIntegral (fromEnum (vVoteType vote)))
    ])

-- | Compute transaction hash
txHash :: Transaction -> Hash
txHash tx = Crypto.hash (serializeForSigning tx)

-- | Serialize block body
serializeBody :: BlockBody -> ByteString
serializeBody body = BS.concat
    [ serializeTransactions (bbTransactions body)
    , serializeVotes (bbVotes body)
    ]

------------------------------------------------------------------------------
-- Primitive Serializers
------------------------------------------------------------------------------

serializeHash :: Hash -> ByteString
serializeHash (Hash b) = b

serializeWord64 :: Word64 -> ByteString
serializeWord64 = BS.pack . go 8
  where
    go 0 _ = []
    go n w = fromIntegral (w `shiftR` (8 * (n - 1))) : go (n - 1) w
    shiftR x y = x `div` (2 ^ y)

serializeWord32 :: Word32 -> ByteString
serializeWord32 w = BS.pack
    [ fromIntegral (w `shiftR` 24)
    , fromIntegral (w `shiftR` 16)
    , fromIntegral (w `shiftR` 8)
    , fromIntegral w
    ]

serializeWord8 :: Word8 -> ByteString
serializeWord8 = BS.singleton

serializeTimestamp :: Timestamp -> ByteString
serializeTimestamp = serializeWord64 . round

serializeValidatorId :: ValidatorId -> ByteString
serializeValidatorId (ValidatorId (Address b)) = b

serializeAddress :: Address -> ByteString
serializeAddress (Address b) = b

serializeAmount :: Amount -> ByteString
serializeAmount (Amount w) = serializeWord64 w

serializeUTxOId :: UTxOId -> ByteString
serializeUTxOId (UTxOId (txId, idx)) = BS.concat
    [ serializeTxId txId
    , serializeWord64 idx
    ]

serializeTxId :: TxId -> ByteString
serializeTxId (TxId (Hash b)) = b

serializeInputs :: [TxInput] -> ByteString
serializeInputs = BS.concat . map serializeInput

serializeInput :: TxInput -> ByteString
serializeInput input = serializeUTxOId (tiUtxoId input)

serializeOutputs :: [TxOutput] -> ByteString
serializeOutputs = BS.concat . map serializeOutput

serializeOutput :: TxOutput -> ByteString
serializeOutput output = BS.concat
    [ serializeAddress (toAddress output)
    , serializeAmount (toAmount output)
    ]

serializeTransactions :: [Transaction] -> ByteString
serializeTransactions = BS.concat . map serializeTransaction

serializeTransaction :: Transaction -> ByteString
serializeTransaction tx = serializeForSigning tx

serializeVotes :: [Vote] -> ByteString
serializeVotes = BS.concat . map serializeVote

serializeVote :: Vote -> ByteString
serializeVote vote = BS.concat
    [ serializeValidatorId (vValidator vote)
    , serializeHash (vBlockHash vote)
    , serializeWord64 (vRound vote)
    , serializeWord8 (fromIntegral (fromEnum (vVoteType vote)))
    ]


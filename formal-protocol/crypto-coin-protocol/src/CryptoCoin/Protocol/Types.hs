{- |
Module      : CryptoCoin.Protocol.Types
Description : Core cryptographic and protocol types for the Crypto_Coin blockchain
Copyright   : (c) Crypto_Coin Team, 2025
License     : MIT
Maintainer  : core@crypto-coin.io
Stability   : experimental

This module defines the fundamental types used throughout the Crypto_Coin
blockchain protocol. All types are designed with strong static guarantees
to prevent invalid states at compile time.
-}

{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies      #-}
{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE StandaloneDeriving #-}

module CryptoCoin.Protocol.Types
    ( -- * Core Cryptographic Types
      Hash (..)
    , Signature (..)
    , PublicKey (..)
    , PrivateKey (..)
    , Address (..)
    , MerkleRoot (..)
    , MerkleProof (..)

      -- * Block Types
    , BlockHeader (..)
    , BlockBody (..)
    , Block (..)
    , BlockHash
    , BlockNumber (..)
    , SlotNumber (..)
    , EpochNumber (..)

      -- * Transaction Types
    , Transaction (..)
    , TxId (..)
    , TxInput (..)
    , TxOutput (..)
    , UTxO (..)
    , UTxOId (..)
    , Amount (..)
    , Value (..)

      -- * State Types
    , ChainState (..)
    , UTxOSet (..)
    , ValidatorState (..)
    , ConsensusState (..)

      -- * Validator Types
    , ValidatorId (..)
    , ValidatorSet (..)
    , Stake (..)
    , Vote (..)

      -- * Protocol Parameters
    , ProtocolParams (..)
    , SecurityParam (..)
    , EpochLength (..)
    , SlotLength (..)
    , GenesisConfig (..)

      -- * Error Types
    , ProtocolError (..)
    , ValidationError (..)
    , ConsensusError (..)

      -- * Type Aliases
    , Nonce
    , Version
    , Timestamp
    ) where

import           Data.ByteString          (ByteString)
import           Data.Int                 (Int64)
import           Data.Word                (Word32, Word64)
import           Data.Time.Clock.POSIX    (POSIXTime)
import           Data.Map.Strict          (Map)
import qualified Data.Map.Strict          as Map
import           Data.Set                 (Set)
import qualified Data.Set                 as Set
import           Data.List                (sort)
import           GHC.Generics             (Generic)
import           Control.DeepSeq          (NFData)
import           Data.Aeson               (ToJSON, FromJSON)

----------------------------------------------------------------------
-- Cryptographic Types
----------------------------------------------------------------------

-- | A cryptographic hash (SHA3-256)
newtype Hash = Hash ByteString
    deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

-- | A digital signature (Ed25519)
newtype Signature = Signature ByteString
    deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

-- | A public key for signature verification
newtype PublicKey = PublicKey ByteString
    deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

-- | A private key for signing operations (never serialized)
newtype PrivateKey = PrivateKey ByteString
    deriving (Eq, Show, Generic, NFData)

-- | A blockchain address derived from a public key
newtype Address = Address ByteString
    deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

-- | Merkle tree root hash
newtype MerkleRoot = MerkleRoot Hash
    deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

-- | A Merkle proof for a single leaf
data MerkleProof = MerkleProof
    { mpLeaf    :: !Hash
    , mpSiblings :: ![Hash]
    , mpIndex   :: !Word64
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

----------------------------------------------------------------------
-- Block Types
----------------------------------------------------------------------

-- | Type alias for a block's hash
type BlockHash = Hash

-- | Block number (monotonically increasing)
newtype BlockNumber = BlockNumber Word64
    deriving (Eq, Ord, Show, Enum, Bounded, Generic, NFData, ToJSON, FromJSON)

-- | Slot number within the consensus protocol
newtype SlotNumber = SlotNumber Word64
    deriving (Eq, Ord, Show, Enum, Bounded, Generic, NFData, ToJSON, FromJSON)

-- | Epoch number for validator rotation
newtype EpochNumber = EpochNumber Word64
    deriving (Eq, Ord, Show, Enum, Bounded, Generic, NFData, ToJSON, FromJSON)

-- | Block header contains all metadata for block verification
data BlockHeader = BlockHeader
    { bhParentHash      :: !BlockHash
    , bhBlockNumber     :: !BlockNumber
    , bhSlotNumber      :: !SlotNumber
    , bhEpochNumber     :: !EpochNumber
    , bhTimestamp       :: !Timestamp
    , bhValidator       :: !ValidatorId
    , bhMerkleRoot      :: !MerkleRoot
    , bhStateRoot       :: !Hash       -- ^ Hash of post-state after applying block
    , bhNonce           :: !Nonce
    , bhVersion         :: !Version
    , bhSignature       :: !Signature  -- ^ Validator's signature over the header
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | Block body contains the actual transactions
data BlockBody = BlockBody
    { bbTransactions :: ![Transaction]
    , bbVotes        :: ![Vote]        -- ^ Votes included in this block
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | A complete block
data Block = Block
    { bHeader :: !BlockHeader
    , bBody   :: !BlockBody
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

----------------------------------------------------------------------
-- Transaction Types
----------------------------------------------------------------------

-- | Transaction identifier (hash of the transaction)
newtype TxId = TxId Hash
    deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

-- | Input to a transaction (spends a UTxO)
data TxInput = TxInput
    { tiUtxoId :: !UTxOId
    , tiProof  :: !(Maybe MerkleProof)  -- ^ Merkle proof of inclusion
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | Output from a transaction (creates a UTxO)
data TxOutput = TxOutput
    { toAddress :: !Address
    , toAmount  :: !Amount
    , toData    :: !(Maybe ByteString)  -- ^ Optional metadata
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | A blockchain transaction
data Transaction = Transaction
    { txId        :: !TxId
    , txInputs    :: ![TxInput]
    , txOutputs   :: ![TxOutput]
    , txSignature :: !Signature
    , txPublicKey :: !PublicKey
    , txNonce     :: !Word64           -- ^ Prevent replay attacks
    , txFee       :: !Amount
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | An unspent transaction output identifier
newtype UTxOId = UTxOId
    { unUTxOId :: (TxId, Word64)  -- ^ (Transaction ID, output index)
    } deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

-- | An unspent transaction output in the UTxO set
data UTxO = UTxO
    { uId      :: !UTxOId
    , uAddress :: !Address
    , uAmount  :: !Amount
    , uData    :: !(Maybe ByteString)
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | Token amount (always non-negative)
newtype Amount = Amount Word64
    deriving (Eq, Ord, Show, Enum, Bounded, Generic, NFData, ToJSON, FromJSON)

-- | A value denomination
data Value = Value
    { vAmount :: !Amount
    , vDenom  :: !Word8  -- ^ Decimal places (0-18)
    } deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

----------------------------------------------------------------------
-- State Types
----------------------------------------------------------------------

-- | The complete UTxO set (all unspent outputs)
newtype UTxOSet = UTxOSet
    { unUTxOSet :: Map UTxOId UTxO
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | The current state of a validator (used in consensus)
data ValidatorState = ValidatorState
    { vsStake        :: !Stake
    , vsIsActive     :: !Bool
    , vsLastVote     :: !(Maybe SlotNumber)
    , vsMissedSlots  :: !Word64
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | Consensus-specific state
data ConsensusState = ConsensusState
    { csCurrentEpoch      :: !EpochNumber
    , csCurrentSlot       :: !SlotNumber
    , csLastFinalizedBlock :: !BlockHash
    , csValidatorSet      :: !ValidatorSet
    , csPendingProposals  :: !(Map SlotNumber BlockHash)
    , csVotes             :: !(Map BlockHash (Set Vote))
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | The complete chain state
data ChainState = ChainState
    { csUtxoSet         :: !UTxOSet
    , csConsensus       :: !ConsensusState
    , csValidatorStates :: !(Map ValidatorId ValidatorState)
    , csTipHash         :: !BlockHash
    , csTipNumber       :: !BlockNumber
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

----------------------------------------------------------------------
-- Validator Types
----------------------------------------------------------------------

-- | A validator's identifier (their public key hash)
newtype ValidatorId = ValidatorId Address
    deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

-- | The complete validator set for the current epoch
newtype ValidatorSet = ValidatorSet
    { unValidatorSet :: [(ValidatorId, Stake)]
    } deriving (Eq, Show, Generic, NFData)

instance ToJSON ValidatorSet where
    toJSON = undefined  -- Implement via tuple pairs

instance FromJSON ValidatorSet where
    parseJSON = undefined  -- Implement via tuple pairs

-- | Amount of stake (in native tokens)
newtype Stake = Stake Word64
    deriving (Eq, Ord, Show, Enum, Bounded, Generic, NFData, ToJSON, FromJSON)

-- | A vote from a validator
data Vote = Vote
    { vValidator    :: !ValidatorId
    , vBlockHash    :: !BlockHash
    , vRound        :: !Word64
    , vVoteType     :: !VoteType
    , vSignature    :: !Signature
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | Type of vote in the consensus protocol
data VoteType
    = VotePrepare   -- ^ Prepare phase vote
    | VoteCommit    -- ^ Commit phase vote (finality)
    deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

----------------------------------------------------------------------
-- Protocol Parameters
----------------------------------------------------------------------

-- | Protocol security parameters
data SecurityParam = SecurityParam
    { spK :: !Word64  -- ^ Confirmation depth parameter
    , spT :: !Word8   -- ^ Maximum fault tolerance (as fraction: t/3 of validators)
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | Number of slots per epoch
newtype EpochLength = EpochLength Word64
    deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

-- | Duration of a single slot (in milliseconds)
newtype SlotLength = SlotLength Word64
    deriving (Eq, Ord, Show, Generic, NFData, ToJSON, FromJSON)

-- | Complete protocol configuration
data ProtocolParams = ProtocolParams
    { ppSecurityParam   :: !SecurityParam
    , ppEpochLength     :: !EpochLength
    , ppSlotLength      :: !SlotLength
    , ppMaxBlockSize    :: !Word32     -- ^ Maximum block size in bytes
    , ppMaxTxSize       :: !Word32     -- ^ Maximum transaction size in bytes
    , ppMinStake        :: !Stake      -- ^ Minimum stake to become validator
    , ppSlashingRate    :: !Word8      -- ^ Percentage slashed for misbehavior
    , ppRewardRate      :: !Word8      -- ^ Annual reward rate in basis points
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

-- | Genesis block configuration
data GenesisConfig = GenesisConfig
    { gcInitialValidators :: ![(ValidatorId, Stake)]
    , gcInitialUtxos      :: ![(Address, Amount)]
    , gcGenesisTime       :: !Timestamp
    , gcProtocolParams    :: !ProtocolParams
    } deriving (Eq, Show, Generic, NFData, ToJSON, FromJSON)

----------------------------------------------------------------------
-- Error Types
----------------------------------------------------------------------

-- | Top-level protocol errors
data ProtocolError
    = PEValidationError ValidationError
    | PEConsensusError ConsensusError
    | PECryptoError String
    | PEInternalError String
    deriving (Eq, Show, Generic, NFData)

-- | Transaction/block validation errors
data ValidationError
    = VEInvalidBlockStructure String
    | VEInvalidSignature
    | VEInsufficientFunds Amount Amount
    | VEDoubleSpend UTxOId
    | VEInvalidNonce
    | VETransactionTooLarge Word32 Word32
    | VEBlockTooLarge Word32 Word32
    | VEMerkleRootMismatch MerkleRoot MerkleRoot
    | VEStateRootMismatch Hash Hash
    deriving (Eq, Show, Generic, NFData)

-- | Consensus-specific errors
data ConsensusError
    = CEInvalidValidator ValidatorId
    | CEInsufficientVotes Word64 Word64  -- ^ (got, needed)
    | CEDoubleVote ValidatorId
    | CEUnknownBlock BlockHash
    | CEForkNotFinalized
    | CEEpochMismatch EpochNumber EpochNumber
    | CESlotMismatch SlotNumber SlotNumber
    | CELeaderElectionFailed
    deriving (Eq, Show, Generic, NFData)

----------------------------------------------------------------------
-- Type Aliases
----------------------------------------------------------------------

-- | A timestamp (POSIX time)
type Timestamp = POSIXTime

-- | A nonce used in consensus
type Nonce = Word64

-- | Protocol version
type Version = Word32


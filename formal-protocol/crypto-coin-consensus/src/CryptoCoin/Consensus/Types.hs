{- |
Module      : CryptoCoin.Consensus.Types
Description : Core consensus types for the Crypto_Coin blockchain
Copyright   : (c) Crypto_Coin Team, 2025
License     : MIT
Maintainer  : core@crypto-coin.io
Stability   : experimental

This module defines the fundamental types used across the consensus
layer of the Crypto_Coin blockchain. It includes validator set management,
consensus rounds, and protocol state types.
-}

{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE DeriveAnyClass    #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns      #-}

module CryptoCoin.Consensus.Types
    ( -- * Validator Types
      ValidatorSet (..)
    , ValidatorInfo (..)
    , ValidatorPower (..)
    , ValidatorStatus (..)

      -- * Consensus Types
    , ConsensusRound (..)
    , ConsensusStep (..)
    , ConsensusState (..)
    , ConsensusConfig (..)
    , ConsensusMessage (..)
    , ConsensusResult (..)

      -- * PBFT Types
    , PBFTRound (..)
    , PBFTPhase (..)
    , PBFTMessage (..)
    , PBFTProof (..)

      -- * Random Beacon Types
    , BeaconRound (..)
    , BeaconOutput (..)
    , BeaconProof (..)
    , BeaconContribution (..)

      -- * View Change Types
    , ViewChange (..)
    , ViewChangeProof (..)
    , NewView (..)

      -- * Checkpoint Types
    , Checkpoint (..)
    , CheckpointProof (..)
    , ConsensusCheckpoint (..)

      -- * Utility Functions
    , validatorSetSize
    , superMajority
    , superMajorityCount
    , isValidatorActive
    , activeValidators
    , validatorPower
    , roundInterval
    ) where

import           Data.ByteString          (ByteString)
import qualified Data.ByteString          as BS
import           Data.Word                (Word64)
import           Data.Int                 (Int64)
import           Data.Time.Clock.POSIX    (POSIXTime)
import           Data.Map                 (Map)
import qualified Data.Map                 as Map
import           Data.Set                 (Set)
import qualified Data.Set                 as Set
import           Data.List                (foldl')
import           GHC.Generics             (Generic)
import           Control.DeepSeq          (NFData)

----------------------------------------------------------------------
-- Validator Types
----------------------------------------------------------------------

-- | Represents the power/stake weight of a validator
newtype ValidatorPower = ValidatorPower
    { unValidatorPower :: Word64
    } deriving (Eq, Ord, Show, Generic, NFData)

-- | Status of a validator in the consensus protocol
data ValidatorStatus
    = Active                    -- ^ Participating in consensus
    | Inactive                  -- ^ Temporarily not participating
    | Jailed                    -- ^ Penalized for misbehavior
    | Tombstoned                -- ^ Permanently removed
    | Unbonding                 -- ^ In the process of unbonding stake
    deriving (Eq, Ord, Show, Enum, Bounded, Generic, NFData)

-- | Information about a single validator
data ValidatorInfo = ValidatorInfo
    { viAddress  :: !Address       -- ^ Validator's address
    , viPower    :: !ValidatorPower -- ^ Voting power
    , viStatus   :: !ValidatorStatus -- ^ Current status
    , viPubKey   :: !PublicKey     -- ^ Consensus public key
    , viVrfKey   :: !PublicKey     -- ^ VRF public key (for leader election)
    , viEndpoint :: !ByteString    -- ^ Network endpoint
    , viMetadata :: !ByteString    -- ^ Additional metadata
    } deriving (Eq, Show, Generic, NFData)

-- | The complete validator set for a given epoch
data ValidatorSet = ValidatorSet
    { vsValidators :: ![ValidatorInfo]
    , vsTotalPower :: !ValidatorPower
    , vsEpoch      :: !EpochNumber
    , vsHash       :: !BlockHash
    } deriving (Eq, Show, Generic, NFData)

----------------------------------------------------------------------
-- Consensus Round Types
----------------------------------------------------------------------

-- | A consensus round identifier
newtype ConsensusRound = ConsensusRound
    { unConsensusRound :: Word64
    } deriving (Eq, Ord, Show, Generic, NFData)

-- | Steps within a consensus round
data ConsensusStep
    = ProposePhase
    | PrevotePhase
    | PrecommitPhase
    | CommitPhase
    deriving (Eq, Ord, Show, Enum, Bounded, Generic, NFData)

-- | Current state of the consensus protocol
data ConsensusState = ConsensusState
    { csRound          :: !ConsensusRound
    , csStep           :: !ConsensusStep
    , csProposedBlock  :: !(Maybe BlockHash)
    , csValidatorSet   :: !ValidatorSet
    , csLockedBlock    :: !(Maybe BlockHash)
    , csLockedRound    :: !(Maybe ConsensusRound)
    , csValidBlock     :: !(Maybe BlockHash)
    , csValidRound     :: !(Maybe ConsensusRound)
    , csDecision       :: !(Maybe BlockHash)
    , csRoundStart     :: !POSIXTime
    , csTimeout        :: !Word64
    } deriving (Eq, Show, Generic, NFData)

-- | Configuration for the consensus protocol
data ConsensusConfig = ConsensusConfig
    | ccTimeoutPropose   :: !Word64
    , ccTimeoutPrevote   :: !Word64
    , ccTimeoutPrecommit :: !Word64
    , ccTimeoutCommit    :: !Word64
    , ccMaxBlockSize     :: !Word64
    , ccMaxTxPerBlock    :: !Word64
    , ccSuperMajority    :: !Double
    , ccRoundInterval    :: !Word64
    } deriving (Eq, Show, Generic, NFData)

-- | Messages exchanged during consensus
data ConsensusMessage
    = CProposal   !ProposalMsg
    | CPrevote    !PrevoteMsg
    | CPrecommit  !PrecommitMsg
    | CCommit     !CommitMsg
    | CViewChange !ViewChange
    | CNewView    !NewView
    deriving (Eq, Show, Generic, NFData)

-- | Result of a consensus round
data ConsensusResult
    = ConsensusSuccess !Block  -- ^ Block was committed
    | ConsensusTimeout         -- ^ Round timed out
    | ConsensusFailure !Error  -- ^ Fatal error
    deriving (Eq, Show, Generic, NFData)

----------------------------------------------------------------------
-- PBFT Types
----------------------------------------------------------------------

-- | PBFT round number
newtype PBFTRound = PBFTRound
    { unPBFTRound :: Word64
    } deriving (Eq, Ord, Show, Generic, NFData)

-- | PBFT phase
data PBFTPhase
    = PBFTPrePrepare
    | PBFTPrepare
    | PBFTCommit
    deriving (Eq, Ord, Show, Enum, Bounded, Generic, NFData)

-- | PBFT consensus message
data PBFTMessage = PBFTMessage
    { pmType    :: !PBFTPhase
    , pmRound   :: !PBFTRound
    , pmView    :: !Word64
    , pmBlock   :: !(Maybe BlockHash)
    , pmSender  :: !ValidatorId
    , pmSig     :: !Signature
    } deriving (Eq, Show, Generic, NFData)

-- | PBFT proof (collection of signed messages)
data PBFTProof = PBFTProof
    | ppPrePrepare :: !PBFTMessage
    , ppPrepares   :: ![PBFTMessage]
    , ppCommits    :: ![PBFTMessage]
    } deriving (Eq, Show, Generic, NFData)

----------------------------------------------------------------------
-- Random Beacon Types
----------------------------------------------------------------------

-- | Beacon round number
newtype BeaconRound = BeaconRound
    { unBeaconRound :: Word64
    } deriving (Eq, Ord, Show, Generic, NFData)

-- | Output of the random beacon
data BeaconOutput = BeaconOutput
    { boRound    :: !BeaconRound
    , boValue    :: !Hash
    , boProof    :: !BeaconProof
    } deriving (Eq, Show, Generic, NFData)

-- | Proof for a beacon output (VRF based)
data BeaconProof = BeaconProof
    { bpContributions :: ![BeaconContribution]
    , bpAggregateSig  :: !Signature
    } deriving (Eq, Show, Generic, NFData)

-- | A single validator's contribution to the beacon
data BeaconContribution = BeaconContribution
    { bcValidator :: !ValidatorId
    , bcValue     :: !Hash
    , bcProof     :: !ByteString
    , bcSig       :: !Signature
    } deriving (Eq, Show, Generic, NFData)

----------------------------------------------------------------------
-- View Change Types
----------------------------------------------------------------------

-- | View change request
data ViewChange = ViewChange
    { vcNewView     :: !Word64
    , vcLastRound   :: !ConsensusRound
    , vcPreparedProof :: !(Maybe PBFTProof)
    , vcSender      :: !ValidatorId
    , vcSig         :: !Signature
    } deriving (Eq, Show, Generic, NFData)

-- | Proof of view change agreement
data ViewChangeProof = ViewChangeProof
    { vcpViewChanges :: ![ViewChange]
    , vcpNewView     :: !NewView
    } deriving (Eq, Show, Generic, NFData)

-- | New view after view change
data NewView = NewView
    { nvView       :: !Word64
    , nvPrePrepares :: ![PBFTMessage]
    , nvSender     :: !ValidatorId
    , nvSig        :: !Signature
    } deriving (Eq, Show, Generic, NFData)

----------------------------------------------------------------------
-- Checkpoint Types
----------------------------------------------------------------------

-- | A consensus checkpoint
data Checkpoint = Checkpoint
    { cpHeight  :: !BlockNumber
    , cpHash    :: !BlockHash
    , cpState   :: !Hash
    } deriving (Eq, Ord, Show, Generic, NFData)

-- | Proof for a checkpoint (signed by validators)
data CheckpointProof = CheckpointProof
    { cppCheckpoint :: !Checkpoint
    , cppSignatures :: ![(ValidatorId, Signature)]
    } deriving (Eq, Show, Generic, NFData)

-- | Consensus-level checkpoint with metadata
data ConsensusCheckpoint = ConsensusCheckpoint
    { ccCheckpoint :: !Checkpoint
    , ccProof      :: !CheckpointProof
    , ccEpoch      :: !EpochNumber
    , ccTimestamp  :: !POSIXTime
    } deriving (Eq, Show, Generic, NFData)

----------------------------------------------------------------------
-- Internal Message Types
----------------------------------------------------------------------

-- | Proposal message
data ProposalMsg = ProposalMsg
    { pmBlock       :: !Block
    , pmRound       :: !ConsensusRound
    , pmValidRound  :: !(Maybe ConsensusRound)
    , pmProposer    :: !ValidatorId
    , pmSignature   :: !Signature
    } deriving (Eq, Show, Generic, NFData)

-- | Prevote message
data PrevoteMsg = PrevoteMsg
    { prBlockHash :: !(Maybe BlockHash)
    , prRound     :: !ConsensusRound
    , prSender    :: !ValidatorId
    , prSignature :: !Signature
    } deriving (Eq, Show, Generic, NFData)

-- | Precommit message
data PrecommitMsg = PrecommitMsg
    { pcBlockHash :: !(Maybe BlockHash)
    , pcRound     :: !ConsensusRound
    , pcSender    :: !ValidatorId
    , pcSignature :: !Signature
    } deriving (Eq, Show, Generic, NFData)

-- | Commit message
data CommitMsg = CommitMsg
    { cmBlockHash :: !BlockHash
    , cmRound     :: !ConsensusRound
    , cmSender    :: !ValidatorId
    , cmSignature :: !Signature
    } deriving (Eq, Show, Generic, NFData)

----------------------------------------------------------------------
-- Utility Functions
----------------------------------------------------------------------

-- | Get the number of validators in the set
validatorSetSize :: ValidatorSet -> Int
validatorSetSize = length . vsValidators

-- | Check if a set of validators constitutes a super-majority (2/3+)
superMajority :: ValidatorSet -> Set ValidatorId -> Bool
superMajority vset voters =
    let totalPower = unValidatorPower (vsTotalPower vset)
        voterPower = sum [ unValidatorPower (viPower v)
                         | v <- vsValidators vset
                         , viAddress v `Set.member` voters
                         ]
    in voterPower * 3 > totalPower * 2

-- | Calculate the number of validators needed for super-majority
superMajorityCount :: ValidatorSet -> Int
superMajorityCount vset =
    let n = validatorSetSize vset
    in (n * 2) `div` 3 + 1

-- | Check if a validator is active
isValidatorActive :: ValidatorInfo -> Bool
isValidatorActive = (== Active) . viStatus

-- | Get the list of active validators
activeValidators :: ValidatorSet -> [ValidatorInfo]
activeValidators = filter isValidatorActive . vsValidators

-- | Get the power of a specific validator
validatorPower :: ValidatorSet -> ValidatorId -> ValidatorPower
validatorPower vset vid =
    case lookup vid [(viAddress v, viPower v) | v <- vsValidators vset] of
        Just p  -> p
        Nothing -> ValidatorPower 0

-- | Get the round interval in seconds
roundInterval :: ConsensusConfig -> Word64
roundInterval = ccRoundInterval

</content>

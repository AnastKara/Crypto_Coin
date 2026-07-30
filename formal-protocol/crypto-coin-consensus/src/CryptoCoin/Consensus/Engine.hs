{- |
Module      : CryptoCoin.Consensus.Engine
Description : Core consensus engine implementing Tendermint-style BFT
Copyright   : (c) Crypto_Coin Team, 2025
License     : MIT
Maintainer  : core@crypto-coin.io
Stability   : experimental

This module implements the core consensus engine using a Tendermint-style
Byzantine Fault Tolerant (BFT) consensus algorithm with PBFT fallback.
It handles block proposal, voting, commit, and view change protocols.
-}

module CryptoCoin.Consensus.Engine
    ( -- * Consensus Engine
      ConsensusEngine (..)
    , newConsensusEngine
    , runConsensusRound
    , handleProposal
    , handlePrevote
    , handlePrecommit
    , handleCommit
    , handleViewChange
    , startConsensus

      -- * State Transitions
    , transitionStep
    , applyConsensusMessage
    , timeoutHandler

      -- * Decision Making
    , decideBlock
    , shouldPropose
    , shouldPrevote
    , shouldPrecommit
    , isRoundProposer

      -- * Queries
    , engineState
    , engineConfig
    , engineValidatorSet
    , engineLatestBlock
    ) where

import           CryptoCoin.Consensus.Types
import qualified CryptoCoin.Protocol.Block   as Block
import qualified CryptoCoin.Protocol.Types   as Protocol
import qualified CryptoCoin.Protocol.Crypto  as Crypto

import           Control.Concurrent          (MVar, newMVar, modifyMVar_, modifyMVar, readMVar)
import           Control.Monad               (when, unless, forM_)
import           Data.ByteString             (ByteString)
import qualified Data.ByteString             as BS
import           Data.Map                    (Map)
import qualified Data.Map                    as Map
import           Data.Set                    (Set)
import qualified Data.Set                    as Set
import           Data.Time.Clock.POSIX       (getPOSIXTime, POSIXTime)
import           Data.Word                   (Word64)
import           Data.Maybe                  (isJust, isNothing, fromMaybe)
import           Data.IORef                  (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import           Control.Concurrent.STM      (TVar, newTVarIO, readTVarIO, writeTVar, atomically)

----------------------------------------------------------------------
-- Consensus Engine Type
----------------------------------------------------------------------

-- | The core consensus engine state
data ConsensusEngine = ConsensusEngine
    { ceState      :: !(TVar ConsensusState)
    , ceConfig     :: !ConsensusConfig
    , cePrivKey    :: !PrivateKey
    , cePubKey     :: !PublicKey
    , ceValidator  :: !ValidatorId
    , ceMsgQueue   :: !(TVar [ConsensusMessage])
    , ceDecisions  :: !(TVar [Block])
    , ceMetrics    :: !(TVar ConsensusMetrics)
    }

-- | Consensus runtime metrics
data ConsensusMetrics = ConsensusMetrics
    { cmRoundsCompleted :: !Word64
    , cmBlocksProposed  :: !Word64
    , cmBlocksCommitted :: !Word64
    , cmViewChanges     :: !Word64
    , cmTimeouts        :: !Word64
    , cmAvgLatency      :: !Double
    } deriving (Eq, Show)

----------------------------------------------------------------------
-- Engine Construction
----------------------------------------------------------------------

-- | Create a new consensus engine instance
newConsensusEngine
    :: ConsensusConfig
    -> PrivateKey
    -> PublicKey
    -> ValidatorId
    -> ValidatorSet
    -> IO ConsensusEngine
newConsensusEngine config privKey pubKey validator vset = do
    now <- getPOSIXTime
    let initState = ConsensusState
            { csRound          = ConsensusRound 0
            , csStep           = ProposePhase
            , csProposedBlock  = Nothing
            , csValidatorSet   = vset
            , csLockedBlock    = Nothing
            , csLockedRound    = Nothing
            , csValidBlock     = Nothing
            , csValidRound     = Nothing
            , csDecision       = Nothing
            , csRoundStart     = now
            , csTimeout        = ccTimeoutPropose config
            }
    stateVar       <- newTVarIO initState
    msgQueue       <- newTVarIO []
    decisions      <- newTVarIO []
    metrics        <- newTVarIO ConsensusMetrics
        { cmRoundsCompleted = 0
        , cmBlocksProposed  = 0
        , cmBlocksCommitted = 0
        , cmViewChanges     = 0
        , cmTimeouts        = 0
        , cmAvgLatency      = 0.0
        }
    return ConsensusEngine
        { ceState     = stateVar
        , ceConfig    = config
        , cePrivKey   = privKey
        , cePubKey    = pubKey
        , ceValidator = validator
        , ceMsgQueue  = msgQueue
        , ceDecisions = decisions
        , ceMetrics   = metrics
        }

----------------------------------------------------------------------
-- Main Consensus Loop
----------------------------------------------------------------------

-- | Start the consensus process
startConsensus :: ConsensusEngine -> IO ()
startConsensus engine = do
    state <- readTVarIO (ceState engine)
    case csDecision state of
        Just _  -> return ()  -- Already decided
        Nothing -> runConsensusRound engine

-- | Run a single consensus round
runConsensusRound :: ConsensusEngine -> IO ()
runConsensusRound engine = do
    state <- readTVarIO (ceState engine)
    let round = csRound state
        vset  = csValidatorSet state

    -- Check if we are the proposer for this round
    when (shouldPropose round vset (ceValidator engine)) $ do
        proposeBlock engine

    -- Process messages until decision or timeout
    processMessages engine

----------------------------------------------------------------------
-- Block Proposal
----------------------------------------------------------------------

-- | Propose a new block
proposeBlock :: ConsensusEngine -> IO ()
proposeBlock engine = do
    state <- readTVarIO (ceState engine)
    let round = csRound state
        vset  = csValidatorSet state

    -- Create block proposal
    -- In production, this would include pending transactions
    let blockHash = Protocol.BlockHash (Protocol.Hash (BS.replicate 32 0))
    let proposal = ProposalMsg
            { pmBlock      = undefined  -- Would be real block
            , pmRound      = round
            , pmValidRound = csValidRound state
            , pmProposer   = ceValidator engine
            , pmSignature  = signMessage engine (serializeProposal round (ceValidator engine))
            }

    -- Broadcast proposal
    let msg = CProposal proposal
    atomically $ do
        queue <- readTVarIO (ceMsgQueue engine)
        writeTVar (ceMsgQueue engine) (msg : queue)
        modifyTVar' (ceMetrics engine) $ \m ->
            m { cmBlocksProposed = cmBlocksProposed m + 1 }

    -- Update state
    atomically $ do
        modifyTVar' (ceState engine) $ \s ->
            s { csProposedBlock = Just (pmBlockHash proposal)
              , csStep = PrevotePhase
              }

----------------------------------------------------------------------
-- Message Handlers
----------------------------------------------------------------------

-- | Handle a proposal message
handleProposal :: ConsensusEngine -> ProposalMsg -> IO ()
handleProposal engine proposal = do
    state <- readTVarIO (ceState engine)
    let round = csRound state

    -- Verify proposal is for current round
    when (pmRound proposal == round) $ do
        -- Verify proposer is correct
        when (isRoundProposer round (csValidatorSet state) (pmProposer proposal)) $ do
            -- In production: validate block, check against locked values
            let shouldVote = case csLockedBlock state of
                    Nothing -> True
                    Just lockedHash
                        | pmBlockHash proposal == lockedHash -> True
                        | pmValidRound proposal > csLockedRound state -> True
                        | otherwise -> False

            when shouldVote $ do
                -- Send prevote
                sendPrevote engine (Just (pmBlockHash proposal))
                atomically $ modifyTVar' (ceState engine) $ \s ->
                    s { csStep = PrevotePhase }

-- | Handle a prevote message
handlePrevote :: ConsensusEngine -> PrevoteMsg -> IO ()
handlePrevote engine prevote = do
    state <- readTVarIO (ceState engine)
    let round = csRound state
        vset  = csValidatorSet state

    -- Collect prevotes and check for +2/3 majority
    let prevotes = collectVotes engine PrevotePhase round
    if superMajority vset (Set.fromList (map prSender prevotes))
        then do
            let blockHash = case map prBlockHash prevotes of
                    (Just h : _) -> Just h
                    _           -> Nothing

            -- Lock on the block if we have a polka
            atomically $ modifyTVar' (ceState engine) $ \s ->
                s { csLockedBlock = blockHash
                  , csLockedRound = Just round
                  , csValidBlock  = blockHash
                  , csValidRound  = Just round
                  , csStep        = PrecommitPhase
                  }

            -- Send precommit
            sendPrecommit engine blockHash
        else do
            -- Check for nil polka
            let nilPrevotes = filter (isNothing . prBlockHash) prevotes
            if superMajority vset (Set.fromList (map prSender nilPrevotes))
                then do
                    sendPrecommit engine Nothing
                    atomically $ modifyTVar' (ceState engine) $ \s ->
                        s { csStep = PrecommitPhase }
                else
                    -- Wait for more votes or timeout
                    return ()

-- | Handle a precommit message
handlePrecommit :: ConsensusEngine -> PrecommitMsg -> IO ()
handlePrecommit engine precommit = do
    state <- readTVarIO (ceState engine)
    let round = csRound state
        vset  = csValidatorSet state

    -- Collect precommits
    let precommits = collectVotes engine PrecommitPhase round
    if superMajority vset (Set.fromList (map pcSender precommits))
        then do
            let blockHash = case map pcBlockHash precommits of
                    (Just h : _) -> Just h
                    _           -> Nothing

            case blockHash of
                Just hash -> do
                    -- Commit the block
                    commitBlock engine hash
                    atomically $ modifyTVar' (ceState engine) $ \s ->
                        s { csDecision = Just hash
                          , csStep     = CommitPhase
                          }
                Nothing ->
                    -- No block committed, start next round
                    startNextRound engine round
        else
            return ()

-- | Handle a commit message
handleCommit :: ConsensusEngine -> CommitMsg -> IO ()
handleCommit engine commit = do
    state <- readTVarIO (ceState engine)
    when (csStep state == CommitPhase) $ do
        -- Verify commit matches our decision
        when (cmBlockHash commit == fromMaybe (cmBlockHash commit) (csDecision state)) $ do
            -- Finalize block
            finalizeBlock engine (cmBlockHash commit)

-- | Handle a view change
handleViewChange :: ConsensusEngine -> ViewChange -> IO ()
handleViewChange engine viewChange = do
    state <- readTVarIO (ceState engine)
    let vset = csValidatorSet state
        currentRound = csRound state

    -- Collect view change messages for the new view
    let viewChanges = collectViewChanges engine (vcNewView viewChange)
    if superMajority vset (Set.fromList (map vcSender viewChanges))
        then do
            -- Start new round with new view
            let newRound = ConsensusRound (unConsensusRound currentRound + 1)
            atomically $ modifyTVar' (ceState engine) $ \s ->
                s { csRound   = newRound
                  , csStep    = ProposePhase
                  }
            atomically $ modifyTVar' (ceMetrics engine) $ \m ->
                m { cmViewChanges = cmViewChanges m + 1 }
            runConsensusRound engine
        else
            return ()

----------------------------------------------------------------------
-- Vote Sending
----------------------------------------------------------------------

sendPrevote :: ConsensusEngine -> Maybe BlockHash -> IO ()
sendPrevote engine blockHash = do
    state <- readTVarIO (ceState engine)
    let prevote = PrevoteMsg
            { prBlockHash = blockHash
            , prRound     = csRound state
            , prSender    = ceValidator engine
            , prSignature = signMessage engine (serializePrevote blockHash (csRound state))
            }
    broadcastMessage engine (CPrevote prevote)

sendPrecommit :: ConsensusEngine -> Maybe BlockHash -> IO ()
sendPrecommit engine blockHash = do
    state <- readTVarIO (ceState engine)
    let precommit = PrecommitMsg
            { pcBlockHash = blockHash
            , pcRound     = csRound state
            , pcSender    = ceValidator engine
            , pcSignature = signMessage engine (serializePrecommit blockHash (csRound state))
            }
    broadcastMessage engine (CPrecommit precommit)

----------------------------------------------------------------------
-- Block Commit & Finalization
----------------------------------------------------------------------

-- | Commit a block to the chain
commitBlock :: ConsensusEngine -> BlockHash -> IO ()
commitBlock engine blockHash = do
    -- In production: write block to storage
    atomically $ modifyTVar' (ceMetrics engine) $ \m ->
        m { cmBlocksCommitted = cmBlocksCommitted m + 1 }

-- | Finalize a block after commit
finalizeBlock :: ConsensusEngine -> BlockHash -> IO ()
finalizeBlock engine blockHash = do
    atomically $ modifyTVar' (ceState engine) $ \s ->
        s { csDecision = Just blockHash }
    -- In production: update application state

----------------------------------------------------------------------
-- State Transitions
----------------------------------------------------------------------

-- | Transition to the next consensus step
transitionStep :: ConsensusEngine -> ConsensusStep -> IO ()
transitionStep engine newStep = do
    atomically $ modifyTVar' (ceState engine) $ \s ->
        s { csStep = newStep }

-- | Apply a consensus message to the state
applyConsensusMessage :: ConsensusEngine -> ConsensusMessage -> IO ()
applyConsensusMessage engine msg = case msg of
    CProposal p     -> handleProposal engine p
    CPrevote p      -> handlePrevote engine p
    CPrecommit p    -> handlePrecommit engine p
    CCommit c       -> handleCommit engine c
    CViewChange vc  -> handleViewChange engine vc
    CNewView nv     -> handleNewView engine nv

-- | Handle a timeout
timeoutHandler :: ConsensusEngine -> IO ()
timeoutHandler engine = do
    atomically $ modifyTVar' (ceMetrics engine) $ \m ->
        m { cmTimeouts = cmTimeouts m + 1 }
    startNextRound engine =<< readTVarIO (ceState engine)

----------------------------------------------------------------------
-- View Change Helpers
----------------------------------------------------------------------

handleNewView :: ConsensusEngine -> NewView -> IO ()
handleNewView engine newView = do
    state <- readTVarIO (ceState engine)
    let vset = csValidatorSet state
    -- Verify the new view is valid
    -- In production: verify pre-prepare messages
    let newRound = ConsensusRound (nvView newView)
    atomically $ modifyTVar' (ceState engine) $ \s ->
        s { csRound = newRound
          , csStep  = ProposePhase
          }

----------------------------------------------------------------------
-- Decision Making
----------------------------------------------------------------------

-- | Decide which block to commit
decideBlock :: ConsensusEngine -> IO (Maybe BlockHash)
decideBlock engine = do
    state <- readTVarIO (ceState engine)
    return $ csDecision state

-- | Check if this validator should propose in the current round
shouldPropose :: ConsensusRound -> ValidatorSet -> ValidatorId -> Bool
shouldPropose round vset validatorId =
    let proposer = roundProposer round vset
    in proposer == validatorId

-- | Determine the proposer for a given round (round-robin)
roundProposer :: ConsensusRound -> ValidatorSet -> ValidatorId
roundProposer (ConsensusRound round) vset =
    let active = activeValidators vset
        idx    = fromIntegral round `mod` length active
    in viAddress (active !! idx)

-- | Check if validator should prevote
shouldPrevote :: ConsensusEngine -> IO Bool
shouldPrevote engine = do
    state <- readTVarIO (ceState engine)
    return $ csStep state == PrevotePhase

-- | Check if validator should precommit
shouldPrecommit :: ConsensusEngine -> IO Bool
shouldPrecommit engine = do
    state <- readTVarIO (ceState engine)
    return $ csStep state == PrecommitPhase

-- | Check if a validator is the round proposer
isRoundProposer :: ConsensusRound -> ValidatorSet -> ValidatorId -> Bool
isRoundProposer = shouldPropose

----------------------------------------------------------------------
-- Message Collection
----------------------------------------------------------------------

-- | Collect votes for a given phase and round
collectVotes :: ConsensusEngine -> ConsensusStep -> ConsensusRound -> [a]
collectVotes engine phase round =
    -- In production: collect from message queue
    []

-- | Collect view change messages for a target view
collectViewChanges :: ConsensusEngine -> Word64 -> [ViewChange]
collectViewChanges engine targetView =
    -- In production: filter from message queue
    []

----------------------------------------------------------------------
-- Round Transition
----------------------------------------------------------------------

-- | Start the next consensus round
startNextRound :: ConsensusEngine -> ConsensusState -> IO ()
startNextRound engine state = do
    let newRound = ConsensusRound (unConsensusRound (csRound state) + 1)
    now <- getPOSIXTime
    atomically $ modifyTVar' (ceState engine) $ \s ->
        s { csRound       = newRound
          , csStep        = ProposePhase
          , csRoundStart  = now
          , csTimeout     = ccTimeoutPropose (ceConfig engine)
          }
    atomically $ modifyTVar' (ceMetrics engine) $ \m ->
        m { cmRoundsCompleted = cmRoundsCompleted m + 1 }

----------------------------------------------------------------------
-- Message Broadcasting
----------------------------------------------------------------------

broadcastMessage :: ConsensusEngine -> ConsensusMessage -> IO ()
broadcastMessage engine msg = do
    atomically $ do
        queue <- readTVarIO (ceMsgQueue engine)
        writeTVar (ceMsgQueue engine) (msg : queue)

----------------------------------------------------------------------
-- Message Processing Loop
----------------------------------------------------------------------

processMessages :: ConsensusEngine -> IO ()
processMessages engine = do
    state <- readTVarIO (ceState engine)
    -- Process all pending messages
    messages <- atomically $ do
        queue <- readTVarIO (ceMsgQueue engine)
        writeTVar (ceMsgQueue engine) []
        return queue
    mapM_ (applyConsensusMessage engine) messages

----------------------------------------------------------------------
-- Signing Helpers
----------------------------------------------------------------------

signMessage :: ConsensusEngine -> ByteString -> Signature
signMessage engine data_ =
    case Crypto.sign (cePrivKey engine) data_ of
        Just sig -> sig
        Nothing  -> Signature BS.empty  -- Should not happen in practice

----------------------------------------------------------------------
-- Serialization Helpers
----------------------------------------------------------------------

serializeProposal :: ConsensusRound -> ValidatorId -> ByteString
serializeProposal round validator = BS.concat
    [ serializeConsensusRound round
    , serializeValidatorId validator
    ]

serializePrevote :: Maybe BlockHash -> ConsensusRound -> ByteString
serializePrevote mHash round = BS.concat
    [ case mHash of
        Just h  -> serializeBlockHash h
        Nothing -> BS.replicate 32 0
    , serializeConsensusRound round
    ]

serializePrecommit :: Maybe BlockHash -> ConsensusRound -> ByteString
serializePrecommit mHash round = serializePrevote mHash round

serializeConsensusRound :: ConsensusRound -> ByteString
serializeConsensusRound (ConsensusRound w) =
    BS.pack [ fromIntegral (w `shiftR` 56)
            , fromIntegral (w `shiftR` 48)
            , fromIntegral (w `shiftR` 40)
            , fromIntegral (w `shiftR` 32)
            , fromIntegral (w `shiftR` 24)
            , fromIntegral (w `shiftR` 16)
            , fromIntegral (w `shiftR` 8)
            , fromIntegral w
            ]

serializeValidatorId :: ValidatorId -> ByteString
serializeValidatorId (ValidatorId (Address b)) = b

serializeBlockHash :: BlockHash -> ByteString
serializeBlockHash (BlockHash (Hash b)) = b

----------------------------------------------------------------------
-- Query Functions
----------------------------------------------------------------------

engineState :: ConsensusEngine -> IO ConsensusState
engineState = readTVarIO . ceState

engineConfig :: ConsensusEngine -> ConsensusConfig
engineConfig = ceConfig

engineValidatorSet :: ConsensusEngine -> IO ValidatorSet
engineValidatorSet engine = csValidatorSet <$> readTVarIO (ceState engine)

engineLatestBlock :: ConsensusEngine -> IO (Maybe BlockHash)
engineLatestBlock engine = csDecision <$> readTVarIO (ceState engine)

</content>

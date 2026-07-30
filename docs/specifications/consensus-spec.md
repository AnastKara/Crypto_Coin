# Crypto_Coin Consensus Protocol Specification v0.1

## 1. Overview

The Crypto_Coin consensus protocol is a Byzantine Fault Tolerant (BFT)
consensus algorithm based on Tendermint-style consensus with modifications
for improved liveness and accountability. It provides:

- **Safety**: No two correct validators decide on different blocks at the same height
- **Liveness**: The protocol eventually commits a new block under partial synchrony
- **Instant finality**: A committed block is immediately final with no forks
- **Accountability**: Validator misbehavior can be detected and proven

## 2. System Model

### 2.1 Network Assumptions

- **Partial synchrony**: Network is initially asynchronous but becomes synchronous
  after a known Global Stabilization Time (GST)
- **Authenticated channels**: All messages are signed and verified
- **Reliable broadcast**: Messages eventually reach all correct validators

### 2.2 Validator Model

- Set of `n` validators, each with a voting power (stake)
- Byzantine fault threshold: `f` where `n = 3f + 1`
- A supermajority is `2f + 1` validators by voting power
- Validators can be: correct (follow protocol), faulty (arbitrary behavior)

### 2.3 Timing Model

The protocol uses timeouts to ensure liveness:

- `timeoutPropose`: Wait for proposal after round start
- `timeoutPrevote`: Wait for prevotes after proposal
- `timeoutPrecommit`: Wait for precommits after +2/3 prevote

Timeouts increase exponentially with round number to handle network congestion.

## 3. Protocol State

Each validator maintains:

```
type Round = ℕ
type Height = ℕ

State = {
    height: Height
    round: Round
    step: { Propose, Prevote, Precommit, Commit }
    lockedValue: Option<BlockHash>
    lockedRound: Option<Round>
    validValue: Option<BlockHash>
    validRound: Option<Round>
    decision: Option<BlockHash>
}
```

### State Transition Rules

1. **lock**: A validator locks on a value `v` at round `r` when it receives
   a polka (supermajority of prevotes) for `v` at round `r`.

2. **unlock**: A validator unlocks when it receives a polka for a different
   value at a higher round, or when it participates in a view change.

3. **valid**: A value is considered valid if the validator has seen a polka
   for it at any round ≥ the current locked round.

## 4. Protocol Steps

### Round Structure

Each consensus round `r` proceeds through four steps:

```
Round r:
  1. Propose:   Proposer broadcasts a block proposal
  2. Prevote:   Validators vote on the proposal
  3. Precommit: Validators commit to the proposal if +2/3 prevotes
  4. Commit:    Block is finalized if +2/3 precommits
```

### Step 1: Propose (timeout: timeoutPropose)

The round proposer broadcasts a `Proposal` message containing:

- The proposed block
- The current round number
- The validRound (highest round with a valid polka known to proposer)
- A signature

**Validators**:
- Wait for the proposal
- If no proposal received within timeoutPropose, send nil prevote
- If locked on a block, only accept proposal for that block or from higher validRound

### Step 2: Prevote (timeout: timeoutPrevote)

Validators broadcast a `Prevote` message:

- `prevote(v)`: Vote for block with hash `v`
- `prevote(nil)`: Vote for nil (no block)

**Rules**:
1. If the proposal is valid and not conflicting with lock:
   - Send `prevote(hash(proposal))`
2. If the proposal is invalid or conflicts with lock:
   - Send `prevote(nil)`
3. After timeout: send `prevote(nil)`

### Step 3: Precommit (timeout: timeoutPrecommit)

Validators collect prevotes from the network:

**Rules**:
1. If +2/3 prevotes for some block hash `v`:
   - Lock on `v` at round `r`
   - Send `precommit(v)`
2. If +2/3 prevotes for nil (or timeout):
   - Send `precommit(nil)`

### Step 4: Commit

Validators collect precommits:

**Rules**:
1. If +2/3 precommits for block hash `v`:
   - Commit block `v`
   - Broadcast commit proof
2. If +2/3 precommits for nil:
   - Start next round immediately

## 5. View Change Protocol

When a round fails to commit (timeout), validators initiate a view change:

1. Validator broadcasts a `ViewChange` message with:
   - New view (round) number
   - Latest known committed block
   - Set of +2/3 prevotes from previous round (if any)

2. The proposer of the new round aggregates ViewChange messages:
   - If +2/3 validators support the view change, broadcast `NewView` message
   - Include prevote set for validValue

3. Validators accept the NewView and start the new round

## 6. Fork Choice Rule

Crypto_Coin uses a **simple fork choice rule** because instant finality
eliminates forks:

- The canonical chain is always the chain with the highest committed block
- Validators commit blocks sequentially at each height
- No reorganizations are possible after commit

## 7. Safety and Liveness Proofs

### Safety Proof (Sketch)

**Theorem**: No two correct validators commit different blocks at the same height.

**Proof**:
1. Assume two validators commit blocks `B1` and `B2` at height `h`
2. Commit requires +2/3 precommits for the respective block
3. Since sets of +2/3 validators intersect (by quorum intersection), at least
   one correct validator must have precommitted for both
4. A correct validator only precommits after seeing +2/3 prevotes for that block
5. A correct validator cannot have +2/3 prevotes for two different blocks
   (quorum intersection again)
6. Contradiction: therefore, only one block can be committed at each height

### Liveness Proof (Sketch)

**Theorem**: Under eventual synchrony, the protocol eventually commits a block.

**Proof**:
1. After GST, messages arrive within bounded time
2. The proposer for each round is known and proposers cycle through validators
3. Eventually a correct proposer is selected
4. The correct proposer's proposal is delivered to all validators
5. With increasing timeouts, validators will reach consensus on the proposal
6. Therefore, after a bounded number of rounds, a block is committed

## 8. Accountability

Validators who violate the protocol can be detected through:

- **Double signing**: Signing two different messages at the same height/round/step
- **Equivocation**: Proposing two different blocks in the same round
- **Invalid messages**: Proposing blocks that violate protocol rules

Evidence is submitted on-chain and results in:
- Slashing of staked tokens
- Removal from validator set
- Jailing (temporary inability to participate)

## 9. Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `timeoutPropose` | 3s | Initial propose timeout |
| `timeoutPrevote` | 1s | Initial prevote timeout |
| `timeoutPrecommit` | 1s | Initial precommit timeout |
| `timeoutMultiplier` | 2 | Exponential backoff multiplier |
| `maxRound` | ∞ | Maximum rounds before forced view change |
| `blockSize` | 2MB | Maximum block size |


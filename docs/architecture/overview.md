# Crypto_Coin Blockchain Architecture

## Overview

Crypto_Coin is a next-generation Layer-1 blockchain designed from the ground up
for security, scalability, and formal correctness. The architecture is divided into
three primary layers:

```text
┌─────────────────────────────────────────────────────────┐
│                      Application Layer                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │  Wallet  │  │  Explorer│  │  dApps   │  │  Tools  │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬────┘ │
├───────┴──────────────┴──────────────┴──────────────┴────┤
│                      Node Layer (Rust)                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │   P2P    │  │   API    │  │  Storage │  │  Sync   │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │
├─────────────────────────────────────────────────────────┤
│               Formal Protocol Layer (Haskell)             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │ Consensus│  │ Protocol │  │   BFT    │  │  Crypto │ │
│  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Design Principles

### 1. Formal Correctness First
Protocol specifications are written in Haskell, enabling mathematical verification
of critical properties before implementation. The Haskell layer defines:

- **State transition functions** with determinism guarantees
- **Consensus rules** with Byzantine fault tolerance proofs
- **Invariant checking** for blockchain consistency

### 2. Performance Through Rust
The node runtime is implemented in Rust, providing:

- Memory safety without garbage collection
- Zero-cost abstractions for critical paths
- Fine-grained control over I/O and concurrency
- FFI bridge to the Haskell formal core

### 3. Security by Design
- **Memory safety**: Rust runtime prevents memory corruption
- **Type safety**: Haskell's type system eliminates invalid states
- **BFT consensus**: Tolerates up to 1/3 Byzantine validators
- **Formal verification**: Property-based testing of all protocol invariants

## Layer Architecture

### Formal Protocol Layer (Haskell)

This layer contains the mathematically verified protocol core:

| Module | Purpose |
|--------|---------|
| `CryptoCoin.Protocol.Types` | Core data types and hash primitives |
| `CryptoCoin.Protocol.Block` | Block structure and validation |
| `CryptoCoin.Protocol.State` | UTXO-based state machine |
| `CryptoCoin.Protocol.Merkle` | Merkle proof verification |
| `CryptoCoin.Protocol.Crypto` | Cryptographic primitives |
| `CryptoCoin.Consensus.Types` | Consensus state types |
| `CryptoCoin.Consensus.Engine` | BFT consensus engine |
| `CryptoCoin.Consensus.Finality` | Finality rules and proofs |
| `CryptoCoin.Consensus.ForkChoice` | Fork choice rule |
| `CryptoCoin.Consensus.BFT` | Byzantine fault tolerance |

### Node Layer (Rust)

| Module | Purpose |
|--------|---------|
| `crypto-coin-node-core` | Runtime, configuration, metrics |
| `crypto-coin-p2p` | Peer-to-peer networking |
| `crypto-coin-storage` | Blockchain storage |
| `crypto-coin-api` | RPC and WebSocket API |

### Cryptography (Rust)

| Module | Purpose |
|--------|---------|
| `crypto-coin-merkle` | Merkle tree proofs |
| `crypto-coin-signatures` | Ed25519 signatures and key generation |

## Consensus Architecture

The blockchain uses a **Hybrid BFT + PoS Consensus**:

1. **Round-robin proposer selection** weighted by stake
2. **Two-phase voting** (prevote + precommit) for safety
3. **View change protocol** for liveness under faults
4. **Instant finality** with no fork possibility
5. **Optimistic responsiveness** adapting to network conditions

### Consensus Flow

```text
Round Start
    │
    ▼
[Propose] ──► [Prevote] ──► [Precommit] ──► [Commit]
    │            │               │              │
    └────────────┴───────────────┴──────────────┘
                    │
               [View Change]
                 (on timeout)
```

## State Model (Extended UTXO)

The blockchain uses an extended UTXO (Unspent Transaction Output) model:

- **UTXO-based**: Each output is a first-class object with a unique ID
- **Smart contracts**: Scripts attached to UTXOs enable programmability
- **Deterministic**: All state transitions are purely functional
- **Provably correct**: Invariants checked at every transition

## Security Model

### Byzantine Fault Tolerance
- **Threshold**: Tolerates f faulty nodes out of n = 3f + 1
- **Safety**: No two correct nodes decide on conflicting blocks
- **Liveness**: Under partial synchrony, protocol eventually commits
- **Accountability**: Malicious behavior can be proven and penalized

### Cryptographic Primitives
- **Signatures**: Ed25519 (EdDSA on Curve25519)
- **Hashing**: SHA3-256
- **Merkle proofs**: Balanced binary Merkle tree
- **Addresses**: Blake2b-160 from public key


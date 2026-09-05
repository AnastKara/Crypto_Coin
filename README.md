# Crypto_Coin

**A Formally Verified Layer-1 Blockchain**
*Protocol correctness specified in Haskell — production performance implemented in Rust.*

![Status](https://img.shields.io/badge/status-development-orange)
![Version](https://img.shields.io/badge/version-0.1.0-blue)
![Rust](https://img.shields.io/badge/Rust-1.70%2B-dea584)
![Haskell](https://img.shields.io/badge/Haskell-GHC%209.6%2B-5e5086)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture](#architecture)
- [Design Decisions](#design-decisions)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Testing](#testing)
- [Documentation](#documentation)
- [Development Status](#development-status)
- [Security](#security)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Crypto_Coin is a next-generation Layer-1 blockchain designed from the ground up for
**formal correctness**, **security**, and **scalability**. It combines two complementary
engineering disciplines:

- **Haskell** — a mathematically rigorous, purely functional specification of the
  protocol core (block structure, UTXO state machine, and Byzantine Fault Tolerant
  consensus), enabling property-based verification of critical invariants.
- **Rust** — a memory-safe, high-performance node implementation (networking, storage,
  API, and cryptography) that mirrors the formally specified behavior.

This "correctness-first, performance-second" philosophy separates the *protocol
definition* from the *node runtime*, allowing each to be independently modeled,
verified, and optimized. The result is a consensus layer with **instant finality**,
an **extended UTXO state model**, and a **comprehensive formal verification framework**.

## Key Features

- **Instant Finality, No Forks** — Hybrid BFT + PoS consensus with `2/3+`
  supermajority commits; committed blocks are immediately final and can never
  be reorganized.
- **Byzantine Fault Tolerance** — Safety and liveness under `f` faulty validators
  for `n = 3f + 1`; equates to provable accountability and slashing of misbehavior.
- **Extended UTXO State Model** — Purely functional, deterministic state transitions;
  each output is a first-class object enabling parallel execution and smart-contract
  programming.
- **Formal Verification** — QuickCheck property suites (40+ properties) validating
  deterministic execution, UTXO conservation, no double spends, Merkle proof
  soundness, consensus safety, and liveness.
- **Modern Cryptography** — Ed25519 signatures, SHA3-256 hashing, Blake2b-160 address
  derivation, HKDF key derivation, VRF primitives, and commit/reveal schemes.
- **Asynchronous Node Runtime** — Tokio-based networking with Kademlia-inspired peer
  discovery, gossip propagation, JSON-RPC/WebSocket APIs, and metrics collection.

## Architecture

Crypto_Coin is organized into three layers. The formal protocol layer (Haskell)
defines *what* the protocol guarantees; the node layer (Rust) implements *how* those
guarantees are delivered at production speed.

```text
┌───────────────────────────────────────────────────────────────┐
│                    Application Layer                            │
│      Wallet │ Explorer │ dApps │ Tools │ RPC / WebSocket       │
├───────────────────────────────────────────────────────────────┤
│                     Node Layer (Rust)                           │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────────┐   │
│   │   P2P   │  │   API   │  │ Storage │  │ Node Core       │   │
│   │ Network │  │  RPC/WS │  │  Layer  │  │ Config / Metrics│   │
│   └─────────┘  └─────────┘  └─────────┘  └─────────────────┘   │
├───────────────────────────────────────────────────────────────┤
│               Formal Protocol Layer (Haskell)                   │
│   ┌──────────────┐  ┌──────────────┐  ┌─────────────────────┐   │
│   │ Protocol Core│  │  Consensus   │  │  Verification       │   │
│   │ Types/Block/ │  │  Engine /    │  │  QuickCheck         │   │
│   │ State/Merkle │  │  BFT View    │  │  Property Suites    │   │
│   └──────────────┘  └──────────────┘  └─────────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

The consensus flow follows a classic Tendermint-style round structure, extended with
exponential timeout backoff and view-change handling for liveness under faults:

```text
Round Start
    │
    ▼
[Propose] ──► [Prevote] ──► [Precommit] ──► [Commit]   (instant finality)
    │            │               │              │
    └────────────┴───────────────┴──────────────┘
                    │
               [View Change]
                 (on timeout)
```

## Design Decisions

| Concern          | Decision                       | Rationale                                        |
|------------------|--------------------------------|--------------------------------------------------|
| Consensus        | Hybrid BFT + PoS               | Instant finality, optimistic responsiveness      |
| State model      | Extended UTXO                  | Formal verifiability, parallel execution         |
| Finality         | `2/3+` supermajority BFT       | Byzantine fault tolerance (`n = 3f + 1`)         |
| Signatures       | Ed25519 + BLS (planned)        | Security + validator efficiency                  |
| Hashing          | SHA3-256                       | NIST standard, well-analyzed                     |
| Addresses        | Blake2b-160 from public key    | Compact, collision-resistant                     |
| Peer discovery   | Kademlia-inspired DHT          | Scalable, self-healing network topology          |
| Specification    | Haskell → Rust                 | Correctness first, performance second            |

## Repository Structure

```text
Crypto_Coin/
├── Cargo.toml                 # Rust workspace manifest (7 crates)
├── cabal.project              # Haskell Cabal project (formal layer)
├── PLAN.md                    # Development plan & status tracker
│
├── crypto/                    # Cryptography (Rust)
│   ├── merkle/                #   crypto-coin-merkle — balanced Merkle trees & proofs
│   └── signatures/            #   crypto-coin-signatures — Ed25519, VRF, commitments
│
├── node/                      # Node runtime (Rust)
│   ├── node-core/             #   crypto-coin-node-core — runtime, config, metrics
│   ├── p2p/                   #   crypto-coin-p2p — transport, gossip, discovery
│   ├── storage/               #   crypto-coin-storage — block store & state DB
│   └── api/                   #   crypto-coin-api — JSON-RPC / REST / WebSocket
│
├── formal-protocol/           # Formal protocol specification (Haskell)
│   ├── crypto-coin-protocol/  #   Types, Block, State, Merkle, Crypto
│   ├── crypto-coin-consensus/ #   Consensus Engine + BFT types
│   └── (tests)                #   QuickCheck property suites (40+ properties)
│
├── tests/
│   └── integration/           # Multi-node integration test framework (8 scenarios)
│
├── docs/                      # Technical documentation
│   ├── architecture/          #   overview.md — system architecture
│   ├── specifications/        #   consensus-spec.md, formal-methods.md
│   └── whitepaper/            #   section-01-introduction.md
│
└── scripts/
    ├── setup.ps1              # Windows toolchain setup (Rust + Haskell)
    ├── build_rust.bat         # Windows Rust build (GNU target)
    ├── test.ps1               # Windows test runner (Rust + Haskell)
    └── build.sh               # Unix build script
```

## Getting Started

### Prerequisites

| Component  | Required Version | Installer                                         |
|------------|------------------|---------------------------------------------------|
| Rust       | 1.70+            | [rustup](https://rustup.rs)                       |
| Haskell    | GHC 9.6+         | [GHCup](https://www.haskell.org/ghcup/)           |
| Cabal/Stack| Cabal 3.10+      | Bundled with GHCup                                |

> On Windows, a MinGW-w64 (UCRT64) toolchain is recommended for the GNU build
> target — see `.cargo/config.toml` for linker configuration.

### Setup

The repository provides one-command environment setup on Windows:

```powershell
# Windows — installs Rust + Haskell toolchains and builds the workspace
.\scripts\setup.ps1
```

Or install toolchains manually, then:

```bash
# Unix / WSL
./scripts/build.sh
```

### Build

```bash
# Build the entire Rust workspace (node + crypto + tests)
cargo build --release

# Build a single crate
cargo build -p crypto-coin-node-core

# Build the Haskell formal protocol layer
cd formal-protocol && cabal build all
```

### Run Tests

```bash
# Rust: unit tests across all workspace crates + multi-node integration tests
cargo test --workspace

# Haskell: QuickCheck property tests for protocol & consensus invariants
cd formal-protocol && cabal test all

# Or run the bundled test orchestration
pwsh ./scripts/test.ps1          # Windows
```

## Testing

Crypto_Coin exercises correctness at every layer:

- **Rust unit tests** — Merkle proof generation/verification (incl. tamper rejection),
  signature/VRF/commitment correctness, deterministic key derivation.
- **Rust integration tests** (`tests/integration`) — an 8-scenario, multi-node
  harness covering:
  - Happy path consensus across `n` honest validators
  - BFT threshold behavior (`n = 3f + 1`) and threshold-exceeded rejection
  - Network partitions and recovery
  - Message delays and consistency verification
- **Haskell property tests** — QuickCheck suites (`ProtocolProperties`,
  `ConsensusProperties`) validating:
  - Deterministic state transitions
  - UTXO conservation & no double spend
  - Merkle proof soundness
  - Consensus safety, liveness, non-equivocation, and view-change validity

## Documentation

| Document | Path |
|----------|------|
| Architecture Overview | [`docs/architecture/overview.md`](docs/architecture/overview.md) |
| Consensus Protocol Specification | [`docs/specifications/consensus-spec.md`](docs/specifications/consensus-spec.md) |
| Formal Methods & Verification | [`docs/specifications/formal-methods.md`](docs/specifications/formal-methods.md) |
| Whitepaper | [`docs/whitepaper/section-01-introduction.md`](docs/whitepaper/section-01-introduction.md) |
| Development Plan | [`PLAN.md`](PLAN.md) |
## Development Status

Crypto_Coin is in **active development** (pre-alpha, v0.1.0). Current milestones:

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Environment & scaffold | ✅ Complete |
| 2 | Protocol whitepaper & specifications | ✅ Complete |
| 3 | Haskell protocol core (types, block, state, crypto) | ✅ Complete |
| 4 | Haskell BFT consensus engine | ✅ Complete |
| 5 | Formal verification (QuickCheck suites) | ✅ Complete |
| 6 | Rust cryptography crates (Merkle, Ed25519, VRF) | ✅ Complete |
| 7 | Rust node runtime (core, P2P, storage, API) | ✅ Complete |
| 8 | Integration & system testing | ✅ Complete |
| 9 | Documentation & whitepaper | ✅ Complete |

Planned next steps include full proof-assistant formalization (Coq/Agda), BLS
aggregate signatures, smart-contract execution, and mainnet hardening.

## Security

> ⚠️ **Disclaimer**: Crypto_Coin is under active development and has **not
> undergone security review**. It is intended for research and development only.
> Do **not** use it to hold or transfer real value.

Security-sensitive considerations are treated with priority throughout the project:

- Byzantine fault tolerance with provable safety and liveness
- Memory safety guaranteed by Rust; invalid states made unrepresentable by Haskell
- Deterministic, authenticated, and signed protocol messages
- On-chain accountability and slashing channels for validator misbehavior

Please report vulnerabilities confidentially to the maintainers before disclosure.

## Contributing

Contributions are welcome! To get started:

1. Fork the repository and create a feature branch.
2. Follow existing code conventions (module layout, documentation style, tests).
3. Ensure your changes compile and pass the full test suite
   (`cargo test --workspace` and `cabal test all`).
4. Open a pull request with a clear description and references to related issues.

For proposals that affect protocol semantics (consensus rules, state transitions,
or cryptographic primitives), please open a discussion in the spec documentation
first — protocol changes require formal-specification updates and updated properties.

## License

This project is licensed under the [MIT License](LICENSE). See the `LICENSE` file
for details.

---

*Copyright © 2025-2026 Crypto_Coin Team — built for correctness, verified by proof.*
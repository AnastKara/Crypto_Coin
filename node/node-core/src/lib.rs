//! # Crypto_Coin Node Core
//!
//! This module implements the core blockchain node runtime.
//! It coordinates the consensus engine, P2P networking, storage,
//! and API layers into a unified node.
//!
//! ## Architecture
//!
//! ```text
//! ┌────────────────────────────────────────────┐
//! │               Node Runtime                 │
//! ├──────────┬──────────┬──────────┬───────────┤
//! │ Consensus│   P2P    │ Storage  │    API    │
//! │  Engine  │ Network  │  Layer   │  Service  │
//! └──────────┴──────────┴──────────┴───────────┘
//!         │          │         │          │
//!         └──────────┴─────────┴──────────┘
//!                    │
//!           ┌────────┴────────┐
//!           │ Configuration  │
//!           └────────────────┘
//! ```

use std::sync::Arc;
use std::net::SocketAddr;
use tokio::sync::{RwLock, mpsc};
use tokio::task::JoinHandle;
use std::collections::HashMap;
use std::time::Duration;

pub mod config;
pub mod runtime;
pub mod metrics;
pub mod error;

// ---------------------------------------------------------------------------
// Re-exports
// ---------------------------------------------------------------------------

pub use config::NodeConfig;
pub use runtime::NodeRuntime;
pub use error::NodeError;

// ---------------------------------------------------------------------------
// Node Core Types
// ---------------------------------------------------------------------------

/// Node identifier (public key hash)
#[derive(Clone, PartialEq, Eq, Hash, Debug)]
pub struct NodeId(pub [u8; 20]);

impl NodeId {
    pub fn from_bytes(bytes: &[u8]) -> Self {
        let mut arr = [0u8; 20];
        let len = bytes.len().min(20);
        arr[..len].copy_from_slice(&bytes[..len]);
        NodeId(arr)
    }
}

/// Block height
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Debug)]
pub struct BlockHeight(pub u64);

impl BlockHeight {
    pub const GENESIS: BlockHeight = BlockHeight(0);

    pub fn increment(&self) -> BlockHeight {
        BlockHeight(self.0 + 1)
    }
}

impl std::fmt::Display for BlockHeight {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

/// Node synchronization status
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum SyncStatus {
    /// Node is still bootstrapping
    Booting,
    /// Node is catching up with the network
    Syncing { current_height: BlockHeight, target_height: BlockHeight },
    /// Node is in sync and participating in consensus
    InSync,
    /// Node has stalled or encountered an error
    Stalled,
}

impl std::fmt::Display for SyncStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SyncStatus::Booting => write!(f, "Booting"),
            SyncStatus::Syncing { current, target } => {
                write!(f, "Syncing ({}/{})", current, target)
            }
            SyncStatus::InSync => write!(f, "In Sync"),
            SyncStatus::Stalled => write!(f, "Stalled"),
        }
    }
}

/// Node runtime information
#[derive(Clone, Debug)]
pub struct NodeInfo {
    pub node_id: NodeId,
    pub version: String,
    pub uptime_secs: u64,
    pub sync_status: SyncStatus,
    pub latest_block_height: BlockHeight,
    pub peer_count: usize,
    pub is_validator: bool,
}

// ---------------------------------------------------------------------------
// Event System
// ---------------------------------------------------------------------------

/// Events emitted by the node runtime
#[derive(Clone, Debug)]
pub enum NodeEvent {
    /// Node has started
    Started,
    /// Node is shutting down
    ShuttingDown(String),
    /// Node has synced to the chain tip
    SyncedToTip(BlockHeight),
    /// New block was committed
    BlockCommitted(BlockHeight),
    /// Consensus round started
    RoundStarted(u64),
    /// Peer connected
    PeerConnected(NodeId, SocketAddr),
    /// Peer disconnected
    PeerDisconnected(NodeId),
    /// Error occurred
    Error(String),
    /// Metrics snapshot
    MetricsTick,
}

// ---------------------------------------------------------------------------
/// Node metrics
// ---------------------------------------------------------------------------

#[derive(Clone, Default, Debug)]
pub struct NodeMetrics {
    pub blocks_received: u64,
    pub blocks_proposed: u64,
    pub transactions_processed: u64,
    pub peers_connected: u32,
    pub mempool_size: usize,
    pub cpu_usage: f64,
    pub memory_usage_bytes: u64,
    pub network_bytes_in: u64,
    pub network_bytes_out: u64,
}

// ---------------------------------------------------------------------------
// Cargo.toml located at node/node-core/


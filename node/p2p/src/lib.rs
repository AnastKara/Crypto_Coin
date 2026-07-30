//! # Crypto_Coin P2P Networking Layer
//!
//! This module implements the peer-to-peer networking layer using
//! a distributed hash table (DHT) for peer discovery and a
//! gossip protocol for message propagation.
//!
//! ## Architecture
//!
//! ```text
//! ┌───────────────────────────────────────────────┐
//! │              P2PManager                       │
//! ├──────────┬──────────┬────────────────────────┤
//! │ Transport│Protocol  │ Discovery               │
//! │ (TCP)    │ (Frames) │ (Kademlia DHT)          │
//! └──────────┴──────────┴────────────────────────┘
//! ```
//!
//! ## Protocol
//! - Kademlia-inspired DHT for peer discovery
//! - GossipSub-style message propagation
//! - TCP-based reliable transport with noise encryption
//! - Peer scoring and reputation system

pub mod transport;
pub mod protocol;
pub mod discovery;

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::{RwLock, mpsc, broadcast};
use std::time::{Duration, Instant};

use transport::{TransportManager, TransportConfig, TransportEvent};
use discovery::{DiscoveryManager, DiscoveryConfig, DiscoveryEvent};

/// A peer in the network
#[derive(Clone, Debug)]
pub struct PeerInfo {
    pub id: [u8; 32],
    pub addr: SocketAddr,
    pub public_key: [u8; 32],
    pub agent_version: String,
    pub latest_height: u64,
    pub is_validator: bool,
    pub connected_since: Instant,
    pub score: f64,
}

/// P2P network configuration
#[derive(Clone, Debug)]
pub struct P2PConfig {
    pub listen_addr: SocketAddr,
    pub external_addr: Option<SocketAddr>,
    pub bootstrap_peers: Vec<SocketAddr>,
    pub max_peers: usize,
    pub gossip_fanout: usize,
    pub heartbeat_interval: Duration,
    pub dial_timeout: Duration,
}

impl Default for P2PConfig {
    fn default() -> Self {
        Self {
            listen_addr: "0.0.0.0:26656".parse().unwrap(),
            external_addr: None,
            bootstrap_peers: vec![],
            max_peers: 50,
            gossip_fanout: 8,
            heartbeat_interval: Duration::from_secs(10),
            dial_timeout: Duration::from_secs(5),
        }
    }
}

impl From<P2PConfig> for TransportConfig {
    fn from(config: P2PConfig) -> Self {
        TransportConfig {
            listen_addr: config.listen_addr,
            dial_timeout: config.dial_timeout,
            ..Default::default()
        }
    }
}

impl From<P2PConfig> for DiscoveryConfig {
    fn from(config: P2PConfig) -> Self {
        DiscoveryConfig {
            bootstrap_peers: config.bootstrap_peers.clone(),
            max_peers: config.max_peers,
            ..Default::default()
        }
    }
}

/// P2P network event
#[derive(Clone, Debug)]
pub enum P2PEvent {
    PeerConnected([u8; 32], SocketAddr),
    PeerDisconnected([u8; 32]),
    MessageReceived(P2PMessage),
    Heartbeat,
}

/// Types of P2P messages
#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub enum P2PMessage {
    /// Block proposal
    BlockProposal(Vec<u8>),
    /// Consensus vote
    ConsensusVote(Vec<u8>),
    /// Transaction broadcast
    Transaction(Vec<u8>),
    /// Peer discovery request
    FindPeer(Vec<u8>),
    /// Peer discovery response
    PeerList(Vec<u8>),
    /// Sync request
    SyncRequest(Vec<u8>),
    /// Sync response
    SyncResponse(Vec<u8>),
    /// Ping/Pong
    Ping,
    Pong,
}

/// P2P network manager
pub struct P2PManager {
    config: P2PConfig,
    transport: Arc<RwLock<TransportManager>>,
    discovery: Arc<RwLock<DiscoveryManager>>,
    peers: Arc<RwLock<HashMap<[u8; 32], PeerInfo>>>,
    event_tx: broadcast::Sender<P2PEvent>,
    message_tx: mpsc::Sender<(P2PMessage, [u8; 32])>,
}

impl P2PManager {
    pub fn new(config: P2PConfig) -> Self {
        let (event_tx, _) = broadcast::channel(256);
        let (message_tx, _) = mpsc::channel(1024);

        let transport = TransportManager::new(config.clone().into());
        let discovery = DiscoveryManager::new(config.clone().into());

        Self {
            config,
            transport: Arc::new(RwLock::new(transport)),
            discovery: Arc::new(RwLock::new(discovery)),
            peers: Arc::new(RwLock::new(HashMap::new())),
            event_tx,
            message_tx,
        }
    }

    /// Start P2P networking (runs the listener)
    pub async fn start(&self) -> Result<(), Box<dyn std::error::Error>> {
        log::info!("P2P listening on {}", self.config.listen_addr);

        // Bootstrap from seed peers
        let mut discovery = self.discovery.write().await;
        discovery.bootstrap().await;

        // Connect to known peers
        let peers_to_connect = discovery.peers_to_connect(self.config.max_peers);
        drop(discovery);

        let mut transport = self.transport.write().await;
        for (addr, _) in peers_to_connect {
            if let Err(e) = transport.dial(addr).await {
                log::warn!("Failed to dial {}: {}", addr, e);
            }
        }
        drop(transport);

        Ok(())
    }

    /// Dial a remote peer
    pub async fn dial_peer(&self, addr: SocketAddr) -> Result<(), Box<dyn std::error::Error>> {
        log::debug!("Dialing peer at {}", addr);
        let mut transport = self.transport.write().await;
        transport.dial(addr).await.map_err(|e| Box::new(std::io::Error::new(std::io::ErrorKind::Other, e.to_string())))?;
        Ok(())
    }

    /// Broadcast a message to all peers
    pub async fn broadcast(&self, msg: P2PMessage) {
        let mut transport = self.transport.write().await;
        transport.broadcast(&msg).await;
    }

    /// Send a message to a specific peer
    pub async fn send_to(&self, msg: P2PMessage, peer_id: [u8; 32]) {
        let mut transport = self.transport.write().await;
        let _ = transport.send(&peer_id, &msg).await;
    }

    /// Subscribe to P2P events
    pub fn subscribe(&self) -> broadcast::Receiver<P2PEvent> {
        self.event_tx.subscribe()
    }

    /// Get connected peer count
    pub async fn peer_count(&self) -> usize {
        self.transport.read().await.active_connections()
    }

    /// Get list of connected peers
    pub async fn peer_list(&self) -> Vec<PeerInfo> {
        self.peers.read().await.values().cloned().collect()
    }
}

impl Drop for P2PManager {
    fn drop(&mut self) {
        log::debug!("P2PManager dropped");
    }
}


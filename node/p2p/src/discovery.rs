//! Peer discovery module for Crypto_Coin P2P network
//!
//! Implements a Kademlia-inspired distributed hash table for peer discovery,
//! with periodic bootstrapping and peer exchange.

use crate::protocol::PeerRecord;
use std::collections::{HashMap, HashSet};
use std::net::SocketAddr;
use std::time::{Duration, Instant};
use rand::seq::SliceRandom;

/// Discovery configuration
#[derive(Clone, Debug)]
pub struct DiscoveryConfig {
    /// Bootstrap peers
    pub bootstrap_peers: Vec<SocketAddr>,
    /// Maximum number of peers in routing table
    pub max_peers: usize,
    /// How often to bootstrap
    pub bootstrap_interval: Duration,
    /// Peer exchange interval
    pub pex_interval: Duration,
    /// Peer timeout (remove if not seen)
    pub peer_timeout: Duration,
    /// Target number of outgoing peers
    pub target_outgoing: usize,
}

impl Default for DiscoveryConfig {
    fn default() -> Self {
        Self {
            bootstrap_peers: vec![],
            max_peers: 500,
            bootstrap_interval: Duration::from_secs(300), // 5 minutes
            pex_interval: Duration::from_secs(60),         // 1 minute
            peer_timeout: Duration::from_secs(3600),       // 1 hour
            target_outgoing: 8,
        }
    }
}

/// Peer status
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum PeerStatus {
    /// Just discovered, not yet connected
    Discovered,
    /// Connection in progress
    Connecting,
    /// Actively connected
    Connected,
    /// Recently disconnected, may reconnect
    Disconnected,
    /// Peer is banned
    Banned,
}

/// Full peer information tracked by discovery
#[derive(Clone, Debug)]
pub struct TrackedPeer {
    pub record: PeerRecord,
    pub status: PeerStatus,
    pub first_seen: Instant,
    pub last_seen: Instant,
    pub last_attempt: Option<Instant>,
    pub connection_attempts: u32,
    pub success_rate: f64,
}

/// Discovery manager
pub struct DiscoveryManager {
    config: DiscoveryConfig,
    /// Known peers: peer_id -> TrackedPeer
    peers: HashMap<[u8; 32], TrackedPeer>,
    /// Banned peers
    banned: HashSet<[u8; 32]>,
    /// Events channel
    event_tx: tokio::sync::broadcast::Sender<DiscoveryEvent>,
}

/// Discovery events
#[derive(Clone, Debug)]
pub enum DiscoveryEvent {
    NewPeerDiscovered([u8; 32], SocketAddr),
    PeerConnected([u8; 32]),
    PeerDisconnected([u8; 32]),
    PeerBanned([u8; 32], String),
    NeedMorePeers(usize),
}

impl DiscoveryManager {
    pub fn new(config: DiscoveryConfig) -> Self {
        let (event_tx, _) = tokio::sync::broadcast::channel(256);
        Self {
            config,
            peers: HashMap::new(),
            banned: HashSet::new(),
            event_tx,
        }
    }

    /// Add a newly discovered peer
    pub fn add_peer(&mut self, record: PeerRecord) {
        let peer_id = record.peer_id;
        if self.banned.contains(&peer_id) {
            return;
        }

        let now = Instant::now();
        let tracked = TrackedPeer {
            record: record.clone(),
            status: PeerStatus::Discovered,
            first_seen: now,
            last_seen: now,
            last_attempt: None,
            connection_attempts: 0,
            success_rate: 1.0,
        };

        let is_new = !self.peers.contains_key(&peer_id);
        self.peers.insert(peer_id, tracked);

        if is_new {
            log::debug!("Discovered new peer: {:?}", hex::encode(&peer_id[..8]));
            let addr = record.addr.parse().unwrap_or_default();
            let _ = self.event_tx.send(DiscoveryEvent::NewPeerDiscovered(peer_id, addr));
        }
    }

    /// Add multiple peers at once (from peer exchange)
    pub fn add_peers(&mut self, records: Vec<PeerRecord>) {
        for record in records {
            self.add_peer(record);
        }
    }

    /// Mark a peer as connected
    pub fn mark_connected(&mut self, peer_id: &[u8; 32]) {
        if let Some(peer) = self.peers.get_mut(peer_id) {
            peer.status = PeerStatus::Connected;
            peer.last_seen = Instant::now();
            peer.connection_attempts = 0;
            peer.success_rate = 1.0;
        }
        let _ = self.event_tx.send(DiscoveryEvent::PeerConnected(*peer_id));
    }

    /// Mark a peer as disconnected
    pub fn mark_disconnected(&mut self, peer_id: &[u8; 32]) {
        if let Some(peer) = self.peers.get_mut(peer_id) {
            peer.status = PeerStatus::Disconnected;
            peer.last_seen = Instant::now();
        }
        let _ = self.event_tx.send(DiscoveryEvent::PeerDisconnected(*peer_id));
    }

    /// Mark a peer as banned
    pub fn ban_peer(&mut self, peer_id: &[u8; 32], reason: String) {
        self.banned.insert(*peer_id);
        self.peers.remove(peer_id);
        let _ = self.event_tx.send(DiscoveryEvent::PeerBanned(*peer_id, reason));
    }

    /// Get peers that need connection attempts
    pub fn peers_to_connect(&self, count: usize) -> Vec<(SocketAddr, [u8; 32])> {
        let mut candidates: Vec<_> = self.peers
            .iter()
            .filter(|(_, p)| {
                matches!(p.status, PeerStatus::Discovered | PeerStatus::Disconnected)
                    && !self.banned.contains(p.record.peer_id)
            })
            .collect();

        candidates.shuffle(&mut rand::thread_rng());
        candidates.truncate(count);

        candidates
            .iter()
            .filter_map(|(id, p)| {
                p.record.addr.parse::<SocketAddr>().ok().map(|a| (a, **id))
            })
            .collect()
    }

    /// Get connected peers
    pub fn connected_peers(&self) -> Vec<&PeerRecord> {
        self.peers
            .iter()
            .filter(|(_, p)| p.status == PeerStatus::Connected)
            .map(|(_, p)| &p.record)
            .collect()
    }

    /// Get a random subset of connected peers for peer exchange
    pub fn peer_exchange_subset(&self, count: usize) -> Vec<PeerRecord> {
        let connected: Vec<_> = self.peers
            .iter()
            .filter(|(_, p)| p.status == PeerStatus::Connected)
            .map(|(_, p)| p.record.clone())
            .collect();

        let mut subset = connected;
        subset.shuffle(&mut rand::thread_rng());
        subset.truncate(count);
        subset
    }

    /// Remove stale peers
    pub fn prune_stale_peers(&mut self) {
        let now = Instant::now();
        let timeout = self.config.peer_timeout;
        let stale: Vec<[u8; 32]> = self.peers
            .iter()
            .filter(|(_, p)| {
                p.status != PeerStatus::Connected && now.duration_since(p.last_seen) > timeout
            })
            .map(|(id, _)| *id)
            .collect();

        for peer_id in stale {
            self.peers.remove(&peer_id);
            log::debug!("Removed stale peer: {:?}", hex::encode(&peer_id[..8]));
        }
    }

    /// Check if we need more peers
    pub fn needs_more_peers(&self) -> bool {
        let connected_count = self.connected_peers().len();
        connected_count < self.config.target_outgoing
    }

    /// Get number of known peers
    pub fn known_peers_count(&self) -> usize {
        self.peers.len()
    }

    /// Get number of connected peers
    pub fn connected_count(&self) -> usize {
        self.connected_peers().len()
    }

    /// Subscribe to discovery events
    pub fn subscribe(&self) -> tokio::sync::broadcast::Receiver<DiscoveryEvent> {
        self.event_tx.subscribe()
    }

    /// Bootstrap from initial seed peers
    pub async fn bootstrap(&mut self) {
        for addr in &self.config.bootstrap_peers {
            let record = PeerRecord {
                peer_id: [0u8; 32], // Will be updated on handshake
                addr: addr.to_string(),
                public_key: [0u8; 32],
                capabilities: Default::default(),
                score: 0.5,
            };
            self.add_peer(record);
        }
        log::info!("Bootstrapped with {} seed peers", self.config.bootstrap_peers.len());
    }
}

impl Drop for DiscoveryManager {
    fn drop(&mut self) {
        log::debug!("DiscoveryManager dropped");
    }
}


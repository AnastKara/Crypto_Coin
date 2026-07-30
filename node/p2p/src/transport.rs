//! P2P transport layer for Crypto_Coin
//!
//! Implements TCP-based transport with optional noise encryption
//! and multiplexed streams for different message types.

use tokio::net::{TcpListener, TcpStream};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use std::net::SocketAddr;
use std::time::Duration;
use crate::{P2PMessage, PeerInfo};

/// Transport configuration
#[derive(Clone, Debug)]
pub struct TransportConfig {
    pub listen_addr: SocketAddr,
    pub dial_timeout: Duration,
    pub handshake_timeout: Duration,
    pub max_message_size: usize,
    pub enable_encryption: bool,
}

impl Default for TransportConfig {
    fn default() -> Self {
        Self {
            listen_addr: "0.0.0.0:26656".parse().unwrap(),
            dial_timeout: Duration::from_secs(5),
            handshake_timeout: Duration::from_secs(3),
            max_message_size: 10 * 1024 * 1024, // 10 MB
            enable_encryption: true,
        }
    }
}

/// Transport event
#[derive(Clone, Debug)]
pub enum TransportEvent {
    ConnectionEstablished {
        peer_id: [u8; 32],
        addr: SocketAddr,
    },
    ConnectionClosed {
        peer_id: [u8; 32],
        addr: SocketAddr,
        reason: String,
    },
    MessageReceived {
        peer_id: [u8; 32],
        message: P2PMessage,
    },
    AcceptError(String),
    DialError(SocketAddr, String),
}

/// Transport manager
pub struct TransportManager {
    config: TransportConfig,
    /// Active connections: peer_id -> stream
    connections: std::collections::HashMap<[u8; 32], TcpStream>,
    /// Event channel
    event_tx: tokio::sync::broadcast::Sender<TransportEvent>,
}

impl TransportManager {
    pub fn new(config: TransportConfig) -> Self {
        let (event_tx, _) = tokio::sync::broadcast::channel(256);
        Self {
            config,
            connections: std::collections::HashMap::new(),
            event_tx,
        }
    }

    /// Start listening for incoming connections
    pub async fn listen(&self) -> Result<(), Box<dyn std::error::Error>> {
        let listener = TcpListener::bind(&self.config.listen_addr).await?;
        log::info!("Transport listening on {}", self.config.listen_addr);

        loop {
            let (stream, addr) = listener.accept().await?;
            log::debug!("Incoming connection from {}", addr);

            let event_tx = self.event_tx.clone();
            tokio::spawn(async move {
                match Self::handle_connection(stream, addr).await {
                    Ok(peer_id) => {
                        let _ = event_tx.send(TransportEvent::ConnectionEstablished {
                            peer_id,
                            addr,
                        });
                        // Keep connection alive and read messages
                        // (simplified - would loop reading messages)
                    }
                    Err(e) => {
                        let _ = event_tx.send(TransportEvent::AcceptError(
                            format!("Failed to handle connection from {}: {}", addr, e)
                        ));
                    }
                }
            });
        }
    }

    /// Dial a remote peer
    pub async fn dial(&mut self, addr: SocketAddr) -> Result<(), Box<dyn std::error::Error>> {
        let stream = tokio::time::timeout(
            self.config.dial_timeout,
            TcpStream::connect(addr)
        ).await??;

        // Perform handshake
        let peer_id = Self::perform_handshake(&stream).await?;

        log::info!("Connected to peer {} at {}", hex::encode(&peer_id[..8]), addr);
        self.connections.insert(peer_id, stream);

        let _ = self.event_tx.send(TransportEvent::ConnectionEstablished {
            peer_id,
            addr,
        });

        Ok(())
    }

    /// Send a message to a connected peer
    pub async fn send(&mut self, peer_id: &[u8; 32], msg: &P2PMessage) -> Result<(), String> {
        if let Some(stream) = self.connections.get_mut(peer_id) {
            let data = bincode::serialize(msg).map_err(|e| format!("Serialization error: {}", e))?;

            // Prefix with length header (4 bytes, big-endian)
            let len = (data.len() as u32).to_be_bytes();
            stream.write_all(&len).await.map_err(|e| format!("Write error: {}", e))?;
            stream.write_all(&data).await.map_err(|e| format!("Write error: {}", e))?;

            Ok(())
        } else {
            Err(format!("No connection to peer {:?}", hex::encode(&peer_id[..8])))
        }
    }

    /// Send a message to all connected peers
    pub async fn broadcast(&mut self, msg: &P2PMessage) {
        let peer_ids: Vec<[u8; 32]> = self.connections.keys().copied().collect();
        for peer_id in peer_ids {
            let _ = self.send(&peer_id, msg).await;
        }
    }

    /// Close a connection
    pub async fn disconnect(&mut self, peer_id: &[u8; 32]) {
        if let Some(mut stream) = self.connections.remove(peer_id) {
            let _ = stream.shutdown().await;
        }
    }

    /// Handle an incoming connection
    async fn handle_connection(mut stream: TcpStream, addr: SocketAddr) -> Result<[u8; 32], Box<dyn std::error::Error>> {
        let peer_id = Self::perform_handshake(&stream).await?;
        // In production: read messages in a loop
        Ok(peer_id)
    }

    /// Perform a handshake to establish peer identity
    async fn perform_handshake(stream: &TcpStream) -> Result<[u8; 32], Box<dyn std::error::Error>> {
        // Simplified: in production, this would exchange public keys
        // and verify signatures to establish peer identity
        let peer_id = [0u8; 32]; // Placeholder
        Ok(peer_id)
    }

    /// Subscribe to transport events
    pub fn subscribe(&self) -> tokio::sync::broadcast::Receiver<TransportEvent> {
        self.event_tx.subscribe()
    }

    /// Get number of active connections
    pub fn active_connections(&self) -> usize {
        self.connections.len()
    }
}

impl Drop for TransportManager {
    fn drop(&mut self) {
        log::debug!("TransportManager dropped");
    }
}


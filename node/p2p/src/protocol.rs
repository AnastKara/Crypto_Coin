//! P2P protocol messages and encoding
//!
//! Defines the wire protocol for peer-to-peer communication,
//! including message encoding, framing, and protocol versioning.

use serde::{Deserialize, Serialize};
use std::fmt;

/// Protocol version
pub const PROTOCOL_VERSION: u32 = 1;
/// Magic bytes for protocol identification
pub const MAGIC_BYTES: &[u8; 4] = b"CCP1";

/// Peer capabilities
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Capabilities {
    pub version: u32,
    pub chain_id: String,
    pub listen_port: u16,
    pub agent_version: String,
    pub is_validator: bool,
    pub latest_height: u64,
    pub latest_hash: [u8; 32],
}

impl Default for Capabilities {
    fn default() -> Self {
        Self {
            version: PROTOCOL_VERSION,
            chain_id: "crypto-coin-mainnet-1".to_string(),
            listen_port: 26656,
            agent_version: format!("crypto-coin-node/{}", env!("CARGO_PKG_VERSION")),
            is_validator: false,
            latest_height: 0,
            latest_hash: [0u8; 32],
        }
    }
}

/// Protocol message types
#[derive(Clone, Debug, Serialize, Deserialize)]
#[repr(u8)]
pub enum ProtocolMessage {
    /// Handshake request
    Handshake {
        capabilities: Capabilities,
        public_key: [u8; 32],
        signature: Vec<u8>,
    },
    /// Handshake response
    HandshakeAck {
        capabilities: Capabilities,
        public_key: [u8; 32],
        signature: Vec<u8>,
    },
    /// Gossip message
    Gossip {
        topic: String,
        data: Vec<u8>,
        signature: Vec<u8>,
    },
    /// Direct message (unicast)
    Direct {
        data: Vec<u8>,
    },
    /// Peer discovery request
    FindPeer {
        target: [u8; 32],
    },
    /// Peer list response
    PeerList {
        peers: Vec<PeerRecord>,
    },
    /// Ping (keep-alive)
    Ping {
        timestamp: i64,
    },
    /// Pong
    Pong {
        timestamp: i64,
    },
    /// Disconnect notification
    Disconnect {
        reason: String,
    },
}

/// Peer record for discovery
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PeerRecord {
    pub peer_id: [u8; 32],
    pub addr: String, // "ip:port" format
    pub public_key: [u8; 32],
    pub capabilities: Capabilities,
    pub score: f64,
}

/// Wire frame: length-prefixed messages
#[derive(Clone, Debug)]
pub struct WireFrame {
    pub magic: [u8; 4],
    pub length: u32,
    pub checksum: [u8; 32],
    pub payload: Vec<u8>,
}

impl WireFrame {
    /// Create a new wire frame from payload
    pub fn new(payload: Vec<u8>) -> Self {
        let length = payload.len() as u32;
        let checksum = compute_checksum(&payload);
        Self {
            magic: *MAGIC_BYTES,
            length,
            checksum,
            payload,
        }
    }

    /// Validate the frame
    pub fn validate(&self) -> Result<(), ProtocolError> {
        if &self.magic != MAGIC_BYTES {
            return Err(ProtocolError::InvalidMagic);
        }
        if self.payload.len() as u32 != self.length {
            return Err(ProtocolError::InvalidLength);
        }
        let expected_checksum = compute_checksum(&self.payload);
        if self.checksum != expected_checksum {
            return Err(ProtocolError::ChecksumMismatch);
        }
        Ok(())
    }

    /// Serialize to bytes
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut bytes = Vec::with_capacity(4 + 4 + 32 + self.payload.len());
        bytes.extend_from_slice(&self.magic);
        bytes.extend_from_slice(&self.length.to_be_bytes());
        bytes.extend_from_slice(&self.checksum);
        bytes.extend_from_slice(&self.payload);
        bytes
    }

    /// Deserialize from bytes
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, ProtocolError> {
        if bytes.len() < 40 {
            return Err(ProtocolError::TooShort);
        }

        let magic = [bytes[0], bytes[1], bytes[2], bytes[3]];
        let length = u32::from_be_bytes([bytes[4], bytes[5], bytes[6], bytes[7]]);
        let mut checksum = [0u8; 32];
        checksum.copy_from_slice(&bytes[8..40]);

        if bytes.len() < 40 + length as usize {
            return Err(ProtocolError::TooShort);
        }

        let payload = bytes[40..40 + length as usize].to_vec();

        Ok(Self {
            magic,
            length,
            checksum,
            payload,
        })
    }
}

/// Protocol error types
#[derive(Clone, Debug)]
pub enum ProtocolError {
    InvalidMagic,
    InvalidLength,
    ChecksumMismatch,
    TooShort,
    UnsupportedVersion(u32),
    InvalidHandshake(String),
    DeserializationError(String),
}

impl fmt::Display for ProtocolError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ProtocolError::InvalidMagic => write!(f, "Invalid magic bytes"),
            ProtocolError::InvalidLength => write!(f, "Invalid message length"),
            ProtocolError::ChecksumMismatch => write!(f, "Checksum mismatch"),
            ProtocolError::TooShort => write!(f, "Message too short"),
            ProtocolError::UnsupportedVersion(v) => write!(f, "Unsupported protocol version: {}", v),
            ProtocolError::InvalidHandshake(msg) => write!(f, "Invalid handshake: {}", msg),
            ProtocolError::DeserializationError(msg) => write!(f, "Deserialization error: {}", msg),
        }
    }
}

impl std::error::Error for ProtocolError {}

/// Compute SHA3-256 checksum (using SHA-256 as approximation)
fn compute_checksum(data: &[u8]) -> [u8; 32] {
    use sha2::{Sha256, Digest};
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&result);
    arr
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_wire_frame_roundtrip() {
        let payload = b"hello crypto-coin p2p".to_vec();
        let frame = WireFrame::new(payload.clone());
        assert!(frame.validate().is_ok());

        let bytes = frame.to_bytes();
        let decoded = WireFrame::from_bytes(&bytes).unwrap();
        assert_eq!(decoded.payload, payload);
    }

    #[test]
    fn test_peer_record() {
        let peer = PeerRecord {
            peer_id: [1u8; 32],
            addr: "127.0.0.1:26656".to_string(),
            public_key: [2u8; 32],
            capabilities: Capabilities::default(),
            score: 1.0,
        };

        let serialized = bincode::serialize(&peer).unwrap();
        let deserialized: PeerRecord = bincode::deserialize(&serialized).unwrap();
        assert_eq!(deserialized.peer_id, peer.peer_id);
        assert_eq!(deserialized.addr, peer.addr);
    }

    #[test]
    fn test_protocol_version() {
        assert_eq!(PROTOCOL_VERSION, 1);
        assert_eq!(MAGIC_BYTES, b"CCP1");
    }
}


//! Node error types

use std::fmt;

/// Node-level errors
#[derive(Debug, Clone)]
pub enum NodeError {
    /// Configuration error
    Config(String),
    /// Initialization error
    Init(String),
    /// Network error
    Network(String),
    /// Consensus error
    Consensus(String),
    /// Storage error
    Storage(String),
    /// Synchronization error
    Sync(String),
    /// Runtime error
    Runtime(String),
    /// IO error
    Io(String),
}

impl fmt::Display for NodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            NodeError::Config(msg) => write!(f, "Config error: {}", msg),
            NodeError::Init(msg) => write!(f, "Init error: {}", msg),
            NodeError::Network(msg) => write!(f, "Network error: {}", msg),
            NodeError::Consensus(msg) => write!(f, "Consensus error: {}", msg),
            NodeError::Storage(msg) => write!(f, "Storage error: {}", msg),
            NodeError::Sync(msg) => write!(f, "Sync error: {}", msg),
            NodeError::Runtime(msg) => write!(f, "Runtime error: {}", msg),
            NodeError::Io(msg) => write!(f, "IO error: {}", msg),
        }
    }
}

impl std::error::Error for NodeError {}

impl From<String> for NodeError {
    fn from(msg: String) -> Self {
        NodeError::Runtime(msg)
    }
}

impl From<std::io::Error> for NodeError {
    fn from(err: std::io::Error) -> Self {
        NodeError::Io(err.to_string())
    }
}


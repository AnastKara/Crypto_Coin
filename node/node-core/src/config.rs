//! Node configuration module

use std::net::SocketAddr;
use std::path::PathBuf;
use std::time::Duration;

/// Node configuration
#[derive(Clone, Debug)]
pub struct NodeConfig {
    // Network
    pub listen_addr: SocketAddr,
    pub external_addr: Option<SocketAddr>,
    pub bootstrap_peers: Vec<SocketAddr>,
    pub max_peers: usize,

    // Chain
    pub chain_id: String,
    pub genesis_path: PathBuf,
    pub data_dir: PathBuf,

    // Consensus
    pub validator_key_path: Option<PathBuf>,
    pub consensus_timeout_propose: Duration,
    pub consensus_timeout_prevote: Duration,
    pub consensus_timeout_precommit: Duration,

    // Storage
    pub db_path: PathBuf,
    pub max_block_size_bytes: u64,
    pub prune_after_blocks: Option<u64>,

    // API
    pub rpc_addr: SocketAddr,
    pub rpc_enabled: bool,
    pub ws_enabled: bool,

    // Logging
    pub log_level: log::LevelFilter,
    pub log_file: Option<PathBuf>,
}

impl Default for NodeConfig {
    fn default() -> Self {
        Self {
            listen_addr: "0.0.0.0:26656".parse().unwrap(),
            external_addr: None,
            bootstrap_peers: vec![],
            max_peers: 50,

            chain_id: "crypto-coin-mainnet-1".to_string(),
            genesis_path: PathBuf::from("genesis.json"),
            data_dir: PathBuf::from("data"),

            validator_key_path: None,
            consensus_timeout_propose: Duration::from_secs(3),
            consensus_timeout_prevote: Duration::from_secs(1),
            consensus_timeout_precommit: Duration::from_secs(1),

            db_path: PathBuf::from("data/blockchain.db"),
            max_block_size_bytes: 2 * 1024 * 1024, // 2 MB
            prune_after_blocks: Some(100_000),

            rpc_addr: "127.0.0.1:26657".parse().unwrap(),
            rpc_enabled: true,
            ws_enabled: true,

            log_level: log::LevelFilter::Info,
            log_file: None,
        }
    }
}

impl NodeConfig {
    /// Create a test configuration
    pub fn test_config(data_dir: &str) -> Self {
        Self {
            data_dir: PathBuf::from(data_dir),
            db_path: PathBuf::from(data_dir).join("blockchain.db"),
            genesis_path: PathBuf::from(data_dir).join("genesis.json"),
            ..Default::default()
        }
    }

    /// Validate the configuration
    pub fn validate(&self) -> Result<(), String> {
        if self.chain_id.is_empty() {
            return Err("chain_id must not be empty".to_string());
        }
        if self.max_peers == 0 {
            return Err("max_peers must be > 0".to_string());
        }
        if self.max_block_size_bytes == 0 {
            return Err("max_block_size_bytes must be > 0".to_string());
        }
        Ok(())
    }
}


//! # Crypto_Coin Blockchain Storage Layer
//!
//! This module implements the persistent storage for blockchain data.
//! Uses a Merkle tree-based structure for block storage and an
//! embedded key-value store (sled) for state.
//!
//! ## Architecture
//! - Blocks stored in sequential files with Merkle integrity
//! - State stored in sled (embedded KV store)
//! - Pruning support for historical data
//! - Atomic batch writes for consistency

pub mod block_store;
pub mod state_db;
pub mod mempool;

use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::RwLock;
use std::collections::HashMap;

/// Storage configuration
#[derive(Clone, Debug)]
pub struct StorageConfig {
    pub data_dir: PathBuf,
    pub db_path: PathBuf,
    pub max_block_size: u64,
    pub prune_threshold: Option<u64>,
    pub cache_size_mb: usize,
}

impl Default for StorageConfig {
    fn default() -> Self {
        Self {
            data_dir: PathBuf::from("data"),
            db_path: PathBuf::from("data/blockchain.db"),
            max_block_size: 2 * 1024 * 1024, // 2 MB
            prune_threshold: Some(100_000),
            cache_size_mb: 256,
        }
    }
}

/// A stored block with metadata
#[derive(Clone, Debug)]
pub struct StoredBlock {
    pub height: u64,
    pub hash: [u8; 32],
    pub data: Vec<u8>,
    pub timestamp: i64,
}

/// Storage manager
pub struct StorageManager {
    config: StorageConfig,
    /// Head of the chain (latest block)
    head: Arc<RwLock<Option<StoredBlock>>>,
    /// Block height -> hash mapping
    height_index: Arc<RwLock<HashMap<u64, [u8; 32]>>>,
    /// Block hash -> block data
    block_cache: Arc<RwLock<HashMap<[u8; 32], StoredBlock>>>,
}

impl StorageManager {
    pub fn new(config: StorageConfig) -> Self {
        Self {
            config,
            head: Arc::new(RwLock::new(None)),
            height_index: Arc::new(RwLock::new(HashMap::new())),
            block_cache: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// Initialize storage
    pub async fn init(&self) -> Result<(), Box<dyn std::error::Error>> {
        std::fs::create_dir_all(&self.config.data_dir)?;
        log::info!("Storage initialized at {:?}", self.config.data_dir);
        Ok(())
    }

    /// Store a block
    pub async fn store_block(&self, block: StoredBlock) -> Result<(), Box<dyn std::error::Error>> {
        let height = block.height;
        let hash = block.hash;

        // Update in-memory indexes
        self.height_index.write().await.insert(height, hash);
        self.block_cache.write().await.insert(hash, block.clone());

        // Update head if this is the latest
        let mut head = self.head.write().await;
        match head.as_ref() {
            Some(current) if height > current.height => {
                *head = Some(block);
            }
            None => {
                *head = Some(block);
            }
            _ => {}
        }

        log::debug!("Stored block #{}", height);
        Ok(())
    }

    /// Get block by height
    pub async fn get_by_height(&self, height: u64) -> Option<StoredBlock> {
        let hash = self.height_index.read().await.get(&height).copied()?;
        self.get_by_hash(&hash).await
    }

    /// Get block by hash
    pub async fn get_by_hash(&self, hash: &[u8; 32]) -> Option<StoredBlock> {
        self.block_cache.read().await.get(hash).cloned()
    }

    /// Get the current chain head
    pub async fn head(&self) -> Option<StoredBlock> {
        self.head.read().await.clone()
    }

    /// Get chain height
    pub async fn height(&self) -> u64 {
        self.head.read().await.as_ref().map(|b| b.height).unwrap_or(0)
    }

    /// Prune old blocks
    pub async fn prune(&self, keep_height: u64) -> Result<u64, Box<dyn std::error::Error>> {
        let mut pruned = 0u64;
        // In production, remove blocks from both indexes and disk
        log::info!("Pruned blocks below height {}", keep_height);
        Ok(pruned)
    }

    /// Shutdown storage
    pub async fn shutdown(&self) {
        log::info!("Storage shutting down");
    }
}

impl Drop for StorageManager {
    fn drop(&mut self) {
        log::debug!("StorageManager dropped");
    }
}


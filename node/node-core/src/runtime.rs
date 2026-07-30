//! Node runtime implementation

use crate::config::NodeConfig;
use crate::error::NodeError;
use crate::{NodeEvent, NodeInfo, NodeMetrics, NodeId, BlockHeight, SyncStatus};
use tokio::sync::{RwLock, mpsc, broadcast};
use tokio::task::JoinHandle;
use std::sync::Arc;
use std::time::{Instant, Duration};

/// The main node runtime
pub struct NodeRuntime {
    /// Node configuration
    config: NodeConfig,
    /// Node ID
    node_id: NodeId,
    /// Start time
    started_at: Instant,
    /// Current sync status
    sync_status: Arc<RwLock<SyncStatus>>,
    /// Latest block height
    latest_height: Arc<RwLock<BlockHeight>>,
    /// Event subscribers
    event_tx: broadcast::Sender<NodeEvent>,
    /// Shutdown signal
    shutdown_tx: mpsc::Sender<()>,
    shutdown_rx: Arc<RwLock<Option<mpsc::Receiver<()>>>>,
    /// Task handles
    handles: Arc<RwLock<Vec<JoinHandle<()>>>>,
    /// Metrics
    metrics: Arc<RwLock<NodeMetrics>>,
}

impl NodeRuntime {
    /// Create a new node runtime
    pub fn new(config: NodeConfig, node_id: NodeId) -> Self {
        let (shutdown_tx, shutdown_rx) = mpsc::channel(1);
        let (event_tx, _) = broadcast::channel(256);

        Self {
            config,
            node_id,
            started_at: Instant::now(),
            sync_status: Arc::new(RwLock::new(SyncStatus::Booting)),
            latest_height: Arc::new(RwLock::new(BlockHeight::GENESIS)),
            event_tx,
            shutdown_tx,
            shutdown_rx: Arc::new(RwLock::new(Some(shutdown_rx))),
            handles: Arc::new(RwLock::new(Vec::new())),
            metrics: Arc::new(RwLock::new(NodeMetrics::default())),
        }
    }

    /// Start the node runtime
    pub async fn start(&self) -> Result<(), NodeError> {
        log::info!("Starting Crypto_Coin node v{}", env!("CARGO_PKG_VERSION"));
        log::info!("Node ID: {:?}", self.node_id);
        log::info!("Listening on: {}", self.config.listen_addr);
        log::info!("Chain ID: {}", self.config.chain_id);

        // Update sync status
        *self.sync_status.write().await = SyncStatus::InSync;

        // Emit started event
        let _ = self.event_tx.send(NodeEvent::Started);

        Ok(())
    }

    /// Initiate graceful shutdown
    pub async fn shutdown(&self, reason: &str) {
        log::info!("Shutting down node: {}", reason);
        let _ = self.event_tx.send(NodeEvent::ShuttingDown(reason.to_string()));

        // Send shutdown signal to all tasks
        let _ = self.shutdown_tx.send(()).await;

        // Wait for all tasks to complete
        let mut handles = self.handles.write().await;
        for handle in handles.drain(..) {
            let _ = handle.await;
        }

        log::info!("Node shutdown complete");
    }

    /// Subscribe to node events
    pub fn subscribe(&self) -> broadcast::Receiver<NodeEvent> {
        self.event_tx.subscribe()
    }

    /// Get node information
    pub async fn info(&self) -> NodeInfo {
        NodeInfo {
            node_id: self.node_id.clone(),
            version: env!("CARGO_PKG_VERSION").to_string(),
            uptime_secs: self.started_at.elapsed().as_secs(),
            sync_status: *self.sync_status.read().await,
            latest_block_height: *self.latest_height.read().await,
            peer_count: 0, // TODO: get from P2P layer
            is_validator: self.config.validator_key_path.is_some(),
        }
    }

    /// Get current metrics
    pub async fn metrics(&self) -> NodeMetrics {
        self.metrics.read().await.clone()
    }

    /// Get configuration
    pub fn config(&self) -> &NodeConfig {
        &self.config
    }

    /// Get node ID
    pub fn node_id(&self) -> &NodeId {
        &self.node_id
    }

    /// Update latest block height
    pub async fn update_height(&self, height: BlockHeight) {
        let mut latest = self.latest_height.write().await;
        if height > *latest {
            *latest = height;
        }
    }

    /// Update sync status
    pub async fn update_sync_status(&self, status: SyncStatus) {
        *self.sync_status.write().await = status;
    }

    /// Spawn a background task managed by this runtime
    pub async fn spawn<F>(&self, name: &str, future: F)
    where
        F: std::future::Future<Output = ()> + Send + 'static,
    {
        let shutdown_rx = {
            let mut rx_opt = self.shutdown_rx.write().await;
            rx_opt.as_ref().map(|rx| rx.clone())
        };

        let handle = tokio::spawn(async move {
            tokio::select! {
                _ = future => {},
                _ = async {
                    if let Some(mut rx) = shutdown_rx {
                        rx.recv().await;
                    } else {
                        std::future::pending::<()>().await;
                    }
                } => {
                    log::debug!("Task '{}' received shutdown signal", name);
                }
            }
        });

        self.handles.write().await.push(handle);
    }
}

impl Drop for NodeRuntime {
    fn drop(&mut self) {
        // Note: In production, you'd want graceful shutdown via tokio
        log::debug!("NodeRuntime dropped");
    }
}


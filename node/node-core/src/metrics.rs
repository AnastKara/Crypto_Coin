//! Metrics collection for the node

use crate::NodeMetrics;
use std::sync::Arc;
use tokio::sync::RwLock;
use std::time::Instant;

/// Metrics collector that periodically samples node metrics
pub struct MetricsCollector {
    metrics: Arc<RwLock<NodeMetrics>>,
    started_at: Instant,
}

impl MetricsCollector {
    pub fn new(metrics: Arc<RwLock<NodeMetrics>>) -> Self {
        Self {
            metrics,
            started_at: Instant::now(),
        }
    }

    /// Record a block being received
    pub async fn record_block_received(&self) {
        let mut m = self.metrics.write().await;
        m.blocks_received += 1;
    }

    /// Record a block being proposed
    pub async fn record_block_proposed(&self) {
        let mut m = self.metrics.write().await;
        m.blocks_proposed += 1;
    }

    /// Record a transaction being processed
    pub async fn record_tx_processed(&self) {
        let mut m = self.metrics.write().await;
        m.transactions_processed += 1;
    }

    /// Record network bytes in
    pub async fn record_bytes_in(&self, bytes: u64) {
        let mut m = self.metrics.write().await;
        m.network_bytes_in += bytes;
    }

    /// Record network bytes out
    pub async fn record_bytes_out(&self, bytes: u64) {
        let mut m = self.metrics.write().await;
        m.network_bytes_out += bytes;
    }

    /// Update peer count
    pub async fn set_peer_count(&self, count: u32) {
        let mut m = self.metrics.write().await;
        m.peers_connected = count;
    }

    /// Update mempool size
    pub async fn set_mempool_size(&self, size: usize) {
        let mut m = self.metrics.write().await;
        m.mempool_size = size;
    }

    /// Get uptime in seconds
    pub fn uptime_secs(&self) -> u64 {
        self.started_at.elapsed().as_secs()
    }

    /// Get a snapshot of current metrics
    pub async fn snapshot(&self) -> NodeMetrics {
        self.metrics.read().await.clone()
    }
}


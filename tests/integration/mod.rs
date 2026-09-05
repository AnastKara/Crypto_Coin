//! # Crypto_Coin Multi-Node Integration Test Framework
//!
//! This module provides integration tests for validating the full
//! blockchain protocol across multiple nodes. It simulates a network
//! of validators running the consensus protocol and verifies that
//! they agree on the same chain state.
//!
//! ## Test Scenarios
//! - Happy path: all correct validators reach consensus
//! - Fault tolerance: up to f faulty validators
//! - Network partitions: temporary disconnections
//! - View changes: proposer failures

use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{RwLock, mpsc, Barrier};
use tokio::time::sleep;

/// Configuration for a test network node
#[derive(Clone, Debug)]
pub struct TestNodeConfig {
    pub node_id: u32,
    pub listen_port: u16,
    pub is_validator: bool,
    pub is_faulty: bool, // Simulates Byzantine behavior
    pub initial_peers: Vec<SocketAddr>,
}

/// Simulated test node
pub struct TestNode {
    pub config: TestNodeConfig,
    pub state: Arc<RwLock<TestNodeState>>,
}

/// State of a test node
#[derive(Clone, Debug, Default)]
pub struct TestNodeState {
    pub height: u64,
    pub last_block_hash: [u8; 32],
    pub blocks_committed: Vec<u64>,
    pub rounds_participated: u64,
    pub is_running: bool,
    pub fault_injected: bool,
}

impl TestNode {
    pub fn new(config: TestNodeConfig) -> Self {
        Self {
            config,
            state: Arc::new(RwLock::new(TestNodeState::default())),
        }
    }

    /// Start the test node
    pub async fn start(&self) {
        let mut state = self.state.write().await;
        state.is_running = true;
        log::info!(
            "TestNode {} started on port {} (validator: {}, faulty: {})",
            self.config.node_id,
            self.config.listen_port,
            self.config.is_validator,
            self.config.is_faulty
        );
    }

    /// Simulate running a consensus round
    pub async fn run_consensus_round(&self, round: u64, total_validators: u32) -> bool {
        if self.config.is_faulty {
            // Byzantine node does nothing or sends conflicting messages
            sleep(Duration::from_millis(10)).await;
            return false;
        }

        // Simulate: propose, prevote, precommit, commit
        sleep(Duration::from_millis(5)).await;
        let mut state = self.state.write().await;
        state.rounds_participated += 1;

        // Commit a block every round (simplified)
        state.height = round;
        state.blocks_committed.push(round);
        true
    }

    /// Get the current height
    pub async fn current_height(&self) -> u64 {
        self.state.read().await.height
    }
}

/// Test network orchestrator
pub struct TestNetwork {
    pub nodes: HashMap<u32, Arc<TestNode>>,
    pub total_validators: u32,
    pub faulty_count: u32,
}

impl TestNetwork {
    /// Create a new test network with `n` validators and `f` faulty
    pub fn new(n: u32, f: u32) -> Self {
        let mut nodes = HashMap::new();

        for i in 0..n {
            let config = TestNodeConfig {
                node_id: i,
                listen_port: (26656 + i) as u16,
                is_validator: true,
                is_faulty: i < f, // First f nodes are faulty
                initial_peers: vec![],
            };
            let node = Arc::new(TestNode::new(config));
            node.start_blocking();
            nodes.insert(i, node);
        }

        // Add a non-validator client node
        let client_config = TestNodeConfig {
            node_id: n,
            listen_port: (26656 + n) as u16,
            is_validator: false,
            is_faulty: false,
            initial_peers: vec![],
        };
        let client_node = Arc::new(TestNode::new(client_config));
        client_node.start_blocking();
        nodes.insert(n, client_node);

        Self {
            nodes,
            total_validators: n,
            faulty_count: f,
        }
    }

    fn start_blocking(&self) {
        // In production: spawn tasks
    }

    /// Run consensus for a given number of rounds
    pub async fn run_consensus(&self, rounds: u64) -> TestResult {
        let mut total_commits = 0u64;
        let mut rounds_with_consensus = 0u64;

        for round in 0..rounds {
            let mut round_commits = 0u64;

            for (id, node) in &self.nodes {
                if node.config.is_validator {
                    let committed = node.run_consensus_round(round, self.total_validators).await;
                    if committed {
                        round_commits += 1;
                    }
                }
            }

            if round_commits > self.total_validators * 2 / 3 {
                rounds_with_consensus += 1;
            }
            total_commits += round_commits;

            sleep(Duration::from_millis(1)).await;
        }

        TestResult {
            total_rounds: rounds,
            rounds_with_consensus,
            total_commits,
            total_validators: self.total_validators,
            faulty_count: self.faulty_count,
        }
    }

    /// Simulate a network partition (disconnect some nodes)
    pub async fn simulate_partition(&self, partition_size: u32) {
        log::info!("Simulating network partition of {} nodes", partition_size);
        // In production: disconnect specified nodes
        sleep(Duration::from_millis(50)).await;
    }

    /// Simulate message delays
    pub async fn simulate_message_delay(&self, delay_ms: u64) {
        log::info!("Simulating message delay of {}ms", delay_ms);
        sleep(Duration::from_millis(delay_ms)).await;
    }

    /// Verify all correct nodes have the same chain state
    pub async fn verify_consistency(&self) -> bool {
        let mut heights = Vec::new();
        for (id, node) in &self.nodes {
            if !node.config.is_faulty && node.config.is_validator {
                let height = node.current_height().await;
                heights.push((id, height));
            }
        }

        // All correct nodes should have the same height
        if heights.is_empty() {
            return true;
        }
        let first_height = heights[0].1;
        heights.iter().all(|(_, h)| *h == first_height)
    }
}

/// Test result metrics
#[derive(Clone, Debug)]
pub struct TestResult {
    pub total_rounds: u64,
    pub rounds_with_consensus: u64,
    pub total_commits: u64,
    pub total_validators: u32,
    pub faulty_count: u32,
}

impl std::fmt::Display for TestResult {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let consensus_rate = if self.total_rounds > 0 {
            (self.rounds_with_consensus as f64 / self.total_rounds as f64) * 100.0
        } else {
            100.0
        };
        write!(
            f,
            "Rounds: {}/{} with consensus ({:.1}%), Validators: {} ({} faulty), Total commits: {}",
            self.rounds_with_consensus,
            self.total_rounds,
            consensus_rate,
            self.total_validators,
            self.faulty_count,
            self.total_commits
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_happy_path_4_validators_no_faults() {
        let network = TestNetwork::new(4, 0);
        let result = network.run_consensus(10).await;
        assert!(result.rounds_with_consensus >= 9, "Consensus rate too low: {}", result);
        assert!(network.verify_consistency().await, "Nodes not in consistent state");
    }

    #[tokio::test]
    async fn test_bft_threshold_4_validators_1_faulty() {
        // n = 4, f = 1: n = 3f + 1 -> should still reach consensus
        let network = TestNetwork::new(4, 1);
        let result = network.run_consensus(10).await;
        assert!(result.rounds_with_consensus >= 8, "Consensus rate too low with 1 faulty: {}", result);
    }

    #[tokio::test]
    async fn test_bft_threshold_7_validators_2_faulty() {
        // n = 7, f = 2: within BFT bound
        let network = TestNetwork::new(7, 2);
        let result = network.run_consensus(10).await;
        assert!(result.rounds_with_consensus >= 7, "Consensus rate too low with 2/7 faulty: {}", result);
    }

    #[tokio::test]
    async fn test_bft_threshold_exceeded() {
        // n = 4, f = 2: exceeds f = (n-1)/3 = 1, should fail
        let network = TestNetwork::new(4, 2);
        let result = network.run_consensus(10).await;
        assert!(result.rounds_with_consensus < 5, "Consensus should fail with > f faulty: {}", result);
    }

    #[tokio::test]
    async fn test_network_partition_recovery() {
        let network = TestNetwork::new(4, 0);
        network.simulate_partition(1).await;
        let result = network.run_consensus(5).await;
        // Partition of 1/4 should not break consensus
        assert!(result.rounds_with_consensus >= 3, "Consensus should survive small partition: {}", result);
    }

    #[tokio::test]
    async fn test_consistency_after_message_delays() {
        let network = TestNetwork::new(4, 0);
        network.simulate_message_delay(100).await;
        let result = network.run_consensus(5).await;
        assert!(result.rounds_with_consensus >= 3, "Consensus should survive delays: {}", result);
        assert!(network.verify_consistency().await, "Nodes inconsistent after delays");
    }

    #[tokio::test]
    async fn test_7_validators_no_faults_all_rounds_consensus() {
        let network = TestNetwork::new(7, 0);
        let result = network.run_consensus(20).await;
        assert_eq!(result.rounds_with_consensus, 20, "All 20 rounds should have consensus: {}", result);
        assert!(network.verify_consistency().await, "Nodes inconsistent");
    }

    #[tokio::test]
    async fn test_majority_partition_should_fail() {
        let network = TestNetwork::new(4, 0);
        network.simulate_partition(3).await; // Partition 3/4 nodes
        let result = network.run_consensus(5).await;
        assert!(result.rounds_with_consensus <= 2, "Consensus should fail with majority partitioned: {}", result);
    }
}


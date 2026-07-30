//! # Crypto_Coin API Layer
//!
//! This module implements the HTTP/JSON-RPC and WebSocket API for
//! interacting with the Crypto_Coin blockchain node.
//!
//! ## Endpoints
//! - `/status` - Node status
//! - `/block`  - Block queries
//! - `/tx`     - Transaction submission and queries
//! - `/consensus` - Consensus info
//! - `/validators` - Validator set
//! - Websocket for event streaming

pub mod rpc;
pub mod ws;
pub mod rest;

use std::net::SocketAddr;
use std::sync::Arc;
use tokio::sync::RwLock;

/// API configuration
#[derive(Clone, Debug)]
pub struct ApiConfig {
    pub rpc_addr: SocketAddr,
    pub rpc_enabled: bool,
    pub ws_addr: SocketAddr,
    pub ws_enabled: bool,
    pub cors_allowed_origins: Vec<String>,
    pub max_request_size: usize,
}

impl Default for ApiConfig {
    fn default() -> Self {
        Self {
            rpc_addr: "127.0.0.1:26657".parse().unwrap(),
            rpc_enabled: true,
            ws_addr: "127.0.0.1:26658".parse().unwrap(),
            ws_enabled: true,
            cors_allowed_origins: vec!["*".to_string()],
            max_request_size: 10 * 1024 * 1024, // 10 MB
        }
    }
}

/// JSON-RPC request
#[derive(serde::Deserialize, serde::Serialize, Clone, Debug)]
pub struct JsonRpcRequest {
    pub jsonrpc: String,
    pub id: serde_json::Value,
    pub method: String,
    pub params: Vec<serde_json::Value>,
}

/// JSON-RPC response
#[derive(serde::Serialize, Clone, Debug)]
pub struct JsonRpcResponse {
    pub jsonrpc: String,
    pub id: serde_json::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<JsonRpcError>,
}

/// JSON-RPC error
#[derive(serde::Serialize, Clone, Debug)]
pub struct JsonRpcError {
    pub code: i32,
    pub message: String,
    pub data: Option<serde_json::Value>,
}

impl JsonRpcResponse {
    pub fn success(id: serde_json::Value, result: serde_json::Value) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id,
            result: Some(result),
            error: None,
        }
    }

    pub fn error(id: serde_json::Value, code: i32, message: String) -> Self {
        Self {
            jsonrpc: "2.0".to_string(),
            id,
            result: None,
            error: Some(JsonRpcError { code, message, data: None }),
        }
    }
}

/// API manager
pub struct ApiManager {
    config: ApiConfig,
}

impl ApiManager {
    pub fn new(config: ApiConfig) -> Self {
        Self { config }
    }

    /// Start the API server
    pub async fn start(&self) -> Result<(), Box<dyn std::error::Error>> {
        if self.config.rpc_enabled {
            log::info!("RPC API starting on {}", self.config.rpc_addr);
            // In production: start HTTP/JSON-RPC server
        }

        if self.config.ws_enabled {
            log::info!("WebSocket API starting on {}", self.config.ws_addr);
            // In production: start WebSocket server
        }

        Ok(())
    }
}

impl Drop for ApiManager {
    fn drop(&mut self) {
        log::debug!("ApiManager dropped");
    }
}


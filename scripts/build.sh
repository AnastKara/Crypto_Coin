#!/bin/bash
# Crypto_Coin Build Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Crypto_Coin Build ==="

# Build Rust components
echo ""
echo "--- Building Rust workspace ---"
cd "$PROJECT_DIR"
cargo build --release

# Build Haskell components (if Stack is available)
echo ""
echo "--- Building Haskell formal protocol ---"
if command -v stack &> /dev/null; then
    cd "$PROJECT_DIR/formal-protocol"
    stack build
else
    echo "Stack not found. Skipping Haskell build."
    echo "Install Haskell via: curl -sSL https://get.haskellstack.org/ | sh"
fi

echo ""
echo "=== Build complete! ==="


//! # Crypto_Coin Merkle Tree Implementation
//!
//! This module provides a balanced binary Merkle tree implementation
//! for efficiently verifying blockchain data integrity.
//!
//! ## Features
//! - SHA3-256 based hashing
//! - Proof generation and verification
//! - Padding to power-of-two
//! - Empty tree handling
//! - Efficient proof verification (O(log n))

use sha3::{Digest, Sha3_256};
use std::fmt;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A 32-byte hash value
#[derive(Clone, PartialEq, Eq, Hash)]
pub struct Hash(pub [u8; 32]);

impl Hash {
    /// Create a new hash from byte slice (must be exactly 32 bytes)
    pub fn new(bytes: &[u8]) -> Self {
        let mut arr = [0u8; 32];
        let len = bytes.len().min(32);
        arr[..len].copy_from_slice(&bytes[..len]);
        Hash(arr)
    }

    /// Create a zero hash (all zeros)
    pub fn zero() -> Self {
        Hash([0u8; 32])
    }
}

impl fmt::Debug for Hash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "0x{}", hex::encode(self.0))
    }
}

impl fmt::Display for Hash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "0x{}", hex::encode(&self.0[..8]))
    }
}

// ---------------------------------------------------------------------------
// Merkle Tree
// ---------------------------------------------------------------------------

/// A balanced binary Merkle tree
#[derive(Clone, Debug, PartialEq)]
pub enum MerkleTree {
    /// Leaf node containing a single hash
    Leaf(Hash),
    /// Internal node with hash and children
    Node {
        hash: Hash,
        left: Box<MerkleTree>,
        right: Box<MerkleTree>,
    },
}

impl MerkleTree {
    /// Get the root hash of the tree
    pub fn root_hash(&self) -> &Hash {
        match self {
            MerkleTree::Leaf(h) => h,
            MerkleTree::Node { hash, .. } => hash,
        }
    }

    /// Calculate the depth of the tree
    pub fn depth(&self) -> usize {
        match self {
            MerkleTree::Leaf(_) => 1,
            MerkleTree::Node { left, .. } => 1 + left.depth(),
        }
    }
}

// ---------------------------------------------------------------------------
// Merkle Proof
// ---------------------------------------------------------------------------

/// A Merkle proof for a specific leaf
#[derive(Clone, Debug)]
pub struct MerkleProof {
    /// The index of the leaf
    pub index: usize,
    /// The leaf hash
    pub leaf: Hash,
    /// Sibling hashes along the path to the root
    pub siblings: Vec<Hash>,
}

impl MerkleProof {
    /// Verify this proof against a known root hash
    pub fn verify(&self, root: &Hash) -> bool {
        let computed = self.compute_root();
        &computed == root
    }

    /// Compute the root hash from the proof
    fn compute_root(&self) -> Hash {
        let mut current = self.leaf.clone();
        let mut idx = self.index;

        for sibling in &self.siblings {
            current = if idx % 2 == 0 {
                // Current is left child
                combine_hashes(&current, sibling)
            } else {
                // Current is right child
                combine_hashes(sibling, &current)
            };
            idx /= 2;
        }

        current
    }
}

// ---------------------------------------------------------------------------
// Core Operations
// ---------------------------------------------------------------------------

/// Compute the Merkle root from a list of hashes
pub fn compute_root(hashes: &[Hash]) -> Hash {
    if hashes.is_empty() {
        return Hash::zero();
    }

    let padded = pad_to_power_of_two(hashes);
    let tree = build_tree(&padded);
    tree.root_hash().clone()
}

/// Build a complete Merkle tree from padded hashes
pub fn build_tree(hashes: &[Hash]) -> MerkleTree {
    if hashes.len() == 1 {
        return MerkleTree::Leaf(hashes[0].clone());
    }

    let mid = hashes.len() / 2;
    let left = build_tree(&hashes[..mid]);
    let right = build_tree(&hashes[mid..]);
    let combined = combine_hashes(left.root_hash(), right.root_hash());

    MerkleTree::Node {
        hash: combined,
        left: Box::new(left),
        right: Box::new(right),
    }
}

/// Generate a Merkle proof for a leaf at the given index
pub fn generate_proof(hashes: &[Hash], index: usize) -> Option<MerkleProof> {
    if hashes.is_empty() || index >= hashes.len() {
        return None;
    }

    let padded = pad_to_power_of_two(hashes);
    let leaf = hashes[index].clone();
    let siblings = collect_siblings(&padded, index);

    Some(MerkleProof {
        index,
        leaf,
        siblings,
    })
}

/// Collect sibling hashes along the path from leaf to root
fn collect_siblings(hashes: &[Hash], mut index: usize) -> Vec<Hash> {
    if hashes.len() <= 1 {
        return vec![];
    }

    let mut siblings = Vec::new();
    let mut current = hashes.to_vec();

    while current.len() > 1 {
        let mid = current.len() / 2;
        let sibling_idx = if index < mid {
            mid + (index % mid)
        } else {
            index % mid
        };

        siblings.push(current[sibling_idx].clone());

        // Move up one level
        let next = if index < mid {
            current[..mid].to_vec()
        } else {
            current[mid..].to_vec()
        };
        index = index % mid;
        current = next;
    }

    siblings
}

// ---------------------------------------------------------------------------
// Helper Functions
// ---------------------------------------------------------------------------

/// Compute SHA3-256 hash of data
pub fn sha3_256(data: &[u8]) -> Hash {
    let mut hasher = Sha3_256::new();
    hasher.update(data);
    let result = hasher.finalize();
    Hash::new(&result)
}

/// Combine two hashes: parent = hash(left || right)
pub fn combine_hashes(left: &Hash, right: &Hash) -> Hash {
    let mut combined = Vec::with_capacity(64);
    combined.extend_from_slice(&left.0);
    combined.extend_from_slice(&right.0);
    sha3_256(&combined)
}

/// Hash a leaf (double hash to prevent second-preimage attack)
pub fn hash_leaf(h: &Hash) -> Hash {
    combine_hashes(h, h)
}

/// Pad a list of hashes to the next power of two
pub fn pad_to_power_of_two(hashes: &[Hash]) -> Vec<Hash> {
    if hashes.is_empty() {
        return vec![Hash::zero()];
    }

    let len = hashes.len();
    let next_pow2 = next_power_of_two(len);

    if len == next_pow2 {
        hashes.to_vec()
    } else {
        let mut padded = hashes.to_vec();
        padded.resize(next_pow2, Hash::zero());
        padded
    }
}

/// Calculate the next power of two >= n
pub fn next_power_of_two(n: usize) -> usize {
    if n <= 1 {
        return 1;
    }
    let mut p = 1;
    while p < n {
        p <<= 1;
    }
    p
}

/// Calculate Merkle tree depth
pub fn tree_depth(num_leaves: usize) -> usize {
    if num_leaves <= 1 {
        return 1;
    }
    let padded = next_power_of_two(num_leaves);
    (padded as f64).log2().ceil() as usize + 1
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn test_hashes() -> Vec<Hash> {
        vec![
            sha3_256(b"tx1"),
            sha3_256(b"tx2"),
            sha3_256(b"tx3"),
            sha3_256(b"tx4"),
        ]
    }

    #[test]
    fn test_single_leaf() {
        let h = sha3_256(b"single");
        let root = compute_root(&[h.clone()]);
        assert_eq!(root, hash_leaf(&h));
    }

    #[test]
    fn test_two_leaves() {
        let hashes = test_hashes();
        let root = compute_root(&hashes[..2]);
        let expected = combine_hashes(&hash_leaf(&hashes[0]), &hash_leaf(&hashes[1]));
        assert_eq!(root, expected);
    }

    #[test]
    fn test_four_leaves() {
        let hashes = test_hashes();
        let root = compute_root(&hashes);

        let leaf1 = hash_leaf(&hashes[0]);
        let leaf2 = hash_leaf(&hashes[1]);
        let leaf3 = hash_leaf(&hashes[2]);
        let leaf4 = hash_leaf(&hashes[3]);

        let left = combine_hashes(&leaf1, &leaf2);
        let right = combine_hashes(&leaf3, &leaf4);
        let expected = combine_hashes(&left, &right);

        assert_eq!(root, expected);
    }

    #[test]
    fn test_proof_generation() {
        let hashes = test_hashes();
        let root = compute_root(&hashes);

        let proof = generate_proof(&hashes, 0).unwrap();
        assert!(proof.verify(&root));
        assert_eq!(proof.index, 0);
        assert_eq!(proof.leaf, hashes[0]);
    }

    #[test]
    fn test_proof_verification() {
        let hashes = test_hashes();
        let root = compute_root(&hashes);

        for i in 0..hashes.len() {
            let proof = generate_proof(&hashes, i).unwrap();
            assert!(proof.verify(&root), "Proof failed for index {}", i);
        }
    }

    #[test]
    fn test_invalid_proof() {
        let hashes = test_hashes();
        let root = compute_root(&hashes);

        let mut proof = generate_proof(&hashes, 0).unwrap();
        // Tamper with the leaf
        proof.leaf = sha3_256(b"tampered");
        assert!(!proof.verify(&root));
    }

    #[test]
    fn test_empty_tree() {
        let root = compute_root(&[]);
        assert_eq!(root, Hash::zero());
    }

    #[test]
    fn test_three_leaves_padding() {
        let hashes = test_hashes()[..3].to_vec();
        let padded = pad_to_power_of_two(&hashes);
        assert_eq!(padded.len(), 4);
        assert_eq!(padded[3], Hash::zero());
    }

    #[test]
    fn test_power_of_two() {
        assert_eq!(next_power_of_two(1), 1);
        assert_eq!(next_power_of_two(2), 2);
        assert_eq!(next_power_of_two(3), 4);
        assert_eq!(next_power_of_two(4), 4);
        assert_eq!(next_power_of_two(5), 8);
        assert_eq!(next_power_of_two(100), 128);
    }

    #[test]
    fn test_build_tree_depth() {
        let hashes = test_hashes();
        let padded = pad_to_power_of_two(&hashes);
        let tree = build_tree(&padded);
        assert_eq!(tree.depth(), 3); // 4 leaves -> depth 3
    }
}


//! # Crypto_Coin Signature Library
//!
//! This module provides Ed25519 digital signature functionality
//! for the Crypto_Coin blockchain protocol.
//!
//! ## Features
//! - Ed25519 signing and verification
//! - Key pair generation (random and seed-based)
//! - Public key derivation
//! - Deterministic key generation via HKDF
//! - Address derivation via Blake2b (20-byte)
//! - VRF (Verifiable Random Function) support
//! - Commitment scheme support

use ed25519_dalek::{
    Signer, Verifier, SigningKey, VerifyingKey,
    Signature as DalekSignature,
};
use rand::rngs::OsRng;
use sha2::{Sha256, Digest};
use blake2::{Blake2b512, Blake2s256, digest::consts::U20};
use hkdf::Hkdf;
use generic_array::GenericArray;
use std::fmt;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Ed25519 signature length in bytes
pub const SIGNATURE_LENGTH: usize = 64;
/// Ed25519 public key length in bytes
pub const PUBLIC_KEY_LENGTH: usize = 32;
/// Ed25519 private key (seed) length in bytes
pub const PRIVATE_KEY_LENGTH: usize = 32;
/// Address length in bytes (Blake2b-160)
pub const ADDRESS_LENGTH: usize = 20;
/// Hash length (SHA3-256)
pub const HASH_LENGTH: usize = 32;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A cryptographic hash (32 bytes)
#[derive(Clone, PartialEq, Eq, Hash)]
pub struct Hash(pub [u8; HASH_LENGTH]);

/// A digital signature (64 bytes)
#[derive(Clone, PartialEq, Eq)]
pub struct Signature(pub [u8; SIGNATURE_LENGTH]);

/// A public key (32 bytes)
#[derive(Clone, PartialEq, Eq)]
pub struct PublicKey(pub [u8; PUBLIC_KEY_LENGTH]);

/// A private/secret key (32 bytes seed)
#[derive(Clone)]
pub struct SecretKey(pub [u8; PRIVATE_KEY_LENGTH]);

/// A key pair
#[derive(Clone)]
pub struct KeyPair {
    pub secret: SecretKey,
    pub public: PublicKey,
}

/// A blockchain address (20 bytes)
#[derive(Clone, PartialEq, Eq, Hash)]
pub struct Address(pub [u8; ADDRESS_LENGTH]);

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

impl fmt::Debug for Hash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "0x{}", hex::encode(&self.0[..8]))
    }
}

impl fmt::Display for Hash {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "0x{}", hex::encode(&self.0[..8]))
    }
}

impl fmt::Debug for Address {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "addr_{}", hex::encode(&self.0[..8]))
    }
}

impl fmt::Display for Address {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "addr_{}", hex::encode(&self.0[..8]))
    }
}

// ---------------------------------------------------------------------------
// Hashing
// ---------------------------------------------------------------------------

/// Compute SHA3-256 hash (using SHA-256 as fallback)
pub fn sha3_256(data: &[u8]) -> Hash {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&result);
    Hash(arr)
}

/// Compute Blake2b hash with configurable output length
pub fn blake2b<const N: usize>(data: &[u8]) -> [u8; N] {
    use blake2::Blake2bVar;
    use blake2::digest::VariableOutput;
    let mut hasher = Blake2bVar::new(N).unwrap();
    hasher.update(data);
    let mut buf = [0u8; N];
    hasher.finalize_variable(&mut buf).unwrap();
    buf
}

/// Compute Blake2b-160 hash (20 bytes)
pub fn blake2b_160(data: &[u8]) -> Address {
    let hash = blake2b::<20>(data);
    Address(hash)
}

/// Compute Blake2s-256 hash (32 bytes)
pub fn blake2s_256(data: &[u8]) -> Hash {
    let mut hasher = Blake2s256::new();
    hasher.update(data);
    let result = hasher.finalize();
    Hash::new(&result)
}

impl Hash {
    pub fn new(bytes: &[u8]) -> Self {
        let mut arr = [0u8; 32];
        let len = bytes.len().min(32);
        arr[..len].copy_from_slice(&bytes[..len]);
        Hash(arr)
    }

    pub fn zero() -> Self {
        Hash([0u8; 32])
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}

// ---------------------------------------------------------------------------
// Key Generation
// ---------------------------------------------------------------------------

/// Generate a random key pair
pub fn generate_keypair() -> KeyPair {
    let mut csprng = OsRng;
    let signing_key = SigningKey::generate(&mut csprng);
    let verifying_key = signing_key.verifying_key();

    KeyPair {
        secret: SecretKey(signing_key.to_bytes()),
        public: PublicKey(verifying_key.to_bytes()),
    }
}

/// Generate a key pair from a seed
pub fn generate_keypair_from_seed(seed: &[u8]) -> KeyPair {
    let arr = expand_to_32(seed);
    let signing_key = SigningKey::from_bytes(&arr);
    let verifying_key = signing_key.verifying_key();

    KeyPair {
        secret: SecretKey(signing_key.to_bytes()),
        public: PublicKey(verifying_key.to_bytes()),
    }
}

/// Expand input to exactly 32 bytes using SHA-256
fn expand_to_32(data: &[u8]) -> GenericArray<u8, typenum::U32> {
    let hash = sha2::Sha256::digest(data);
    GenericArray::clone_from_slice(&hash)
}

/// Derive public key from secret key
pub fn derive_public_key(secret: &SecretKey) -> PublicKey {
    let signing_key = SigningKey::from_bytes(&secret.0);
    PublicKey(signing_key.verifying_key().to_bytes())
}

/// Deterministic key generation from master seed
pub fn keygen_deterministic(master_seed: &[u8], derivation_path: &[u8]) -> KeyPair {
    let hkdf = Hkdf::<Sha256>::new(Some(master_seed), derivation_path);
    let mut okm = [0u8; 32];
    hkdf.expand(b"crypto-coin-key", &mut okm).unwrap();
    generate_keypair_from_seed(&okm)
}

// ---------------------------------------------------------------------------
// Signing and Verification
// ---------------------------------------------------------------------------

/// Sign data with the given secret key
pub fn sign(secret: &SecretKey, data: &[u8]) -> Signature {
    let signing_key = SigningKey::from_bytes(&secret.0);
    let signature = signing_key.sign(data);
    Signature(signature.to_bytes())
}

/// Verify a signature against data and public key
pub fn verify(public: &PublicKey, signature: &Signature, data: &[u8]) -> bool {
    let verifying_key = match VerifyingKey::from_bytes(&public.0) {
        Ok(key) => key,
        Err(_) => return false,
    };

    let sig = match DalekSignature::from_bytes(&signature.0) {
        Ok(s) => s,
        Err(_) => return false,
    };

    verifying_key.verify(data, &sig).is_ok()
}

// ---------------------------------------------------------------------------
// Address Derivation
// ---------------------------------------------------------------------------

/// Derive an address from a public key
pub fn derive_address(public: &PublicKey) -> Address {
    blake2b_160(&public.0)
}

/// Verify that an address matches a public key
pub fn verify_address(address: &Address, public: &PublicKey) -> bool {
    derive_address(public) == *address
}

// ---------------------------------------------------------------------------
// VRF (Verifiable Random Function) - Simplified
// ---------------------------------------------------------------------------

/// Generate a VRF proof
pub fn vrf_prove(secret: &SecretKey, input: &[u8]) -> Vec<u8> {
    let hash = sha3_256(&[secret.0.as_slice(), input].concat());
    let proof = sign(secret, &hash.0);
    [hash.0.as_slice(), proof.0.as_slice()].concat()
}

/// Verify a VRF proof and extract the output
pub fn vrf_verify(public: &PublicKey, input: &[u8], proof: &[u8]) -> Option<Hash> {
    if proof.len() < 64 {
        return None;
    }

    let (hash_bytes, sig_bytes) = proof.split_at(32);
    let hash = Hash::new(hash_bytes);
    let sig = Signature::new(sig_bytes);

    if verify(public, &sig, &hash.0) {
        Some(hash)
    } else {
        None
    }
}

impl Signature {
    pub fn new(bytes: &[u8]) -> Self {
        let mut arr = [0u8; 64];
        let len = bytes.len().min(64);
        arr[..len].copy_from_slice(&bytes[..len]);
        Signature(arr)
    }

    pub fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}

// ---------------------------------------------------------------------------
// Commitment Scheme
// ---------------------------------------------------------------------------

/// Create a commitment to a value
pub fn commit(value: &[u8], blinding: &[u8]) -> Hash {
    sha3_256(&[value, blinding].concat())
}

/// Verify a commitment
pub fn open(commitment: &Hash, value: &[u8], blinding: &[u8]) -> bool {
    commit(value, blinding) == *commitment
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keypair_generation() {
        let kp = generate_keypair();
        assert_ne!(kp.secret.0, [0u8; 32]);
        assert_ne!(kp.public.0, [0u8; 32]);
    }

    #[test]
    fn test_sign_and_verify() {
        let kp = generate_keypair();
        let data = b"hello crypto-coin";
        let signature = sign(&kp.secret, data);
        assert!(verify(&kp.public, &signature, data));
    }

    #[test]
    fn test_invalid_signature() {
        let kp1 = generate_keypair();
        let kp2 = generate_keypair();
        let data = b"test data";
        let signature = sign(&kp1.secret, data);
        assert!(!verify(&kp2.public, &signature, data));
    }

    #[test]
    fn test_deterministic_keygen() {
        let kp1 = keygen_deterministic(b"master", b"path/0");
        let kp2 = keygen_deterministic(b"master", b"path/0");
        assert_eq!(kp1.secret.0, kp2.secret.0);
        assert_eq!(kp1.public.0, kp2.public.0);
    }

    #[test]
    fn test_address_derivation() {
        let kp = generate_keypair();
        let addr = derive_address(&kp.public);
        assert!(verify_address(&addr, &kp.public));
        assert!(!verify_address(&Address([0u8; 20]), &kp.public));
    }

    #[test]
    fn test_commitment() {
        let value = b"secret value";
        let blinding = b"random blinding";
        let commitment = commit(value, blinding);
        assert!(open(&commitment, value, blinding));
        assert!(!open(&commitment, b"wrong value", blinding));
    }

    #[test]
    fn test_vrf() {
        let kp = generate_keypair();
        let input = b"randomness input";
        let proof = vrf_prove(&kp.secret, input);

        let result = vrf_verify(&kp.public, input, &proof);
        assert!(result.is_some());
    }

    #[test]
    fn test_seed_based_keypair() {
        let seed = b"my test seed 1234567890abcdef";
        let kp1 = generate_keypair_from_seed(seed);
        let kp2 = generate_keypair_from_seed(seed);
        assert_eq!(kp1.secret.0, kp2.secret.0);
        assert_eq!(kp1.public.0, kp2.public.0);

        let data = b"test data";
        let sig = sign(&kp1.secret, data);
        assert!(verify(&kp1.public, &sig, data));
    }
}


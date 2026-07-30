{- |
Module      : CryptoCoin.Protocol.Merkle
Description : Merkle tree implementation for the Crypto_Coin blockchain
Copyright   : (c) Crypto_Coin Team, 2025
License     : MIT
Maintainer  : core@crypto-coin.io
Stability   : experimental

This module implements a balanced binary Merkle tree used for
efficiently verifying the integrity of block data (transactions, votes).
The implementation uses SHA3-256 as the underlying hash function.
-}

module CryptoCoin.Protocol.Merkle
    ( -- * Merkle Tree Operations
      computeRoot
    , computeRootFromLeaves
    , generateProof
    , verifyProof
    , combineRoots
    , merkleTreeDepth
    , padToPowerOfTwo

      -- * Merkle Tree Type
    , MerkleTree (..)
    , buildTree
    , rootHash
    ) where

import           CryptoCoin.Protocol.Types (Hash (..))
import qualified CryptoCoin.Protocol.Crypto as Crypto

import           Data.ByteString            (ByteString)
import qualified Data.ByteString            as BS
import           Data.List                  (unfoldr)
import           Data.Word                  (Word64)
import           Data.Bits                  (shiftL, shiftR, xor)

----------------------------------------------------------------------
-- Merkle Tree Data Structure
----------------------------------------------------------------------

-- | A balanced binary Merkle tree
data MerkleTree
    = MerkleLeaf !Hash              -- ^ Leaf node containing a hash
    | MerkleNode !Hash !MerkleTree !MerkleTree  -- ^ Internal node with hash and children
    deriving (Eq, Show)

-- | Compute the root hash of a Merkle tree
rootHash :: MerkleTree -> Hash
rootHash (MerkleLeaf h) = h
rootHash (MerkleNode h _ _) = h

----------------------------------------------------------------------
-- Merkle Root Computation
----------------------------------------------------------------------

-- | Compute the Merkle root from a list of hashes
computeRoot :: [Hash] -> Hash
computeRoot [] = emptyTreeHash
computeRoot [h] = hashLeaf h
computeRoot hashes =
    let padded = padToPowerOfTwo hashes
    in rootHash (buildTree padded)

-- | Compute Merkle root from leaves (alias)
computeRootFromLeaves :: [Hash] -> Hash
computeRootFromLeaves = computeRoot

-- | Build a complete Merkle tree from a list of padded hashes
buildTree :: [Hash] -> MerkleTree
buildTree [h] = MerkleLeaf h
buildTree hashes =
    let half = length hashes `div` 2
        left  = buildTree (take half hashes)
        right = buildTree (drop half hashes)
        combined = combineHashes (rootHash left) (rootHash right)
    in MerkleNode combined left right

----------------------------------------------------------------------
-- Merkle Proof Generation & Verification
----------------------------------------------------------------------

-- | Generate a Merkle proof for a leaf at the given index
generateProof :: Int -> [Hash] -> Maybe [Hash]
generateProof _ [] = Nothing
generateProof _ [h] = Just [h]  -- Single element, proof is just the element
generateProof idx hashes =
    let padded = padToPowerOfTwo hashes
        depth  = merkleTreeDepth (length padded)
    in go idx padded depth
  where
    go _ [h] _ = Just [h]
    go i hs d
        | i < 0 || i >= length hs = Nothing
        | otherwise =
            let half = length hs `div` 2
                (leftHashes, rightHashes) = splitAt half hs
                siblingIdx = if i < half then half + (i `mod` half) else i `mod` half
                sibling = hs !! siblingIdx
            in if i < half
               then do
                   rest <- go i leftHashes (d - 1)
                   Just (sibling : rest)
               else do
                   rest <- go (i - half) rightHashes (d - 1)
                   Just (sibling : rest)

-- | Verify a Merkle proof for a given leaf hash
verifyProof :: Hash -> [Hash] -> Hash -> Bool
verifyProof leafHash proof expectedRoot =
    let computedRoot = foldl combineSingles leafHash proof
    in computedRoot == expectedRoot
  where
    combineSingles :: Hash -> Hash -> Hash
    combineSingles h1 h2 = do
        let leftH  = min h1 h2
            rightH = max h1 h2
        in combineHashes leftH rightH

-- | Combine two Merkle root hashes into one
combineRoots :: MerkleRoot -> MerkleRoot -> MerkleRoot
combineRoots (MerkleRoot h1) (MerkleRoot h2) = MerkleRoot (combineHashes h1 h2)

----------------------------------------------------------------------
-- Internal Operations
----------------------------------------------------------------------

-- | Combine two hashes (parent = hash(left || right))
combineHashes :: Hash -> Hash -> Hash
combineHashes (Hash left) (Hash right) =
    Crypto.hash (left `BS.append` right)

-- | Hash a single leaf
hashLeaf :: Hash -> Hash
hashLeaf h = combineHashes h h  -- Double hash for leaf to prevent second-preimage attack

-- | Empty tree hash (32 zero bytes)
emptyTreeHash :: Hash
emptyTreeHash = Hash (BS.replicate 32 0)

-- | Pad a list of hashes to the next power of two
padToPowerOfTwo :: [Hash] -> [Hash]
padToPowerOfTwo [] = [emptyTreeHash]
padToPowerOfTwo hashes =
    let len = length hashes
        nextPow2 = nextPowerOfTwo len
    in if len == nextPow2
       then hashes
       else hashes ++ replicate (nextPow2 - len) emptyTreeHash

-- | Calculate the depth of a Merkle tree with n leaves
merkleTreeDepth :: Int -> Int
merkleTreeDepth n
    | n <= 1    = 1
    | otherwise = floor (logBase 2 (fromIntegral (nextPowerOfTwo n))) + 1

-- | Find the next power of two greater than or equal to n
nextPowerOfTwo :: Int -> Int
nextPowerOfTwo n
    | n <= 1    = 1
    | otherwise = 1 `shiftL` (finiteBitSize n - countLeadingZeros (n - 1))
  where
    -- Simulate finiteBitSize and countLeadingZeros for portability
    finiteBitSize _ = 64  -- Using 64-bit integer
    countLeadingZeros x = go 64 x
      where
        go 0 _ = 0
        go bits val
            | val >= (1 `shiftL` (bits - 1)) = 0
            | otherwise = 1 + go (bits - 1) (val `shiftL` 1)


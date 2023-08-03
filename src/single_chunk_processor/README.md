# Chunk Processor

The chunk procesor is used to process block headers from EVM in a continuous way. For clarity, we will define some notations. 

- `n` is the block number of first block header being processed.   

- `r` is the number of block headers being processed in a single chunk.

- `n-r+1` is the block number of last block header being processed.

- `H(k)` is the hash of block header `k`.

- `PH(k)` is the parent hash of block header `k`. Ie: `PH(k) = H(k-1)`


This means one run of chunk processor will process block headers from block number `n` to block number `n-r+1` (both bound included), for a total of `r` block headers.  
We will note `[n-r+1, n]`` the range of block headers being processed.


The processor is essentially doing two things:  

I. Proves the cryptographic link from block header `N` to block header `N - R + 1`.  
II. Stores the block headers hashes inside a cryptographic accumulator (a Merkle Mountain Range (MMR)).


The processor takes as (private) input the following data :
1) PH(n+1) : The parent hash of the first block header being processed.
2) The block headers for block numbers `[n-r+1, n]`
3) The size in bytes of each block header. 
3) The previous MMR root hash
4) The previous MMR length
5) The previous MMR peaks that lead to the previous MMR root hash. 

It then outputs the following data:
1) PH(n+1) : from the input
2) PH(n-r+1) : extracted from the block header n-r+1
3) The previous MMR root hash : from the input
4) The previous MMR length : from the input
5) The new MMR root hash
6) The new MMR length

Sample Output : 

```json
{
    "block_n_plus_one_parent_hash_low": 315370331409443736823221485988685195413,
    "block_n_plus_one_parent_hash_high": 126107605954105369951508068813108544057,
    "block_n_minus_r_plus_one_parent_hash_low": 136866067543847669498991722409075541041,
    "block_n_minus_r_plus_one_parent_hash_high": 177967517848902133258538140088066928522,
    "mmr_last_root_poseidon": 3479338169082095971046364168027768535347015637320633319590549596752193694292,
    "mmr_last_root_keccak_low": 65040557660138839334666358099506704086,
    "mmr_last_root_keccak_high": 284555609286660322864717653413946846488,
    "mmr_last_len": 39,
    "new_mmr_root_poseidon": 223713918790983505475296316320346982784536430942231172119011387937163131563,
    "new_mmr_root_keccak_low": 121691365733540700158450111681477937269,
    "new_mmr_root_keccak_high": 73517937895429982038849154586466839530,
    "new_mmr_len": 79
}
```


## I. Proving the cryptographic link from block header `N` to block header `N - R + 1`.

Assuming `PH(n+1)` provided as input (and returned as output) is correct, we can assert that H(n) = PH(n+1).

Following RLP conventions, one is able to extract the parent hash of a block header deterministically. 

Then it straightforward to continue this recursion, extracting `PH(n)` and assert that `H(n-1) == PH(n)`

This ensures the integrity of the data of the block headers [n-r+1, n-r] provided as input. 

We can therefore store all [H[n], ..., H[n-r+1]] into the accumulator. 

The PH(n-r+1) is extracted and returned as output to be able to use it as the "new" PH(n+1) for the next chunk. 

## 2. Storing the block header hashes into the MMR

Using the previous root of the MMR and the previous peaks provided as input, one can assert that the peaks provided indeed match the root of the tree. 

If that's the case, one can only use the previous MMR peaks to append values to it. 


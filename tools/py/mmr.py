"""
Merkle Mountain Range
"""

from typing import List, Tuple, Optional
import hashlib
from tools.py.poseidon.poseidon_hash import poseidon_hash_single, poseidon_hash
import matplotlib.pyplot as plt


def tree_pos_height(pos: int) -> int:
    """
    calculate pos height in tree
    Explains:
    https://github.com/mimblewimble/grin/blob/0ff6763ee64e5a14e70ddd4642b99789a1648a32/core/src/core/pmmr.rs#L606
    use binary expression to find tree height(all one position number)
    return pos height
    """
    # convert from 0-based to 1-based position, see document
    pos += 1

    def all_ones(num: int) -> bool:
        return (1 << num.bit_length()) - 1 == num

    def jump_left(pos: int) -> int:
        most_significant_bits = 1 << pos.bit_length() - 1
        return pos - (most_significant_bits - 1)

    # loop until we jump to all ones position, which is tree height
    while not all_ones(pos):
        pos = jump_left(pos)
    # count all 1 bits
    return pos.bit_length() - 1


# get left or right sibling offset by height
def sibling_offset(height) -> int:
    return (2 << height) - 1


def get_peaks(mmr_size) -> List[int]:
    """
    return peaks positions from left to right
    """
    def get_right_peak(height, pos, mmr_size):
        """
        find next right peak
        peak not exsits if height is -1
        """
        # jump to right sibling
        pos += sibling_offset(height)
        # jump to left child
        while pos > mmr_size - 1:
            height -= 1
            if height < 0:
                # no right peak exists
                return (height, None)
            pos -= 2 << height
        return (height, pos)

    poss = []
    height, pos = left_peak_height_pos(mmr_size)
    poss.append(pos)
    while height > 0:
        height, pos = get_right_peak(height, pos, mmr_size)
        if height >= 0:
            poss.append(pos)
    return poss


def left_peak_height_pos(mmr_size: int) -> Tuple[int, int]:
    """
    find left peak
    return (left peak height, pos)
    """
    def get_left_pos(height):
        """
        convert height to binary express, then minus 1 to get 0 based pos
        explain:
        https://github.com/mimblewimble/grin/blob/master/doc/mmr.md#structure
        https://github.com/mimblewimble/grin/blob/0ff6763ee64e5a14e70ddd4642b99789a1648a32/core/src/core/pmmr.rs#L606
        For example:
        height = 2
        # use one-based encoding, mean that left node is all one-bits
        # 0b1 is 0 pos, 0b11 is 2 pos 0b111 is 6 pos
        one_based_binary_encoding = 0b111
        pos = 0b111 - 1 = 6
        """
        return (1 << height + 1) - 2
    height = 0
    prev_pos = 0
    pos = get_left_pos(height)
    # increase height and get most left pos of tree
    # once pos is out of mmr_size we consider previous pos is left peak
    while pos < mmr_size:
        height += 1
        prev_pos = pos
        pos = get_left_pos(height)
    return (height - 1, prev_pos)


class MMR(object):
    """
    MMR
    """
    def __init__(self, hasher=hashlib.blake2b):
        self.last_pos = -1
        self.pos_hash = {}
        self._hasher = hasher

    def add(self, elem: bytes) -> int:
        """
        Insert a new leaf, v is a binary value
        """
        self.last_pos += 1
        # hasher = self._hasher()
        # hasher.update(elem)

        # store hash
        self.pos_hash[self.last_pos] = elem
        height = 0
        pos = self.last_pos
        # merge same sub trees
        # if next pos height is higher implies we are in right children
        # and sub trees can be merge
        while tree_pos_height(self.last_pos + 1) > height:
            # increase pos cursor
            self.last_pos += 1
            # calculate pos of left child and right child
            left_pos = self.last_pos - (2 << height)
            right_pos = left_pos + sibling_offset(height)
            # hasher = self._hasher()
            # # calculate parent hash
            # hasher.update(self.pos_hash[left_pos])
            # hasher.update(self.pos_hash[right_pos])
            hash_val = poseidon_hash(self.pos_hash[left_pos], self.pos_hash[right_pos])
            self.pos_hash[self.last_pos] = hash_val
            height += 1
        return pos

    # def get_root(self) -> Optional[bytes]:
    #     """
    #     MMR root
    #     """
    #     peaks = get_peaks(self.last_pos + 1)
    #     print("peaks pos", peaks)
    #     # bag all rhs peaks, which is exact root
    #     return self._bag_rhs_peaks(-1, peaks)

    def get_root(self) -> Optional[bytes]:
        """
        MMR root
        """
        peaks = get_peaks(self.last_pos + 1)
        peaks_values = [self.pos_hash[p] for p in peaks]
        bagged = self.bag_peaks(peaks_values)
        root = poseidon_hash(len(self.pos_hash), bagged)
        return root

    def bag_peaks(self, peaks: List[int]) -> int:
        bags = peaks[-1]
        for peak in reversed(peaks[:-1]): 
            bags = poseidon_hash(peak, bags) 

        return bags
    def _bag_rhs_peaks(self, peak_pos: int, peaks: List[int]
                       ) -> Optional[bytes]:
        rhs_peak_hashes = [self.pos_hash[p] for p in peaks
                           if p > peak_pos]
        print("peaks hashes", rhs_peak_hashes)
        while len(rhs_peak_hashes) > 1:
            peak_r = rhs_peak_hashes.pop()
            peak_l = rhs_peak_hashes.pop()
            # hasher = self._hasher()
            # hasher.update(peak_r)
            # hasher.update(peak_l)
            hash_val = poseidon_hash(peak_r, peak_l)
            # rhs_peak_hashes.append(hasher.digest())
            rhs_peak_hashes.append(hash_val)
        if len(rhs_peak_hashes) > 0:
            return rhs_peak_hashes[0]
        else:
            return None

    def _lhs_peaks(self, peak_pos: int, peaks: List[int]
                   ) -> List[bytes]:
        return [self.pos_hash[p] for p in peaks if p < peak_pos]


# class MerkleProof(object):
#     """
#     MerkleProof, used for verify a proof
#     """
#     def __init__(self, mmr_size: int,
#                  proof: List[bytes],
#                  hasher):
#         self.mmr_size = mmr_size
#         self.proof = proof
#         self._hasher = hasher

#     def verify(self, root: bytes, pos: int, elem: bytes) -> bool:
#         """
#         verify proof
#         root - MMR root that generate this proof
#         pos - elem insertion pos
#         elem - elem
#         """
#         peaks = get_peaks(self.mmr_size)
#         hasher = self._hasher()
#         hasher.update(elem)
#         elem_hash = hasher.digest()
#         height = 0
#         for proof in self.proof:
#             hasher = self._hasher()
#             # verify bagging peaks
#             if pos in peaks:
#                 if pos == peaks[-1]:
#                     hasher.update(elem_hash)
#                     hasher.update(proof)
#                 else:
#                     hasher.update(proof)
#                     hasher.update(elem_hash)
#                     pos = peaks[-1]
#                 elem_hash = hasher.digest()
#                 continue

#             # verify merkle path
#             pos_height = tree_pos_height(pos)
#             next_height = tree_pos_height(pos + 1)
#             if next_height > pos_height:
#                 # we are in right child
#                 hasher.update(proof)
#                 hasher.update(elem_hash)
#                 pos += 1
#             else:
#                 # we are in left child
#                 hasher.update(elem_hash)
#                 hasher.update(proof)
#                 pos += 2 << height
#             elem_hash = hasher.digest()
#             height += 1
#         return elem_hash == root

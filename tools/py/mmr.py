"""
Merkle Mountain Range
Adapted from https://github.com/jjyr/mmr.py (MIT License)
Replicates the MMR behavior of the chunk processor, ie : 
    - the leafs are directly inserted in the tree without any hashing (they're supposed to be already hashes of block headers)
    - merging is done by hashing the two hashes together, without prepending any indexes
    - the root is computed by bagging the peaks without prepending any indexes
"""

from typing import List, Tuple, Union
import sha3
from tools.py.poseidon.poseidon_hash import poseidon_hash, poseidon_hash_single, poseidon_hash_many
    

class PoseidonHasher:
    def __init__(self):
        self.list = []

    def update(self, item):
        if type(item) == int:
            self.list.append(item)
        elif type(item) == bytes:
            self.list.append(int.from_bytes(item, 'big'))
        else:
            raise Exception("unsupported type")
    def digest(self) -> int:
        try:
            if len(self.list) == 1:
                res= poseidon_hash_single(self.list[0])
            elif len(self.list) == 2:
                
                res= poseidon_hash(self.list[0], self.list[1])
            elif len(self.list) > 2:
                res= poseidon_hash_many(self.list)
            else:
                raise Exception("no item to digest")
        finally:
            self.list = []
        return res
        
class KeccakHasher:
    def __init__(self):
        self.keccak = sha3.keccak_256()
    def update(self, item):
        if type(item) == int:
            self.keccak.update(item.to_bytes(32, 'big'))
        elif type(item) == bytes:
            self.keccak.update(item)
        else:
            raise Exception("unsupported type")
    def digest(self) -> int:
        res = self.keccak.digest()
        self.keccak = sha3.keccak_256()
        return int.from_bytes(res, 'big')
    


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
    return peaks positions from left to right, 0-index based. 
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
    def __init__(self, hasher:Union[PoseidonHasher, KeccakHasher]=PoseidonHasher()):
        self.last_pos = -1
        self.pos_hash = {}
        self._hasher = hasher

    def add(self, elem: Union[bytes, int]) -> int:
        """
        Insert a new leaf, v is a binary value
        """
        self.last_pos += 1

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
            # calculate parent hash
            self._hasher.update(self.pos_hash[left_pos])
            self._hasher.update(self.pos_hash[right_pos])
            self.pos_hash[self.last_pos] = self._hasher.digest()
            height += 1
        return pos

    def get_root(self) -> int:
        """
        MMR root
        """
        peaks = get_peaks(len(self.pos_hash))
        peaks_values = [self.pos_hash[p] for p in peaks]
        bagged = self.bag_peaks(peaks_values)
        
        return bagged

    def bag_peaks(self, peaks: List[int]) -> int:
        bags = peaks[-1]
        for peak in reversed(peaks[:-1]): 
            self._hasher.update(peak)
            self._hasher.update(bags)

            bags = self._hasher.digest()

        return bags


if __name__ == '__main__':
    poseidon_mmr=MMR(PoseidonHasher())
    for i in range(3):
        _ = poseidon_mmr.add(i)
    
    print(poseidon_mmr.get_root())

    keccak_mmr=MMR(KeccakHasher())
    for i in range(3):
        _ = keccak_mmr.add(i)
    print(keccak_mmr.get_root())
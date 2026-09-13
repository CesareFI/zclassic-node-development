Description
------------

This directory contains data-driven tests for various aspects of Bitcoin.

OG Zclassic download fixture
---------------------------

`zclassic-download-130.dat` contains the original mainnet blocks 0 through 129,
including their eight-byte disk framing. It was copied from an existing full
node's first block file on 2026-09-13; no test mining was used. Tests verify the
genesis hash, continuous parent links, headers, and normal block processing.
The 207319-byte fixture's SHA256 is
`4ae8e7c4a2b2fb5b925ecc18752bf517dad39dd0a965a8c44d4fee29360ba2b6`.

License
--------

The data files in this directory are distributed under the MIT software
license, see the accompanying file COPYING or
http://www.opensource.org/licenses/mit-license.php.

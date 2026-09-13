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

`zclassic-header-extension-320.dat` extends that fixture with original mainnet
headers at heights 130 through 320. It contains 191 concatenated CBlockHeader
serializations (no block framing or transaction-count bytes), allowing two full
160-header responses to pass normal header validation. The 284017-byte file's
SHA256 is `fb65199635078e9bb4c8d8da301d3c632a20b63782f47c532f2e915777c12370`.
It was extracted from the existing frozen 4096-block benchmark fixture with
SHA256 `4a382be44d8add0f95c17e4bc6eb8a414cf3e37b38779a95c738f42fec9bbdd3`;
no production datadir access, network download, or test mining was used.

License
--------

The data files in this directory are distributed under the MIT software
license, see the accompanying file COPYING or
http://www.opensource.org/licenses/mit-license.php.

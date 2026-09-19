#!/usr/bin/env python3
"""Read-only RPC summary of JoinSplit work available within captured blocks.

Use a scratch node with the selected blocks already validated. Only aggregate
counts are emitted; no transaction data or authentication material is printed.
"""
import argparse
from collections import Counter
import importlib.util
import json
from pathlib import Path
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rpcport", type=int, required=True)
    parser.add_argument("--cookie", type=Path, required=True)
    parser.add_argument("--start-height", type=int, default=1)
    parser.add_argument("--end-height", type=int, default=5000)
    args = parser.parse_args()
    if (not 1 <= args.rpcport <= 65535 or args.start_height < 0 or
            not args.start_height <= args.end_height < args.start_height + 100000):
        parser.error("valid port and an ordered range of at most 100,000 blocks are required")
    spec = importlib.util.spec_from_file_location(
        "ibd_benchmark", Path(__file__).resolve().parent / "benchmark-ibd.py")
    benchmark = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(benchmark)
    per_block, per_transaction, shielded_transactions_per_block = Counter(), Counter(), Counter()
    transactions = proofs = proofs_in_parallel_blocks = proofs_in_parallel_transactions = 0
    proofs_across_transactions = 0
    start = time.monotonic()
    for height in range(args.start_height, args.end_height + 1):
        block = benchmark.rpc(args.rpcport, args.cookie, "getblock", [str(height), 2])
        if block["height"] != height:
            raise RuntimeError("RPC returned an unexpected block height")
        block_proofs = 0
        shielded_transactions = 0
        for transaction in block["tx"]:
            count = len(transaction.get("vjoinsplit", []))
            per_transaction[count] += 1
            block_proofs += count
            shielded_transactions += count > 0
            if count > 1:
                proofs_in_parallel_transactions += count
        transactions += len(block["tx"])
        proofs += block_proofs
        per_block[block_proofs] += 1
        shielded_transactions_per_block[shielded_transactions] += 1
        if shielded_transactions > 1:
            proofs_across_transactions += block_proofs
        if block_proofs > 1:
            proofs_in_parallel_blocks += block_proofs
    print(json.dumps({"start_height": args.start_height, "end_height": args.end_height,
                      "blocks": sum(per_block.values()), "transactions": transactions,
                      "joinsplits": proofs, "joinsplits_per_block": dict(sorted(per_block.items())),
                      "joinsplits_per_transaction": dict(sorted(per_transaction.items())),
                      "shielded_transactions_per_block": dict(sorted(shielded_transactions_per_block.items())),
                      "joinsplits_in_blocks_with_multiple_shielded_transactions": proofs_across_transactions,
                      "joinsplits_in_multi_proof_blocks": proofs_in_parallel_blocks,
                      "joinsplits_in_multi_proof_transactions": proofs_in_parallel_transactions,
                      "rpc_scan_seconds": time.monotonic() - start}, sort_keys=True))


if __name__ == "__main__":
    main()

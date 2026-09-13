#!/usr/bin/env python3
"""Check sync diagnostics using ordinary recorded RPC-shaped values."""
import contextlib
import importlib.util
import io
import json
import pathlib
import types
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "sync_status", ROOT / "contrib/diagnostics/sync-status.py")
STATUS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STATUS)


class SyncStatusTests(unittest.TestCase):
    def snapshot(self, peers):
        responses = [
            {"blocks": 0, "headers": 129, "initialblockdownload": True,
             "blockdownload": {"blocks_in_flight": 1,
                               "validated_blocks_in_flight": 0}},
            peers,
        ]
        replies = [types.SimpleNamespace(returncode=0, stdout=json.dumps(value), stderr="")
                   for value in responses]
        with patch.object(STATUS.subprocess, "run", side_effect=replies):
            return STATUS.snapshot(["fixture-cli"])

    def test_requests_without_known_heights_still_identify_downloader(self):
        state = self.snapshot([{"id": 7, "inbound": False, "inflight": [],
                                "blocks_in_flight": 1}])
        self.assertEqual(state["download_peers"], [7])

    def test_role_and_lifecycle_diagnostics_are_preserved(self):
        peer = {"id": 7, "inbound": False, "inflight": [], "blocks_in_flight": 0,
                "synced_headers": -1, "synced_blocks": -1,
                "header_sync_started": True, "block_download_stopped": False}
        state = self.snapshot([peer])
        for field in ("synced_headers", "synced_blocks", "header_sync_started",
                      "block_download_stopped"):
            self.assertEqual(state["peers"][0].get(field), peer[field])
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            STATUS.render(state)
        self.assertIn("header_sync=True", output.getvalue())
        self.assertIn("stopped=False", output.getvalue())

    def test_older_rpc_fields_remain_supported(self):
        state = self.snapshot([{"id": 4, "inbound": True, "inflight": [1]}])
        self.assertEqual(state["download_peers"], [4])
        self.assertNotIn("header_sync_started", state["peers"][0])
        with contextlib.redirect_stdout(io.StringIO()):
            STATUS.render(state)

    def test_active_header_deadline_is_preserved_and_displayed(self):
        state = self.snapshot([{"id": 7, "inbound": False, "blocks_in_flight": 0,
                                "header_sync_deadline": 1800000900,
                                "header_sync_timeout_remaining": 899.5}])
        self.assertEqual(state["peers"][0].get("header_sync_deadline"), 1800000900)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            STATUS.render(state)
        self.assertIn("header_remaining=899.5s", output.getvalue())

    def test_global_counts_match_the_peer_snapshot_when_requests_change(self):
        state = self.snapshot([{"id": 7, "inbound": False, "blocks_in_flight": 128,
                                "global_blocks_in_flight": 128,
                                "global_validated_blocks_in_flight": 128}])
        # getpeerinfo runs after getblockchaininfo. Its counts describe the
        # same locked snapshot as the peer rows we display.
        self.assertEqual(state["global_blocks_in_flight"], 128)
        self.assertEqual(state["global_validated_blocks_in_flight"], 128)

    def test_global_counts_remain_available_without_peers(self):
        state = self.snapshot([])
        self.assertEqual(state["global_blocks_in_flight"], 1)
        self.assertEqual(state["global_validated_blocks_in_flight"], 0)


if __name__ == "__main__":
    unittest.main()

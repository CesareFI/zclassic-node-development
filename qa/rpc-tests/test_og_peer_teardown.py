#!/usr/bin/env python3
"""Check test-daemon shutdown against real, bounded local child processes."""
import importlib.util
import pathlib
import subprocess
import sys
import unittest

SPEC = importlib.util.spec_from_file_location(
    "og_teardown", pathlib.Path(__file__).with_name("og-peer-teardown.py"))
HARNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HARNESS)


class ShutdownTests(unittest.TestCase):
    def child(self, code):
        child = subprocess.Popen([sys.executable, "-c", code], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 text=True)
        self.addCleanup(self.reap, child)
        return child

    @staticmethod
    def reap(child):
        if child.poll() is None:
            child.terminate()
        child.wait(timeout=5)
        for stream in (child.stdin, child.stdout, child.stderr):
            stream.close()

    def ready_child(self):
        child = self.child("import signal,sys\n"
                           "signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))\n"
                           "print('ready', flush=True)\n"
                           "sys.stdin.readline()\n")
        self.assertEqual(child.stdout.readline(), "ready\n")
        return child

    def test_already_exited_preserves_failure_without_rpc(self):
        for code in (0, 7):
            with self.subTest(exit=code):
                child = self.child("raise SystemExit(" + str(code) + ")")
                child.wait(timeout=5)
                report = {"pass": True}
                calls = []
                HARNESS.stop_daemon(child, calls.append, report)
                self.assertEqual(calls, [])
                self.assertEqual(report["exit"], code)
                self.assertFalse(report["pass"])
                self.assertFalse(report["stop_attempted"])
                self.assertTrue(report["unexpected_exit"])

    def test_normal_rpc_shutdown(self):
        child = self.ready_child()
        report = {"pass": True}

        def rpc(method):
            self.assertEqual(method, "stop")
            child.stdin.write("stop\n")
            child.stdin.flush()
            return "stopping"

        HARNESS.stop_daemon(child, rpc, report, timeout=5)
        self.assertTrue(report["pass"])
        self.assertEqual(report["exit"], 0)
        self.assertTrue(report["stop_attempted"])
        self.assertNotIn("shutdown_signal", report)

    def test_rpc_failure_terminates_gracefully_but_still_fails(self):
        child = self.ready_child()
        report = {"pass": True}

        def failed_rpc(method):
            raise RuntimeError("fixture RPC unavailable")

        HARNESS.stop_daemon(child, failed_rpc, report, timeout=5)
        self.assertEqual(report["exit"], 0)
        self.assertEqual(report["shutdown_signal"], "SIGTERM")
        self.assertIn("fixture RPC unavailable", report["shutdown_error"])
        self.assertFalse(report["pass"])

    def test_shutdown_timeout_terminates_gracefully_but_still_fails(self):
        child = self.ready_child()
        report = {"pass": True}
        HARNESS.stop_daemon(child, lambda method: "stopping", report, timeout=1)
        self.assertEqual(report["exit"], 0)
        self.assertEqual(report["shutdown_signal"], "SIGTERM")
        self.assertIn("TimeoutExpired", report["shutdown_error"])
        self.assertFalse(report["pass"])


if __name__ == "__main__":
    unittest.main()

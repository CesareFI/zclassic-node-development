# Zclassic development status

Updated: 2026-09-13 23:02 UTC.

## Current mission

Continue autonomous original-node reliability, synchronization, diagnostics,
efficiency, and defensive correctness work. Preserve consensus and /root/.zclassic.
No main push, production changes, destructive data operations, mining, external
peer scanning, or malformed-message/socket-security campaigns. Do not resume the
unfinished sequence described below. If a tool refuses any security operation,
abandon that operation immediately and move to another safe task; no retry or
reformulation. Current user instruction was read from
/root/.codex/attachments/678d6916-f1aa-4a5e-8b29-7baea7b4168c/pasted-text-1.txt.

## Repository and production

- Working directory /opt/zclassic-money, branch fix/og-node-sync-20260913.
- Latest validated commit 60548418a: immediate owned-notfound response recovery.
- Prior milestones: 8edfb0afd address counts; 549a2f43a sparse selection;
  55cf564aa preferred outbound header discovery;dc4beef1d parser recovery.
- Running production PID 503646 uses deleted inode SHA256
  6c4a80ec792c894aa1be9d27332f7d05e857e36408485e3b651fe114f3be14ad
  (deployment e9fa74638). On-disk src/zclassicd remains SHA256
  bc161f5339039ca1bacd1653dd45c2b42f409c4982b029609e8316869cca3c4f.
  Neither matches current candidate source. No production action this continuation.
- Build normal candidates without replacing service executable:
  make -C src -j2 EXEEXT=-mission zclassicd-mission.
- Repository-local Git identity now Codex <codex@localhost>, per updated user rule.

## Preserved completed evidence

Existing accounting, timeout, peer lifetime, benchmark, parser and sanitizer
results remain valid for their stated versions/scopes. Do not repeat completed
security sequences. See doc/og-node-sync-investigation.md and private mission/.
Recent ordinary synchronization evidence: eight reconnects then inbound A with 128 requests,
quiet preferred B discovers headers, A timeout 300.037/300.068s, B validates 129 blocks
(normal/ASan), global requests 0, no restart. notfound variant: outbound A with 128 / B with 0 requests, valid
negative response, disconnect 0.704/0.657s, B validates 129 blocks, global requests 0, normal stops.
Notfound selected 43 normal cases PASS 49.375s, ASan/UBSan/leak PASS 87.799s.

Block 478544 has a separate historical transaction-size incompatibility. Existing
strict historical validation accepts it; current code rejects bad-txns-oversize
because of an ungated later size-limit reduction. No consensus changes or bypass
were made. Production advancement is not claimed. Preserve all historical evidence.

## Set-aside unfinished work

Misbehavior score locking/saturation and Bloom lock-order follow-up were unfinished
when the mission changed. Preserved reversibly in stash@{0}, message
"Preserve unfinished misbehavior work; pause sequence per updated mission".
Source files and all private evidence are intact. Do NOT pop/restart that sequence.
All its prior build/test processes had stopped before stashing. The TSAN
worktree still contains those candidate source copies; do not run that sequence.
The ASan source files were restored from the root working tree before building
the current diagnostic changes. Root source was restored to 60548418a before
starting this diagnostic milestone.
Detailed previous status preserved in mission/status-before-updated-mission-20260913T2244.md.

## Validated diagnostic milestone

Add per-peer header_sync_started and block_download_stopped fields to
getpeerinfo, using existing state under cs_main. Extend sync-status.py with
those roles and known heights. Identify downloaders using request counts even
when the known-height list is empty; prefer global counts from the same peer
snapshot rather than a preceding blockchain RPC call.

- New ordinary RPC regression failed before the C++ change (missing role field).
- Normal test passes: 687 assertions, 2.074 seconds. Covers fresh/assigned/stopped
  states, idempotent disconnect and healthy reassignment through fixture 129.
- Five local Python fixture tests pass; both omitted downloader and mismatched
  RPC snapshot counts failed before their respective fixes.
- Candidate daemon built as src/zclassicd-mission. Production untouched.
- ASan/UBSan/leak check passes: the same 687 assertions, 3.943 seconds.
  Its source files exactly matched the staged diagnostic snapshot.
- Evidence: mission/download-diagnostics-*.log.

Next: cover the ordinary header-sync completion gap. A valid empty or short response currently retains
the preferred header role and can suppress discovery from another peer.
Do not resume the stashed sequence or repeat completed security campaigns.

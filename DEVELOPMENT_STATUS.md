# Zclassic development status

Updated: 2026-09-14 00:21 UTC.

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
- Latest validated milestone: bounded preferred-source scan (this snapshot).
- Prior 0514633fa: inbound fallback after completed preferred discovery.
- Prior 865993abf: header-response deadlines; 286036078: header completion.
- Prior a7f7bd07d: peer download role diagnostics.
- Prior 60548418a: immediate owned-notfound response recovery.
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

## Validated header-completion milestone

Three ordinary regressions reproduced a retained header role after valid empty
or short responses. Completion now frees that role and remembers the initial
exchange ended, retaining preferred eligibility and outstanding block ownership.

- Eight selected ordinary cases pass: 5,162 assertions, normal 12.132 seconds,
  ASan/UBSan/leak 25.275 seconds. No excluded security sequence was run.
- New og-header-discovery.py: normal empty/short responses and instrumented short
  response all pass. A holds 128 / B receives block 129 in the short case;
  ordinary A disconnect releases work and B validates all 129. Exit 0, no errors.
- Existing valid-notfound wire recovery passes after two reconnects. Its fixture
  leaves A's getheaders unanswered to isolate negative-response role cleanup.
- Normal and ASan candidates both built as zclassicd-mission in their own trees.
- Evidence: mission/header-completion-*.

Next: investigate unanswered initial header requests with no outstanding blocks.
They currently have no response-specific timeout. Use ordinary state-machine
fixtures and mock time; preserve validation and avoid peer-name discrimination.
Do not resume the stashed sequence or repeat completed security campaigns.


## Validated header-response timeout milestone

Committed as 865993abf. All tests finished before the commit.

A 15-minute per-response deadline expires unanswered header exchanges even with
no block requests. It renews only when validated chain work advances in a full
160-header batch, supporting a shorter fork with more work. Empty/short completion
and disconnect clear it. Import/reindex cancels an active exchange for a fresh
retry after replies stop being ignored. No consensus/protocol changes.

- Initial silent-header baseline fails four assertions; repeated valid full batch
  baseline fails three. Advancing-batch control passes before/after.
- Final chain-work-based version: 12 ordinary cases, 8,063 assertions all pass
  normally (15.944 seconds) and ASan/UBSan/leak (32.477 seconds).
- Six Python tests pass, including deadline display; that test failed before.
- ASan timer source exactly matched the staged snapshot before building; its
  source tree has since been advanced to the next fallback task. Timer executable
  zclassicd-mission remained SHA256 e3c476353f08aac42d0c827ea6495cf0a1ec5c862bbecd4b298eb53315ac453a.
- Final normal short-response wire case passes. Early normal timer silent case
  passes after 900.107s; FINAL instrumented timer silent case passes after
  900.099s. Both validate 129, counters zero, exit 0, no peer/sanitizer errors.
- All timer build/unit/wire jobs completed. Do not duplicate completed runs.
- Evidence: mission/header-timeout-*. Header extension fixture is staged with
  checksum/provenance in src/test/data/README.md.

## Validated inbound fallback milestone

HasPreferredDownloadSource consults completed discovery and
validated available work instead of excluding inbounds merely because an outbound
remains connected. Pending preferred discovery, assigned work, and validated work
beyond the active tip retain priority. Known inventory is resolved before deciding.

- Ordinary baseline: outbound answers empty; inbound gets no getheaders. Exit 201.
- Three new cases plus 12 timer/recovery controls pass 9,955 assertions normally
  (19.640s) and under ASan/UBSan/leak (39.049s).
- Real baseline fails B discovery; fixed normal and instrumented daemons validate
  129, counters zero, exit 0, no peer or sanitizer errors. Outbound A stays connected.
- Initial wire attempts used maxconnections=8, below 16 reserved outbound slots;
  B was dropped before handshake. Those failures remain preserved. The isolated
  inbound fixture now uses 32. Corrected evidence: mission/inbound-fallback-wire-
  {before,after,asan}-capacity. Unit/build logs: mission/inbound-fallback-*.
- Normal and ASan next candidates are zclassicd-fallback, separately named from
  the completed timer binaries. No production executable/service/data changed.
- All fallback test/build processes completed. Do not resume the paused stash.


## Validated idle scheduling optimization

Stop checking peer state once the existing preferred count has been examined.
No additional mutable index or ownership state. Three quiet loop measurements
(1,000 full rounds; preferred peer first) improved median 125-peer time from
0.103885s to 0.023699s; 750-peer time from 2.528977s to 0.157800s. These are local
scheduling-loop measurements, not whole-node CPU estimates.

- Added bounded 125/750-peer completed-role coverage and a preferred source after
  64 inbound peers. Late preferred discovery/work retains priority, then cleanup
  allows inbound takeover and full fixture validation.
- 18 selected ordinary cases / 20,067 assertions pass normally (21.007s) and
  ASan/UBSan/leak (46.137s). Both zclassicd-mission candidates rebuild successfully.
- All builds/tests complete; evidence mission/scheduling-{idle,scale}-*.
- Initial benchmark constructor had an unsigned-overload ambiguity; corrected to
  the explicitly bounded int port before recording successful measurements.
- Next: isolate and test cache-size conversion. init.cpp currently shifts the
  signed -dbcache argument before clamping. Test pure arithmetic without startup
  or live datadir access, then fix conversion order if reproduced.

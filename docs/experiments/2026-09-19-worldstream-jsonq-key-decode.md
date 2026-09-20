<!-- Copyright 2026 Rhett Creighton. Licensed under Apache-2.0. -->

# Worldstream: reduce JSON observation key conversion

Branch: `agent/worldstream-ibd-20260918`; baseline HEAD:
`c1f7863d098e1efaa8deba240c580ae0559312a5`.

The two-node peer-tip observer uses `jsonq raw error` and `jsonq raw result`
to inspect RPC envelopes. During path lookup, jsonq converted every encountered
key through `zjsonp_str_decode`, including plain ASCII keys. That decoder
encodes each byte through the Unicode encoder. A wide response therefore
spends avoidable CPU converting unchanged keys during every observation.

The change is confined to `tools/jsonq.c`: validated, unescaped ASCII keys
use a checked copy. Escaped and non-ASCII keys retain the existing decoder
and its exact behavior. Full-document validation still precedes every query.
No parser package, node, consensus, cryptography, acceleration policy,
scheduler, database or production state changed in this slice.

## Measurements

Linux x86_64, 48 reported logical processors, GCC 14.2.0, C23 `-O2`, warm
tools and filesystem caches, uncontrolled ambient host load. Each response
contains 20,000 synthetic diagnostic keys before a result object and null
error. Three sequential baseline/candidate pairs each run 100 `raw result`
processes with output discarded. Lint initialization overlapped the run.
These are observer stress measurements, not live IBD or time-to-tip evidence.

| Response bytes | Baseline wall seconds | Candidate wall seconds | Median reduction |
|---|---|---|---|
| 480,042 | 0.93 / 0.95 / 0.91 | 0.72 / 0.83 / 0.86 | 11% |
| 3,920,042 | 4.94 / 4.80 / 4.87 | 4.01 / 4.03 / 4.16 | 17% |

Reported maximum RSS was unchanged: 3,072 KiB and 4,992 KiB respectively.
Small ordinary RPC responses may be dominated by process startup; no
production speedup is claimed. Full-document scanning remains necessary.

Baseline source SHA-256:
`38a17c35cf86a0f51d55b252183ef6ecd73a9222fb3b61cf5d13d154ea3771bf`.
Candidate source SHA-256:
`e7112450f29db0116e02f5357fea2df085192ccc16ec4a97dd789308f483e223`.
Baseline source/binary, candidate binary and input fixtures are temporary
development evidence in `/tmp/worldstream-jsonq-keys/`, not committed output.

## Reproduction and validation

```sh
bash tools/scripts/jsonq_key_decode_selftest.sh --bench
ASAN_OPTIONS=detect_leaks=0 CC=clang-20 \
  CFLAGS='-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer' \
  bash tools/scripts/jsonq_key_decode_selftest.sh
```

The script compiles the tool and a decoder-parity harness in a temporary
directory. It checks ASCII key lengths around the capacity boundary, ASCII
punctuation, escaped keys, embedded NUL, surrogate pairs, non-ASCII fallback,
and encoded keys longer than their decoded buffer. Each case compares exact
bytes and success/refusal against the existing decoder at capacities 0–258.
A deterministic work budget requires zero decoder calls for plain ASCII.
The baseline passes all CLI fixtures and fails that new work budget.

CLI fixtures cover all query modes, nested and duplicate keys, missing paths,
RPC errors, and malformed suffixes/UTF-8/escapes without partial output.
The existing two-node peer-tip selftest also passes in a copied fixture tree
using the candidate jsonq; it opens no node or socket. That observer script
contains pre-existing work which is not included in this slice.

GCC and Clang compile with warnings as errors. GCC `-fanalyzer`, Clang static
analysis, ASan/UBSan, Bash syntax, architecture-tree, C23-only, allocation,
JSON initialization, shell-host-assumption, pipefail-status and discarded-status
checks pass. LeakSanitizer itself cannot operate under this sandbox's tracing;
only leak detection is disabled for the sanitizer run. `git diff --check`
passes. `make lint-fast` timed out after 60 seconds during initialization;
no aggregate lint, full node build or live-chain acceptance is claimed.

Publication remains blocked. The checkout's `.git` is read-only: staging
fails creating `index.lock`, and branch fetch fails writing `FETCH_HEAD`.
The origin branch lookup also fails resolving GitHub. No commit, push or
remote-SHA verification is claimed. Earlier staged and unstaged work is
preserved. This slice consists only of this record, `tools/jsonq.c`, and
`tools/scripts/jsonq_key_decode_selftest.sh`; it includes no credentials,
logs, datadirs, binaries or generated output. An exact slice patch is saved
at `/tmp/worldstream-jsonq-keys/slice.patch` for review and later integration.

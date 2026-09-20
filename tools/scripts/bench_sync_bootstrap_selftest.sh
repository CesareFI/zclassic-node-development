#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton. Licensed under Apache-2.0.
# Exercise Make's bootstrap and epoch selection with inert build fixtures.
set -euo pipefail

root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
source_make=${1:-"$root/Makefile"}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/zcl-bench-bootstrap.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

cat > "$scratch/Makefile" <<'MAKE'
.DEFAULT_GOAL := fixture-default
.SUFFIXES:
ZCL_HOST_OS := Linux
ZCL_VENDOR_LIB := vendor/lib
TOR_ARCHIVE_PATHS := vendor/tor/libtor.a
MAKE
# Keep the production conditionals and include decisions intact. Only the
# recipes that would download/build libraries are replaced by local markers.
awk '
    /^NODE_SECP_ARCHIVE =/ { copy = 1; vendor++ }
    /^# Generated view headers/ { copy = 0 }
    /^ZCL_TOR \?=/ { copy = 1; tor++ }
    /^# The stub is reachable/ { copy = 0 }
    copy { print }
    END { if (vendor != 1 || tor != 1) exit 1 }
' "$source_make" >> "$scratch/Makefile"
awk '
    /^ZCL_EPOCH_ALL_PROFILES :=/ { copy = 1; starts++ }
    /^ifneq \(\$\(origin BUILD_SOURCE_RECORD\),command line\)/ { copy = 0; ends++ }
    copy { print }
    END { if (starts != 1 || ends != 1) exit 1 }
' "$source_make" >> "$scratch/Makefile"
cat >> "$scratch/Makefile" <<'MAKE'
$(file >profiles,$(strip $(ZCL_EPOCH_PROFILES)))
build/identity/vendor-inputs-ready.mk:
	@mkdir -p $(@D)
	@printf 'vendor\n' >> observed
	@touch $@
build/identity/tor-inputs-ready.mk:
	@mkdir -p $(@D)
	@printf 'tor\n' >> observed
	@touch $@
.PHONY: fixture-default z23 zclassic23 bench-sync vendor-ready unknown-goal
.PHONY: bench_fresh_sync bench-fresh-sync-selftest bench-fresh-sync-height-selftest
.PHONY: bench-sync-bootstrap-selftest help
.PHONY: fold-profile-selftest fold-profile-summary-selftest
fixture-default z23 zclassic23 bench-sync vendor-ready unknown-goal \
bench_fresh_sync bench-fresh-sync-selftest bench-fresh-sync-height-selftest \
bench-sync-bootstrap-selftest help build/bin/bench_fresh_sync \
fold-profile-selftest fold-profile-summary-selftest:
	@:
MAKE

cases=0
check()
{
    local expected=$1 actual
    shift
    rm -f "$scratch/observed" "$scratch/build/identity/vendor-inputs-ready.mk" \
        "$scratch/build/identity/tor-inputs-ready.mk"
    make -sr --no-print-directory -C "$scratch" "$@"
    actual=none
    if [[ -f "$scratch/observed" ]]; then
        actual=$(LC_ALL=C sort "$scratch/observed" | tr '\n' ' ')
    fi
    if [[ $actual != "$expected" ]]; then
        printf 'bench-sync-bootstrap: FAIL goals=[%s] expected=[%s] observed=[%s]\n' \
            "$*" "$expected" "$actual" >&2
        exit 1
    fi
    cases=$((cases + 1))
}

for goal in bench_fresh_sync build/bin/bench_fresh_sync \
    bench-fresh-sync-selftest bench-fresh-sync-height-selftest \
    bench-sync-bootstrap-selftest fold-profile-selftest fold-profile-summary-selftest; do
    check none "$goal"
    check 'tor vendor ' "$goal" z23
    check 'tor vendor ' z23 "$goal"
    check 'tor vendor ' "$goal" unknown-goal
    check 'vendor ' "$goal" vendor-ready
done
check none bench_fresh_sync bench-fresh-sync-selftest
check none help bench-fresh-sync-selftest
check none fold-profile-selftest fold-profile-summary-selftest
check none fold-profile-selftest bench-fresh-sync-selftest
check 'tor vendor '
check 'tor vendor ' zclassic23
check 'tor vendor ' bench-sync
check 'tor vendor ' unknown-goal
printf 'bench-sync-bootstrap-selftest: PASS (%s cases)\n' "$cases"

# Standalone benchmark recipes never consume node/test epoch objects. Check
# the production selector directly; default, mixed and unknown goals must
# retain the profiles needed by their possible build graph.
all_profiles='build-only dev dev-asan dev-tsan test-fast test-strict test-asan test-tsan coverage node-c23'
profile_cases=0
check_profiles()
{
    local expected=$1 actual
    shift
    make -sr --no-print-directory -C "$scratch" "$@"
    actual=$(<"$scratch/profiles")
    if [[ $actual != "$expected" ]]; then
        printf 'bench-sync-epochs: FAIL goals=[%s] expected=[%s] observed=[%s]\n' \
            "$*" "$expected" "$actual" >&2
        exit 1
    fi
    profile_cases=$((profile_cases + 1))
}
for goal in bench_fresh_sync build/bin/bench_fresh_sync \
    bench-fresh-sync-selftest bench-fresh-sync-height-selftest \
    bench-sync-bootstrap-selftest fold-profile-selftest fold-profile-summary-selftest; do
    check_profiles '' "$goal"
    check_profiles '' "$goal" ZCL_PROFILE=dev
    check_profiles "$all_profiles" "$goal" z23
    check_profiles "$all_profiles" z23 "$goal"
    check_profiles "$all_profiles" "$goal" unknown-goal
done
check_profiles '' bench_fresh_sync bench-fresh-sync-selftest
check_profiles '' bench-fresh-sync-selftest bench_fresh_sync
check_profiles '' fold-profile-selftest fold-profile-summary-selftest
check_profiles '' fold-profile-selftest bench-fresh-sync-selftest
check_profiles "$all_profiles" help bench-fresh-sync-selftest
check_profiles "$all_profiles" bench-sync
check_profiles "$all_profiles" unknown-goal
check_profiles node-c23
check_profiles dev ZCL_PROFILE=dev
check_profiles node-c23 z23
check_profiles node-c23 zclassic23
printf 'bench-sync-epochs-selftest: PASS (%s cases)\n' "$profile_cases"

#!/usr/bin/env bash
# Copyright 2026 Rhett Creighton - Apache License 2.0
# Hermetic benchmark integer observations; optional argument selects old source.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
subject=${1:-$root/tools/bench_fresh_sync.c}
fixture=$(mktemp -d /tmp/z23-bench-integer.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
cat > "$fixture/test.c" <<'C'
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
C
sed -n '/^static long json_get_int(/,/^}/p' "$subject" >> "$fixture/test.c"
cat >> "$fixture/test.c" <<'C'
static int checks, failures;
static void check(const char *doc, long expected)
{
    long actual = json_get_int(doc, "result");
    checks++;
    if (actual != expected) {
        fprintf(stderr, "FAIL fixture %d: expected %ld, got %ld\n",
                checks, expected, actual);
        failures++;
    }
}
int main(void)
{
    check("{\"result\":1234567}", 1234567);
    check("{\"result\" : 1234567}", 1234567);
    check("{\n\"result\"\t:\r\n1234567 \t\r\n}", 1234567);
    check("{\"id\":\"result\",\"result\" : 1234567}", 1234567);
    check("{\"result_next\":9,\"result\":0,\"error\":null}", 0);
    check("{\"result\":-1}", -1);
    check("{\"result\":-0}", 0);
    const char *invalid[] = {
        "", "{}", "{\"result\":null}", "{\"result\":true}",
        "{\"result\":\"123\"}", "{\"result\":}", "{\"result\":+123}",
        "{\"result\":01}", "{\"result\":-01}", "{\"result\":1.5}",
        "{\"result\":1e6}", "{\"result\":123oops}", "{\"result\":123",
        "{\"result\":123 \n", "{\"result\":--1}",
        "{\"result\":999999999999999999999999999999999999999}",
        "{\"result\":-999999999999999999999999999999999999999}"
    };
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++)
        check(invalid[i], -1);
    char doc[128];
    snprintf(doc, sizeof(doc), "{\"result\":%ld}", LONG_MAX);
    errno = ERANGE; /* A previous operation's errno must not reject a value. */
    check(doc, LONG_MAX);
    snprintf(doc, sizeof(doc), "{\"result\":%ld}", LONG_MIN);
    check(doc, LONG_MIN);
    snprintf(doc, sizeof(doc), "{\"result\":%ld0}", LONG_MAX);
    check(doc, -1);
    printf("integer observations: checks=%d failures=%d\n", checks, failures);
    return failures ? 1 : 0;
}
C
flags=(-std=c23 -Wall -Wextra -Werror -pedantic)
"${CC:-cc}" "${flags[@]}" -O2 "$fixture/test.c" -o "$fixture/test"
"${CC:-cc}" "${flags[@]}" -fanalyzer -c "$fixture/test.c" -o "$fixture/analyzed.o"
"$fixture/test"

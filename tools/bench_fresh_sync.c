/* Copyright 2026 Rhett Creighton - Apache License 2.0
 *
 * Cold-start benchmark: measures time from zero to fully synced
 * block explorer via FlyClient + MMB + SHA3 UTXO snapshot.
 *
 * Spawns a fresh zclassic23 node, monitors RPC + log, reports
 * phase timing for each step of the fast sync pipeline.
 *
 * Build: make bench_fresh_sync
 * Run:   build/bin/bench_fresh_sync
 * HTTP observers ignore default curl configuration so ambient retries,
 * output redirects and extra URLs cannot change the measurement.
 * Exit:  0 only when tip + explorer + grace complete within TIMEOUT;
 *        1 on incomplete measurement or setup/runtime failure.
 */

#include "platform/time_compat.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdbool.h>

#define PORT       8047
#define RPCPORT    18247
#define HTTPSPORT  8447
#define TIMEOUT    1800

static pid_t g_child = 0;
static double now_sec(void);

static void cleanup(void)
{
    if (g_child > 0) {
        kill(g_child, SIGTERM);
        const double deadline = now_sec() + 0.5;
        int status;
        /* Retain the shutdown grace period, but return promptly when the
         * benchmark child exits. Interrupted sleeps cannot shorten grace. */
        for (;;) {
            pid_t waited;
            do {
                waited = waitpid(g_child, &status, WNOHANG);
            } while (waited < 0 && errno == EINTR);
            if (waited != 0) {
                if (waited < 0) perror("bench-sync: wait for child shutdown");
                g_child = 0;
                return;
            }
            double observed = now_sec();
            if (observed >= deadline) break;
            const struct timespec interval = {0, 10000000};
            const double next_poll = observed + 0.01;
            /* Signals do not warrant another child-status query. Retry the
             * short sleep until the poll interval or shutdown grace expires.
             * As with ordinary scheduling, a sleep may overshoot by 10 ms. */
            while (nanosleep(&interval, NULL) != 0) {
                if (errno != EINTR) {
                    perror("bench-sync: sleep during child shutdown");
                    break;
                }
                observed = now_sec();
                if (observed >= next_poll || observed >= deadline) break;
            }
        }
        kill(g_child, SIGKILL);
        pid_t waited;
        do {
            waited = waitpid(g_child, &status, 0);
        } while (waited < 0 && errno == EINTR);
        if (waited < 0) perror("bench-sync: reap child after forced shutdown");
        g_child = 0;
    }
}

static double now_sec(void)
{
    struct timespec ts;
    platform_time_monotonic_timespec(&ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec / 1e9;
}

/* Find the latest snapshot summary from the end of this child's text log.
 * Snapshot the extent, use bounded memory even for oversized lines, and stop
 * at the first matching line. Bound this display-only lookup to the final
 * 16 MiB so an absent summary cannot scan an arbitrarily large IBD log.
 * This is display-only evidence, never a snapshot-validation predicate.
 * The chunk buffer is writable and NUL-terminated at want; temporary search
 * boundaries are restored before returning. */
static off_t snapshot_log_bisect(char *buf, size_t want, size_t first,
                                 const char *marker, size_t marker_len,
                                 off_t match)
{
    size_t low = (size_t)match + 1, high = first;
    while (low < high) {
        size_t mid = low + (high - low) / 2;
        size_t limit = want - high < marker_len - 1 ?
            want : high + marker_len - 1;
        char saved = buf[limit];
        buf[limit] = '\0';
        const char *p = strstr(buf + mid, marker);
        buf[limit] = saved;
        if (p) {
            match = (off_t)(p - buf);
            low = (size_t)match + 1;
        } else {
            high = mid;
        }
    }
    return match;
}

static off_t snapshot_log_chunk(char *buf, size_t want,
                                const char *marker, size_t marker_len)
{
    /* Recent summaries usually end this chunk. Look in its final 64 bytes
     * first, retaining the whole-buffer fallback for older candidates. */
    size_t tail = want > 64 ? want - 64 : 0;
    const char *last = strrchr(buf + tail, marker[0]);
    if (!last && tail > 0) last = strrchr(buf, marker[0]);
    if (!last) return -1;
    /* A short unrelated U suffix must not force enumeration of every older
     * summary. Bound the reverse walk; bulk search handles the rest. */
    size_t pos = (size_t)(last - buf) + 1;
    /* Exhaust the small initial read here so a miss adds no bulk searches
     * before the next chunk. Larger reads retain the 64-byte reverse bound. */
    size_t reverse = want <= 512 ? want : 64;
    size_t first = pos > reverse ? pos - reverse : 0;
    while (pos > first) {
        pos--;
        if (buf[pos] == marker[0] && want - pos >= marker_len &&
            memcmp(buf + pos, marker, marker_len) == 0)
            return (off_t)pos;
    }
    if (first == 0) return -1;
    off_t match = -1;
    const char *p = buf;
    /* Ordinary logs have few summaries. Keep their linear bulk search,
     * switching only when repeated matches make enumeration expensive. */
    for (int i = 0; i < 8; i++) {
        p = strstr(p, marker);
        if (!p) return match;
        match = (off_t)(p - buf);
        p++;
    }
    /* Repeated summaries followed by a long unrelated suffix must not
     * enumerate every historic match. A suffix either contains a later
     * match or excludes every start in that suffix: bisect the remaining
     * start positions. The short reverse walk already excluded first..end.
     * Sparse buffers return from the small linear search above. */
    /* Excluded starts need not be searched again. The helper restores every
     * borrowed text boundary before returning. */
    return snapshot_log_bisect(buf, want, first, marker, marker_len, match);
}

static off_t snapshot_log_match(FILE *f, off_t end)
{
    static const char marker[] = "UTXOs in";
    char buf[65536 + sizeof(marker)];
    char suffix[sizeof(marker) - 2];
    size_t overlap = 0;
    off_t offset = end;
    off_t match = -1;
    const off_t budget = 16 * 1024 * 1024;
    const off_t floor = end > budget ? end - budget : 0;
    while (offset > floor) {
        off_t remaining = offset - floor;
        /* A recent displayable summary fits in 512 bytes. Start with that
         * window; amortize older reads in bulk. The 16 MiB budget is unchanged. */
        size_t chunk = offset == end ? 512 : 65536;
        size_t step = remaining < (off_t)chunk ? (size_t)remaining : chunk;
        /* Retain the right-hand overlap in memory. Reading these seven
         * bytes again makes stdio fetch another buffer on every chunk. */
        size_t want = step + overlap;
        offset -= (off_t)step;
        if (fseeko(f, offset, SEEK_SET) != 0 || fread(buf, 1, step, f) != step) {
            fprintf(stderr, "bench-sync: snapshot log read failed at %lld\n", (long long)offset);
            return -1;
        }
        memcpy(buf + step, suffix, overlap);
        if (memchr(buf, '\0', want)) {
            fprintf(stderr, "bench-sync: binary snapshot log has no text summary\n");
            return -1;
        }
        buf[want] = '\0';
        off_t found = snapshot_log_chunk(buf, want, marker, sizeof(marker) - 1);
        if (found >= 0) {
            match = offset + found;
            break;
        }
        overlap = want < sizeof(suffix) ? want : sizeof(suffix);
        memcpy(suffix, buf, overlap);
    }
    if (match < 0 && floor > 0)
        fprintf(stderr, "bench-sync: snapshot summary unavailable in final 16 MiB of log\n");
    return match;
}

/* A displayable line must fit within this small window around its match.
 * Read both boundaries so a long suffix or prefix cannot be truncated
 * into a plausible-looking summary. */
static void snapshot_log_line(FILE *f, off_t extent, off_t match, char *line, size_t size)
{
    char buf[512];
    off_t offset = match > 255 ? match - 255 : 0;
    off_t remaining = extent - offset;
    size_t want = remaining < 512 ? (size_t)remaining : 512;
    if (fseeko(f, offset, SEEK_SET) != 0 || fread(buf, 1, want, f) != want) {
        fprintf(stderr, "bench-sync: snapshot summary read failed\n");
        return;
    }
    size_t start = (size_t)(match - offset), end = start;
    while (start > 0 && buf[start - 1] != '\n') start--;
    while (end < want && buf[end] != '\n') end++;
    size_t len = end - start;
    /* grep emits a newline even for an unterminated final line. Preserve
     * run_cmd's old limit, which included that newline and the final NUL. */
    if ((start == 0 && offset > 0) ||
        (end == want && offset + (off_t)want < extent) || len >= size - 1) {
        fprintf(stderr, "bench-sync: oversized snapshot summary\n");
        return;
    }
    memcpy(line, buf + start, len);
    line[len] = '\0';
}

static void snapshot_log_summary(const char *path, char *line, size_t size)
{
    line[0] = '\0';
    FILE *f = fopen(path, "r");
    if (!f) { perror("bench-sync: open snapshot log"); return; }
    /* Reverse reads already use explicit chunks. Stdio seek/read-ahead
     * rereads partial blocks when the log extent is not block-aligned. */
    if (setvbuf(f, NULL, _IONBF, 0) != 0)
        fprintf(stderr, "bench-sync: unbuffered snapshot log unavailable\n");
    struct stat st;
    if (fstat(fileno(f), &st) != 0) {
        perror("bench-sync: stat snapshot log");
    } else {
        off_t match = snapshot_log_match(f, st.st_size);
        if (match >= 0) snapshot_log_line(f, st.st_size, match, line, size);
    }
    fclose(f);
}

/* Startup progress needs only the last line, not a shell and tail process.
 * Read at most line_size bytes from a snapshot of the log's end. Preserve
 * run_cmd's refusal of oversized lines, including their terminating newline. */
static void startup_log_tail(const char *path, char *line, size_t line_size)
{
    line[0] = '\0';
    FILE *f = fopen(path, "r");
    if (!f) {
        perror("bench-sync: open startup progress log");
        return;
    }
    /* This stream reads one small tail and closes. Disable stdio read-ahead:
     * seeking within a buffered stream can read a whole preceding block. */
    if (setvbuf(f, NULL, _IONBF, 0) != 0)
        fprintf(stderr, "bench-sync: unbuffered startup log unavailable\n");
    struct stat st;
    if (fstat(fileno(f), &st) != 0) {
        perror("bench-sync: locate startup progress log end");
        fclose(f);
        return;
    }
    /* Snapshot the open file's extent without seeking to EOF and back. */
    off_t end = st.st_size;
    size_t want = end > (off_t)line_size ? line_size : (size_t)end;
    if (fseeko(f, end - (off_t)want, SEEK_SET) != 0) {
        perror("bench-sync: seek startup progress log tail");
        fclose(f);
        return;
    }
    size_t n = fread(line, 1, want, f);
    bool failed = ferror(f) != 0 || n != want;
    fclose(f);
    if (failed) {
        fprintf(stderr, "bench-sync: incomplete startup progress log read\n");
        line[0] = '\0';
        return;
    }
    size_t start = n;
    if (start > 0 && line[start - 1] == '\n') start--;
    while (start > 0 && line[start - 1] != '\n') start--;
    size_t len = n - start;
    if (len >= line_size) {
        fprintf(stderr, "bench-sync: oversized startup progress line\n");
        line[0] = '\0';
        return;
    }
    memmove(line, line + start, len);
    line[len] = '\0';
}

/* Capture complete, successful command output. Never expose a partial RPC
 * response as an observation: a prefix may already contain state=at_tip. */
static int run_cmd(const char *cmd, char *buf, int bufsz)
{
    buf[0] = '\0';
    FILE *f = popen(cmd, "r");
    if (!f) {
        perror("bench-sync: open command output");
        return 0;
    }
    int n = (int)fread(buf, 1, (size_t)(bufsz - 1), f);
    /* One lookahead byte distinguishes exact-fit output from truncation.
     * Closing an oversized stream may stop its writer; it is rejected either
     * way. Do not drain arbitrary output just to obtain a successful exit. */
    bool oversized = fgetc(f) != EOF;
    bool read_failed = ferror(f) != 0;
    int status = pclose(f);
    if (oversized || read_failed || status != 0) {
        /* Commands can contain RPC credentials, so never log command text. */
        fprintf(stderr, "bench-sync: command output rejected (oversized=%d read_error=%d status=%d)\n",
                oversized, read_failed, status);
        buf[0] = '\0';
        return 0;
    }
    buf[n] = '\0';
    return n;
}

/* RPC call via curl. Returns result string in buf.
 * Loopback observers bypass ambient proxies: proxy latency and responses
 * cannot establish this child's local readiness.
 * Bound each HTTP observation so a stalled endpoint cannot indefinitely hide
 * the benchmark's outer deadline or child exit. A timeout is a missing sample;
 * run_cmd rejects even a partial response containing state=at_tip. HTTP error
 * bodies likewise cannot establish state or trigger a follow-up height RPC. */
static bool rpc_call(const char *cookie, const char *method,
                     char *buf, int bufsz)
{
    char cmd[1024];
    snprintf(cmd, sizeof(cmd),
        "curl -q -s --fail --noproxy '*' --max-time 2 -u '%s' "
        "--data-binary '{\"jsonrpc\":\"1.0\",\"id\":\"b\",\"method\":\"%s\",\"params\":[]}' "
        "-H 'content-type:text/plain;' "
        "http://127.0.0.1:%d/ 2>/dev/null",
        cookie, method, RPCPORT);
    return run_cmd(cmd, buf, bufsz) > 0;
}

/* Extract a string field with either compact or formatted
 * JSON separators. RPC whitespace must not turn an at-tip sample into unknown.
 * This remains a field reader, not a general JSON decoder. */
static bool json_get_str(const char *json, const char *key, char *out, int outsz)
{
    char needle[128];
    snprintf(needle, sizeof(needle), "\"%s\"", key);
    const char *p = json;
    do {
        p = strstr(p, needle);
        if (!p) return false;
        p += strlen(needle);
        p += strspn(p, " \t\r\n");
    } while (*p != ':');
    p++;
    p += strspn(p, " \t\r\n");
    if (*p != '"') return false;
    p++;
    const char *e = strchr(p, '"');
    if (!e) return false;
    int len = (int)(e - p);
    if (len >= outsz) len = outsz - 1;
    memcpy(out, p, (size_t)len);
    out[len] = '\0';
    return true;
}

static long json_get_int(const char *json, const char *key)
{
    char needle[128];
    snprintf(needle, sizeof(needle), "\"%s\"", key);
    const char *p = json;
    do {
        p = strstr(p, needle);
        if (!p) return -1;
        p += strlen(needle);
        p += strspn(p, " \t\r\n");
    } while (*p != ':');
    p++;
    p += strspn(p, " \t\r\n");
    /* Fixed integer telemetry fields, not a general JSON decoder. Require
     * a complete integer token: missing, fractional or overflowing heights
     * must remain unavailable rather than becoming plausible observations. */
    const char *digits = p + (*p == '-');
    if (*digits < '0' || *digits > '9') return -1;
    if (*digits == '0' && digits[1] >= '0' && digits[1] <= '9') return -1;
    char *end;
    errno = 0;
    long value = strtol(p, &end, 10);
    if (errno == ERANGE) return -1;
    end += strspn(end, " \t\r\n");
    if (*end != ',' && *end != '}') return -1;
    return value;
}

enum log_phase {
    LOG_FILE_START, LOG_FILE_DONE, LOG_FLYCLIENT, LOG_SNAPSHOT_START,
    LOG_SNAPSHOT_DONE, LOG_PHASE_COUNT
};

static const char *const phase_markers[LOG_PHASE_COUNT] = {
    "File sync downloading", "File sync complete", "FlyClient PASSED",
    "negotiating -> receiving", "verifying -> complete"
};

struct phase_log {
    off_t offset;
    dev_t device;
    ino_t inode;
    bool seen[LOG_PHASE_COUNT];
    /* Retain enough bytes to match a marker split across reads or polls. */
    char tail[sizeof("negotiating -> receiving") - 2];
    size_t tail_len;
};

/* One bounded pass over newly appended bytes for all phase markers. The log
 * belongs to this benchmark's child. Previously observed phases survive a
 * replacement/truncation, just as the caller's phase timestamps always did.
 * Snapshot the size so a busy writer cannot keep a poll reading forever. */
static void phase_log_normalize(char *buf, size_t n)
{
    /* Ordinary text needs no byte walk. NULs must neither hide text nor
     * join words. Normalize bounded windows, then search the next gap:
     * a second NUL alone cannot establish that the whole suffix is binary. */
    char *binary = memchr(buf, '\0', n);
    while (binary) {
        size_t window = (size_t)(buf + n - binary);
        if (window > 256) window = 256;
        char *end = binary + window;
        /* A fixed full window lets the compiler vectorize the replacement.
         * Batch mixed binary/text runs too: NULs 65 bytes apart should not
         * require one library search each. Keep the short suffix bounded;
         * never read beyond the captured log. */
        if (window == 256) {
            for (size_t i = 0; i < 256; i++)
                binary[i] = binary[i] == '\0' ? '\n' : binary[i];
        } else {
            for (char *p = binary; p < end; p++)
                if (*p == '\0') *p = '\n';
        }
        binary = end < buf + n && *end == '\0' ? end :
            memchr(end, '\0', (size_t)(buf + n - end));
    }
}

static bool phase_log_scan_chunk(struct phase_log *log, char *buf, size_t n)
{
    phase_log_normalize(buf, n);
    buf[n] = '\0';
    bool complete = true;
    for (int i = 0; i < LOG_PHASE_COUNT; i++) {
        if (!log->seen[i] && strstr(buf, phase_markers[i]))
            log->seen[i] = true;
        complete &= log->seen[i];
    }
    log->tail_len = n < sizeof(log->tail) ? n : sizeof(log->tail);
    memcpy(log->tail, buf + n - log->tail_len, log->tail_len);
    return complete;
}

static bool phase_log_poll(FILE *f, struct phase_log *log)
{
    struct stat st;
    if (fstat(fileno(f), &st) != 0) {
        perror("bench-sync: stat phase log");
        return false;
    }
    if (st.st_dev != log->device || st.st_ino != log->inode ||
        st.st_size < log->offset) {
        log->offset = 0;
        log->tail_len = 0;
        log->device = st.st_dev;
        log->inode = st.st_ino;
    }
    /* An unchanged extent needs no seek. On a freshly opened stream, stdio
     * can reread the final partial buffer just to seek to this same EOF.
     * Check identity/truncation first and retain the tail for later appends. */
    if (log->offset == st.st_size) return true;
    /* A large startup backlog must yield to RPC and benchmark deadline
     * observations. Consume at most 16 MiB per poll; leave the cursor and
     * partial marker intact for the next turn. Phase timestamps remain
     * observation times and can lag the writer while catching up. */
    off_t end = st.st_size;
    const off_t budget = 16 * 1024 * 1024;
    if (end - log->offset > budget) end = log->offset + budget;
    if (fseeko(f, log->offset, SEEK_SET) != 0) {
        perror("bench-sync: seek phase log");
        return false;
    }
    const off_t poll_start = log->offset;
    while (log->offset < end) {
        char buf[65536 + sizeof(log->tail) + 1];
        memcpy(buf, log->tail, log->tail_len);
        off_t remaining = end - log->offset;
        /* Preserve the first two early-stop boundaries and small-append
         * reads; amortize scanner/library work over a larger backlog. */
        size_t chunk = log->offset - poll_start < 8192 ? 4096 : 65536;
        size_t want = remaining < (off_t)chunk ? (size_t)remaining : chunk;
        size_t n = fread(buf + log->tail_len, 1, want, f);
        if (n == 0) {
            fprintf(stderr, "bench-sync: phase log read stopped at %lld of %lld bytes\n",
                    (long long)log->offset, (long long)st.st_size);
            return false;
        }
        log->offset += (off_t)n;
        n += log->tail_len;
        /* The caller stops polling once every milestone is observed. Avoid
         * scanning the remaining startup history after that final match. */
        if (phase_log_scan_chunk(log, buf, n)) return true;
    }
    return true;
}

/* Check if HTTPS explorer is responding. HTTP error pages cannot establish
 * readiness even if their body contains the usual marker. Scan with bounded
 * memory. After finding the marker, drain the body and require curl success:
 * a page prefix received before timeout cannot prove readiness. */
static bool explorer_responding(void)
{
    char cmd[256];
    snprintf(cmd, sizeof(cmd),
        "curl -q -sk --fail --noproxy '*' --max-time 2 'https://127.0.0.1:%d/explorer' 2>/dev/null",
        HTTPSPORT);
    FILE *f = popen(cmd, "r");
    if (!f) {
        perror("bench-sync: open explorer response");
        return false;
    }
    static const char marker[] = "Latest Blocks";
    /* Batch body reads to reduce observer work on large IBD pages. Keep
     * memory bounded and retain the overlap needed for split markers. */
    enum { read_size = 65536 };
    char buf[read_size + sizeof(marker) - 1];
    size_t tail = 0, n;
    bool found = false;
    while ((n = fread(buf + tail, 1, read_size, f)) > 0) {
        if (found) continue;
        n += tail;
        size_t i = 0;
        while (i + sizeof(marker) - 1 <= n) {
            size_t starts = n - i - (sizeof(marker) - 2);
            const char *first = memchr(buf + i, marker[0], starts);
            if (!first) break;
            i = (size_t)(first - buf);
            size_t window = n - i - (sizeof(marker) - 2);
            if (window > 64) window = 64;
            /* Sparse candidates need one comparison. Dense candidates use
             * the library search instead of comparing every byte. Normalize
             * NULs to newlines, which cannot join or occur in this marker. */
            if (memchr(buf + i + 1, marker[0], window - 1)) {
                phase_log_normalize(buf + i, n - i);
                buf[n] = '\0';
                found = strstr(buf + i, marker) != NULL;
                break;
            }
            if (memcmp(buf + i, marker, sizeof(marker) - 1) == 0) {
                found = true;
                break;
            }
            i += window;
        }
        /* Keep a partial marker across read boundaries, without joining
         * nonadjacent bytes or treating embedded NULs as end-of-response. */
        tail = n < sizeof(marker) - 2 ? n : sizeof(marker) - 2;
        memmove(buf, buf + n - tail, tail);
    }
    bool read_failed = ferror(f) != 0;
    int status = pclose(f);
    if (read_failed || status != 0) {
        fprintf(stderr, "bench-sync: explorer response rejected (read_error=%d status=%d)\n",
                read_failed, status);
        return false;
    }
    return found;
}

static int explorer_page_size(const char *path)
{
    char buf[32];
    char cmd[256];
    snprintf(cmd, sizeof(cmd),
        "curl -q -sk --fail --noproxy '*' --max-time 2 -o /dev/null -w '%%{size_download}' "
        "'https://127.0.0.1:%d%s' 2>/dev/null",
        HTTPSPORT, path);
    /* Curl counts the complete body without piping it through another shell
     * and wc. HTTP errors and failed transfers cannot supply a page size;
     * run_cmd rejects their counters along with their nonzero exit status. */
    run_cmd(cmd, buf, sizeof(buf));
    return atoi(buf);
}

static void startup_progress(const char *logfile, double t0,
                             double observed, double *next_progress)
{
    if (observed < *next_progress) return;
    char line[256] = "";
    startup_log_tail(logfile, line, sizeof(line));
    char *nl = strchr(line, '\n');
    if (nl) *nl = '\0';
    printf("  [%.0fs] %s\n", observed - t0, line);
    *next_progress = now_sec() + 10.0;
}

static bool startup_pause(double deadline)
{
    double sleep_start = now_sec();
    double remaining = deadline - sleep_start;
    if (remaining <= 0) return true;
    double wake_at = sleep_start + (remaining < 0.5 ? remaining : 0.5);
    do {
        unsigned int delay_us = remaining < 0.5 ?
            (unsigned int)(remaining * 1000000.0) : 500000;
        if (usleep(delay_us > 0 ? delay_us : 1) == 0) return true;
        if (errno != EINTR) {
            perror("bench-sync: sleep during startup");
            return false;
        }
        remaining = wake_at - now_sec();
    } while (remaining > 0);
    return true;
}

static bool startup_child_alive(const char *logfile)
{
    int st;
    pid_t waited;
    do {
        waited = waitpid(g_child, &st, WNOHANG);
    } while (waited < 0 && errno == EINTR);
    if (waited == 0) return true;
    fprintf(stderr, "ERROR: Node died during startup\n");
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "tail -10 '%s'", logfile);
    system(cmd);
    g_child = 0;
    return false;
}

/* This benchmark launches the node without explicit RPC credentials, so its
 * private datadir must contain the node-owned cookie-mode token. rpc_call()
 * passes that token to curl through a shell command; refuse every byte outside
 * the exact producer format before it can acquire shell syntax. */
static bool benchmark_cookie_valid(const char *cookie, size_t cookie_len)
{
    static const char prefix[] = "__cookie__:";
    if (cookie_len != sizeof(prefix) - 1 + 32 ||
        memcmp(cookie, prefix, sizeof(prefix) - 1) != 0)
        return false;
    const char *secret = cookie + sizeof(prefix) - 1;
    for (size_t i = 0; i < 32; i++) {
        unsigned char byte = (unsigned char)secret[i];
        if (!((byte >= '0' && byte <= '9') ||
              (byte >= 'a' && byte <= 'f')))
            return false;
    }
    return true;
}

static bool read_cookie(const char *cookie_path, double deadline,
                        char *cookie, size_t cookie_size)
{
    FILE *f = fopen(cookie_path, "r");
    if (!f) {
        perror("bench-sync: open RPC cookie");
        return false;
    }
    size_t n = fread(cookie, 1, cookie_size - 1, f);
    bool oversized = fgetc(f) != EOF;
    bool read_failed = ferror(f) != 0;
    fclose(f);
    if (now_sec() > deadline) {
        fprintf(stderr, "bench-sync: RPC cookie read exceeded startup budget (300s timeout)\n");
        cookie[0] = '\0';
        return false;
    }
    cookie[n] = '\0';
    if (n > 0 && cookie[n - 1] == '\n')
        cookie[--n] = '\0';
    bool malformed = n > 0 && !benchmark_cookie_valid(cookie, n);
    if (oversized || read_failed || cookie[0] == '\0' || malformed) {
        fprintf(stderr, "bench-sync: RPC cookie rejected (oversized=%d read_error=%d empty=%d malformed=%d)\n",
                oversized, read_failed, cookie[0] == '\0', malformed);
        cookie[0] = '\0';
        return false;
    }
    return true;
}

/* Wait for RPC startup independently of the phase-observation loop. */
static bool wait_for_cookie(const char *cookie_path, const char *logfile, double t0,
                            char *cookie, size_t cookie_size)
{
    printf("Waiting for node startup (file sync + block scan)...\n");
    const double startup_start = now_sec();
    const double deadline = startup_start + 300.0;
    double next_progress = startup_start + 10.0;
    bool cookie_ready = false;
    for (;;) {
        bool readable = access(cookie_path, R_OK) == 0;
        double observed = now_sec();
        /* Attribute readiness to the completed observation. A delayed wake
         * or filesystem lookup cannot turn a late cookie into on-time startup.
         * Keep the existing inclusive boundary at exactly 300 seconds. */
        if (readable && observed <= deadline) {
            cookie_ready = true;
            break;
        }
        if (observed >= deadline) break;
        startup_progress(logfile, t0, observed, &next_progress);
        /* Interrupted sleeps do not consume a full poll interval, and log
         * observation consumes real time. Charge both to the same deadline. */
        if (!startup_pause(deadline) || !startup_child_alive(logfile))
            return false;
    }
    if (!cookie_ready) {
        fprintf(stderr, "ERROR: RPC cookie not observed within startup budget (300s timeout)\n");
        char cmd[512];
        snprintf(cmd, sizeof(cmd), "tail -10 '%s'", logfile);
        system(cmd);
        return false;
    }
    return read_cookie(cookie_path, deadline, cookie, cookie_size);
}

static bool benchmark_paths(char *datadir, size_t datadir_size,
                            char *binary, size_t binary_size,
                            char *logfile, size_t logfile_size)
{
    const char *bench_home = getenv("HOME");
    if (!bench_home || !bench_home[0]) {
        fprintf(stderr, "bench-sync: HOME is required for an isolated datadir\n");
        return false;
    }
    time_t t = platform_time_wall_time_t();
    struct tm *tm = localtime(&t);
    if (!tm) {
        perror("bench-sync: format datadir timestamp");
        return false;
    }
    int n = snprintf(datadir, datadir_size,
        "%s/.zclassic-c23-bench-%04d%02d%02d-%02d%02d%02d-XXXXXX",
        bench_home, tm->tm_year + 1900, tm->tm_mon + 1, tm->tm_mday,
        tm->tm_hour, tm->tm_min, tm->tm_sec);
    if (n < 0 || (size_t)n >= datadir_size) {
        fprintf(stderr, "bench-sync: datadir path is too long\n");
        return false;
    }
    if (access("build/bin/zclassic23", X_OK) == 0)
        snprintf(binary, binary_size, "build/bin/zclassic23");
    else
        snprintf(binary, binary_size, "%s/zclassic23/build/bin/zclassic23", bench_home);
    if (access(binary, X_OK) != 0) {
        fprintf(stderr, "ERROR: Binary not found at %s\n", binary);
        return false;
    }
    if (!mkdtemp(datadir)) {
        perror("bench-sync: create fresh datadir");
        return false;
    }
    snprintf(logfile, logfile_size, "%s/node.log", datadir);
    return true;
}

static void benchmark_copy_ssl(const char *datadir)
{
    const char *bench_home = getenv("HOME");
    char src[512], dst[512], ssldir[512];
    snprintf(ssldir, sizeof(ssldir), "%s/ssl", datadir);
    mkdir(ssldir, 0755);
    snprintf(src, sizeof(src), "%s/.zclassic-c23/ssl/fullchain.pem", bench_home);
    snprintf(dst, sizeof(dst), "%s/ssl/fullchain.pem", datadir);
    if (access(src, R_OK) != 0) return;
    char cp[1024];
    snprintf(cp, sizeof(cp), "cp '%s' '%s'", src, dst);
    system(cp);
    snprintf(src, sizeof(src), "%s/.zclassic-c23/ssl/privkey.pem", bench_home);
    snprintf(dst, sizeof(dst), "%s/ssl/privkey.pem", datadir);
    snprintf(cp, sizeof(cp), "cp '%s' '%s'", src, dst);
    system(cp);
}

static bool benchmark_spawn(const char *binary, const char *datadir,
                            const char *logfile)
{
    g_child = fork();
    if (g_child == 0) {
        FILE *log = fopen(logfile, "w");
        if (log) {
            dup2(fileno(log), STDOUT_FILENO);
            dup2(fileno(log), STDERR_FILENO);
            fclose(log);
        }
        char dd[300], pp[32], rp[32], hp[32];
        snprintf(dd, sizeof(dd), "-datadir=%s", datadir);
        snprintf(pp, sizeof(pp), "-port=%d", PORT);
        snprintf(rp, sizeof(rp), "-rpcport=%d", RPCPORT);
        snprintf(hp, sizeof(hp), "-httpsport=%d", HTTPSPORT);
        execlp(binary, "zclassic23", dd, pp, rp, hp,
            "-connect=127.0.0.1:8033", "-listen=0", "-txindex",
            "-showmetrics=0", (char *)NULL);
        _exit(127);
    }
    if (g_child < 0) {
        perror("fork");
        return false;
    }
    atexit(cleanup);
    return true;
}

static void benchmark_results(double t_filesync, double t_filesync_done,
                              double t_fc, double t_snap_start,
                              double t_snap_end, double t_tip,
                              double t_explorer, double t_done)
{
    printf("\n================================================================\n");
    printf("  RESULTS\n");
    printf("================================================================\n\n");
    if (t_filesync > 0 && t_filesync_done > 0)
        printf("  File sync:           %5.1fs  (%.1fs download)\n",
               t_filesync_done, t_filesync_done - t_filesync);
    if (t_fc > 0) printf("  FlyClient + MMB:     %5.1fs\n", t_fc);
    if (t_snap_start > 0 && t_snap_end > 0)
        printf("  SHA3 snapshot:       %5.1fs  (%.1fs transfer + verify)\n",
               t_snap_end, t_snap_end - t_snap_start);
    if (t_tip > 0) printf("  Synced to tip:       %5.1fs\n", t_tip);
    if (t_explorer > 0) printf("  Explorer serving:    %5.1fs\n", t_explorer);
    if (t_done > 0) printf("  Total cold->live:    %5.1fs\n", t_done);
}

static void benchmark_pages(double t_explorer, double t_done)
{
    if (t_explorer <= 0 || t_done <= 0) {
        printf("\n  Explorer Pages: not probed (benchmark did not complete)\n");
        return;
    }
    static const char *const paths[] = {
        "/explorer", "/explorer/factoids", "/explorer/hodl", "/explorer/stats"
    };
    printf("\n  Explorer Pages:\n");
    for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
        int size = explorer_page_size(paths[i]);
        printf("    %-18s %d bytes %s\n", paths[i], size,
               size > 1000 ? "OK" : "EMPTY");
    }
}

static bool benchmark_progress_output(void)
{
    if (setvbuf(stdout, NULL, _IOLBF, 0) == 0) return true;
    fprintf(stderr, "bench-sync: cannot configure progress output\n");
    return false;
}

static void benchmark_validation(const char *cookie, char *rpc_buf,
                                 size_t rpc_buf_size)
{
    if (!rpc_call(cookie, "validationstatus", rpc_buf, (int)rpc_buf_size))
        return;
    char state[64] = "";
    json_get_str(rpc_buf, "state", state, sizeof(state));
    long height = json_get_int(rpc_buf, "verified_height");
    long proofs = json_get_int(rpc_buf, "proofs_verified");
    printf("\n  Background validation: %s (height %ld, %ld proofs)\n",
           state, height, proofs);
}

static int benchmark_outcome(double t_done)
{
    if (t_done > 0) return 0;
    fprintf(stderr,
            "bench-sync: incomplete within %ds; phase observations are partial results\n",
            TIMEOUT);
    return 1;
}

int main(void)
{
    /* Supervisors and redirected logs need each progress line during IBD,
     * even when stdout is not a terminal. Configure before the first write. */
    if (!benchmark_progress_output()) return 1;

    char datadir[256];
    char binary[256];
    char logfile[300];
    if (!benchmark_paths(datadir, sizeof(datadir), binary, sizeof(binary),
                         logfile, sizeof(logfile))) return 1;
    benchmark_copy_ssl(datadir);

    printf("\n");
    printf("================================================================\n");
    printf("  Z23 Cold-Start Benchmark\n");
    printf("  FlyClient + MMB + SHA3 Snapshot -> Block Explorer\n");
    printf("================================================================\n\n");
    printf("Binary:  %s\n", binary);
    printf("Datadir: %s\n", datadir);
    printf("Ports:   P2P=%d RPC=%d HTTPS=%d\n\n", PORT, RPCPORT, HTTPSPORT);

    double t0 = now_sec();

    if (!benchmark_spawn(binary, datadir, logfile)) return 1;

    printf("Started PID=%d\n\n", g_child);

    /* Wait for RPC cookie (may take a while during block file scan) */
    char cookie_path[300];
    snprintf(cookie_path, sizeof(cookie_path), "%s/.cookie", datadir);
    char cookie[256] = "";
    if (!wait_for_cookie(cookie_path, logfile, t0, cookie, sizeof(cookie))) return 1;

    /* Phase timestamps */
    double t_fc = 0, t_snap_start = 0, t_snap_end = 0;
    double t_filesync = 0, t_filesync_done = 0;
    double t_tip = 0, t_explorer = 0, t_done = 0;
    double tip_stable_since = 0;
    char last_state[64] = "";
    char rpc_buf[4096];
    struct phase_log phases = {0};

    printf("Phase                Time     Details\n");
    printf("-----------------------------------------------------------\n");

    while (1) {
        double elapsed = now_sec() - t0;
        if (elapsed >= TIMEOUT) {
            printf("\nTIMEOUT after %ds\n", TIMEOUT);
            break;
        }

        /* Check child alive */
        int status;
        pid_t waited;
        /* An interrupted observation must not discard a running IBD trial.
         * Retry immediately, as during startup, without another poll sleep. */
        do {
            waited = waitpid(g_child, &status, WNOHANG);
        } while (waited < 0 && errno == EINTR);
        if (waited != 0) {
            if (waited < 0)
                perror("bench-sync: observe node during IBD");
            else
                printf("\nERROR: Node died (status %d)\n", status);
            char cmd[512];
            snprintf(cmd, sizeof(cmd), "tail -20 '%s'", logfile);
            system(cmd);
            g_child = 0;
            return 1;
        }

        /* Get sync state */
        char state[64] = "unknown";
        long height = -1;
        bool state_observed = rpc_call(cookie, "syncstate", rpc_buf, sizeof(rpc_buf)) &&
            json_get_str(rpc_buf, "state", state, sizeof(state));
        /* Timestamp the observation after it completes. Later height/log
         * probes must neither backdate nor delay the observed tip time. */
        double state_elapsed = now_sec() - t0;
        if (strcmp(state, last_state) != 0) {
            /* Height is displayed only on a state transition (including
             * first arrival at tip), so stable IBD polls need no height RPC. */
            /* A failed state observation needs no second RPC to the same
             * unavailable endpoint. Keep height unavailable until a valid
             * state transition can use it. */
            if (state_observed && state_elapsed <= TIMEOUT &&
                rpc_call(cookie, "getblockcount", rpc_buf, sizeof(rpc_buf)))
                height = json_get_int(rpc_buf, "result");
            printf("  %-20s %5.1fs   state=%s height=%ld\n",
                   "", state_elapsed, state, height);
            strcpy(last_state, state);
        }

        /* An observer already in flight may exhaust the trial budget.
         * Retain its result, but do not start more work after expiry. */
        if (now_sec() - t0 <= TIMEOUT &&
            (t_filesync == 0 || t_filesync_done == 0 || t_fc == 0 ||
             t_snap_start == 0 || t_snap_end == 0)) {
            FILE *phase_file = fopen(logfile, "r");
            if (phase_file) {
                /* Batch filesystem reads, including the scanner's initial
                 * 4 KiB early-stop reads. The buffer must remain
                 * alive through fclose; refusal retains default stdio. */
                char phase_io_buffer[65536];
                /* Two early-stop blocks plus one bulk block need no
                 * read-ahead. Buffered seeks can reread bytes preceding an
                 * unaligned cursor on a reopened stream. Bound unbuffered
                 * reads to three per poll; buffer larger backlogs. */
                int phase_io_mode = _IOFBF;
                struct stat phase_stat;
                if (fstat(fileno(phase_file), &phase_stat) == 0 &&
                    phase_stat.st_dev == phases.device &&
                    phase_stat.st_ino == phases.inode &&
                    phase_stat.st_size >= phases.offset &&
                    phase_stat.st_size - phases.offset <= 8192 + 65536)
                    phase_io_mode = _IONBF;
                if (setvbuf(phase_file, phase_io_buffer, phase_io_mode,
                            sizeof(phase_io_buffer)) != 0)
                    fprintf(stderr, "bench-sync: phase log buffering unavailable\n");
                (void)phase_log_poll(phase_file, &phases);
                fclose(phase_file);
            } else {
                perror("bench-sync: open phase log");
            }
        }
        elapsed = now_sec() - t0;

        /* File sync */
        if (t_filesync == 0 && phases.seen[LOG_FILE_START]) {
            t_filesync = elapsed;
            printf("  File sync started   %5.1fs   downloading chain data\n", elapsed);
        }
        if (t_filesync_done == 0 && phases.seen[LOG_FILE_DONE]) {
            t_filesync_done = elapsed;
            printf("  File sync done      %5.1fs\n", elapsed);
        }

        /* FlyClient */
        if (t_fc == 0 && phases.seen[LOG_FLYCLIENT]) {
            t_fc = elapsed;
            printf("  FlyClient verified  %5.1fs   50/50 MMB samples (150-bit security)\n", elapsed);
        }

        /* Snapshot start */
        if (t_snap_start == 0 && phases.seen[LOG_SNAPSHOT_START]) {
            t_snap_start = elapsed;
            printf("  Snapshot started    %5.1fs   UTXO transfer began\n", elapsed);
        }

        /* Snapshot SHA3 verified */
        if (t_snap_end == 0 && phases.seen[LOG_SNAPSHOT_DONE]) {
            t_snap_end = elapsed;
            char line[256] = "";
            snapshot_log_summary(logfile, line, sizeof(line));
            printf("  SHA3 verified       %5.1fs   %s\n", elapsed, line);
        }

        /* Synced to tip */
        if (t_tip == 0 && strcmp(state, "at_tip") == 0) {
            t_tip = state_elapsed;
            printf("  SYNCED TO TIP       %5.1fs   height=%ld\n", t_tip, height);
        }
        /* Keep first arrival as a milestone, but require consecutive at-tip
         * observations for the grace period. A failed RPC leaves state
         * unknown and breaks the interval just like renewed synchronization. */
        if (strcmp(state, "at_tip") != 0)
            tip_stable_since = 0;
        else if (tip_stable_since == 0)
            tip_stable_since = state_elapsed;

        /* Probe readiness on current tip observations. A historical tip must
         * not keep fetching pages during renewed IBD or missing state RPCs. */
        if (t_explorer == 0 && strcmp(state, "at_tip") == 0 &&
            now_sec() - t0 <= TIMEOUT && explorer_responding()) {
            t_explorer = now_sec() - t0;
            printf("  Explorer live       %5.1fs   HTTPS port %d\n", t_explorer, HTTPSPORT);
        }

        /* Done: at tip + explorer working */
        elapsed = now_sec() - t0;
        /* A poll can cross the deadline during RPC or explorer observation.
         * Retain its measurements, but never accept it as an on-time run. */
        if (elapsed > TIMEOUT) {
            printf("\nTIMEOUT after %ds\n", TIMEOUT);
            break;
        }
        /* The latest tip observation must cover the grace interval; time
         * spent waiting for unrelated observers cannot establish that. */
        if (tip_stable_since > 0 && t_explorer > 0 && state_elapsed - tip_stable_since > 5) {
            t_done = elapsed;
            printf("  Fully operational   %5.1fs\n", elapsed);
            break;
        }

        /* 2 second poll. Signals must not turn observation into a busy loop
         * that competes with the node. Charge interruption handling and
         * scheduling delays to the same monotonic wake deadline. */
        double remaining = TIMEOUT - elapsed;
        /* The final interval must not add two seconds to an expired trial.
         * Keep the usual cadence when the full interval still fits. */
        double pause = remaining < 2.0 ? remaining : 2.0;
        double wake_at = now_sec() + pause;
        struct timespec delay = {
            (time_t)pause, (long)((pause - (time_t)pause) * 1000000000.0)
        };
        while (nanosleep(&delay, &delay) != 0) {
            if (errno != EINTR) {
                perror("bench-sync: sleep between IBD observations");
                return 1;
            }
            pause = wake_at - now_sec();
            if (pause <= 0) break;
            delay.tv_sec = (time_t)pause;
            delay.tv_nsec = (long)((pause - (time_t)pause) * 1000000000.0);
        }
    }

    benchmark_results(t_filesync, t_filesync_done, t_fc, t_snap_start,
                      t_snap_end, t_tip, t_explorer, t_done);

    /* Test explorer pages */
    /* A historical readiness observation does not make an incomplete run
     * worth four more page fetches (up to eight seconds of HTTP waits).
     * Keep these diagnostics for completed trials; validation status below
     * remains independently observable even when the benchmark times out. */
    benchmark_pages(t_explorer, t_done);

    /* Validation status */
    benchmark_validation(cookie, rpc_buf, sizeof(rpc_buf));

    printf("\n  Datadir: %s\n", datadir);
    printf("  Log:     %s\n\n", logfile);

    return benchmark_outcome(t_done);
}

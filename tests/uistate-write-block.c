// Test-only ui.json barriers hold inside the owned temp's first write and after the publication rename.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Fixed wait so a driver that never releases cannot hang the child forever.
#define RELEASE_WAIT_MS 15000
// Short prefix keeps the temp nonempty and incomplete for the killed proof.
#define PREFIX_LEN 16

static atomic_int held = 0;
static atomic_int rename_held = 0;
static atomic_int in_rename_hook = 0;

// Sample input: /proc/self/fd/7 reads /run/.../flea/ui.json.12345.tmp for the owned child.
static int target_matches(const char *target, pid_t self) {
    char expect[64];
    snprintf(expect, sizeof expect, "ui.json.%d.tmp", (int)self);
    size_t tl = strlen(target);
    size_t el = strlen(expect);
    if (tl >= el && strcmp(target + tl - el, expect) == 0)
        return 1;
    // Explicit mutation mode only: the truncated ui.json itself, never a backup.
    const char *allow = getenv("FLEA_TEST_UIS_ALLOW_DIRECT");
    if (allow && strcmp(allow, "1") == 0) {
        if (tl >= 8 && strcmp(target + tl - 8, "/ui.json") == 0)
            return 1;
    }
    return 0;
}

static void publish_entered(int fd, const char *target) {
    const char *path = getenv("FLEA_TEST_UIS_ENTERED");
    if (!path || !path[0])
        return;
    // Atomic publish: existence means ready, so complete bytes must land via rename.
    char sib[PATH_MAX + 64];
    int sl = snprintf(sib, sizeof sib, "%s.%d.part", path, (int)getpid());
    if (sl <= 0 || sl >= (int)sizeof sib)
        return;
    int out = open(sib, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (out < 0)
        return;
    char line[PATH_MAX + 64];
    int len = snprintf(line, sizeof line, "%d %d %s\n", (int)getpid(), fd, target);
    ssize_t (*real_write)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
    int ok = 0;
    // A truncated line is a malformed receipt, so length inside the buffer is checked first.
    if (len > 0 && len < (int)sizeof line && real_write && real_write(out, line, (size_t)len) == len)
        ok = 1;
    if (close(out) != 0)
        ok = 0;
    if (ok) {
        if (rename(sib, path) != 0) {
            int e = errno;
            unlink(sib);
            // The driver fails closed on the missing receipt; this names the publication failure.
            char msg[PATH_MAX + 128];
            int ml = snprintf(msg, sizeof msg, "flea-test: receipt publish %s failed (%s)\n", path, strerror(e));
            if (ml > 0 && real_write) {
                if (ml >= (int)sizeof msg)
                    ml = (int)sizeof msg - 1;
                real_write(STDERR_FILENO, msg, (size_t)ml);
            }
        }
    } else {
        unlink(sib);
    }
}

static void wait_for_path(const char *path) {
    // Poll for the release file; the driver SIGKILLs first in the killed proofs.
    for (int i = 0; i < RELEASE_WAIT_MS; i++) {
        if (access(path, F_OK) == 0)
            return;
        usleep(1000);
    }
}

static void wait_for_release(void) {
    const char *path = getenv("FLEA_TEST_UIS_RELEASE");
    if (!path || !path[0])
        return;
    wait_for_path(path);
}

ssize_t write(int fd, const void *buf, size_t count) {
    ssize_t (*real_write)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
    const char *entered = getenv("FLEA_TEST_UIS_ENTERED");
    const char *release = getenv("FLEA_TEST_UIS_RELEASE");
    if (real_write && entered && entered[0] && release && release[0] && atomic_load(&held) == 0) {
        char link[64];
        char target[PATH_MAX + 1];
        snprintf(link, sizeof link, "/proc/self/fd/%d", fd);
        ssize_t n = readlink(link, target, sizeof target - 1);
        if (n > 0) {
            target[n] = '\0';
            if (target_matches(target, getpid())) {
                if (atomic_exchange(&held, 1) == 0) {
                    // Forward only the prefix so the temp stays nonempty and incomplete.
                    size_t prefix = count > PREFIX_LEN ? PREFIX_LEN : (count > 1 ? 1 : count);
                    ssize_t w = real_write(fd, buf, prefix);
                    publish_entered(fd, target);
                    wait_for_release();
                    return w;
                }
            }
        }
    }
    return real_write(fd, buf, count);
}

// The rename barrier matches only the publication rename: old name is a tmp, new leaf is ui.json.
static int rename_target_matches(const char *oldpath, const char *newpath) {
    if (!oldpath || !newpath)
        return 0;
    size_t ol = strlen(oldpath);
    if (ol < 4 || strcmp(oldpath + ol - 4, ".tmp") != 0)
        return 0;
    const char *leaf = strrchr(newpath, '/');
    leaf = leaf ? leaf + 1 : newpath;
    return strcmp(leaf, "ui.json") == 0;
}

// Sample input: /run/.../flea/ui.json for the owned child after its own publication rename.
static void publish_renamed(const char *newpath) {
    const char *path = getenv("FLEA_TEST_UIS_RENAME_ENTERED");
    if (!path || !path[0])
        return;
    // Atomic publish: existence means the rename landed, so bytes arrive via rename.
    char sib[PATH_MAX + 64];
    int sl = snprintf(sib, sizeof sib, "%s.%d.part", path, (int)getpid());
    if (sl <= 0 || sl >= (int)sizeof sib)
        return;
    int out = open(sib, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (out < 0)
        return;
    char line[PATH_MAX + 64];
    int len = snprintf(line, sizeof line, "%d rename %s\n", (int)getpid(), newpath);
    ssize_t (*real_write)(int, const void *, size_t) = dlsym(RTLD_NEXT, "write");
    int ok = 0;
    // A truncated line is a malformed receipt, so length inside the buffer is checked first.
    if (len > 0 && len < (int)sizeof line && real_write && real_write(out, line, (size_t)len) == len)
        ok = 1;
    if (close(out) != 0)
        ok = 0;
    if (ok) {
        if (rename(sib, path) != 0) {
            unlink(sib);
        }
    } else {
        unlink(sib);
    }
}

// The rename runs first and the hold after it, so a kill in the hold lands past the rename.
static int maybe_hold_after_rename(const char *oldpath, const char *newpath) {
    const char *entered = getenv("FLEA_TEST_UIS_RENAME_ENTERED");
    const char *release = getenv("FLEA_TEST_UIS_RENAME_RELEASE");
    if (!entered || !entered[0] || !release || !release[0])
        return 0;
    if (atomic_load(&in_rename_hook))
        return 0;
    if (!rename_target_matches(oldpath, newpath))
        return 0;
    if (atomic_exchange(&rename_held, 1) != 0)
        return 0;
    return 1;
}

static void hold_after_rename(const char *newpath) {
    publish_renamed(newpath);
    const char *release = getenv("FLEA_TEST_UIS_RENAME_RELEASE");
    if (release && release[0])
        wait_for_path(release);
}

int rename(const char *oldpath, const char *newpath) {
    int (*real_rename)(const char *, const char *) = dlsym(RTLD_NEXT, "rename");
    if (!real_rename)
        return -1;
    int hold = maybe_hold_after_rename(oldpath, newpath);
    if (atomic_exchange(&in_rename_hook, 1) != 0)
        hold = 0;
    int rc = real_rename(oldpath, newpath);
    atomic_store(&in_rename_hook, 0);
    if (hold && rc == 0)
        hold_after_rename(newpath);
    return rc;
}

int renameat(int olddirfd, const char *oldpath, int newdirfd, const char *newpath) {
    int (*real_renameat)(int, const char *, int, const char *) = dlsym(RTLD_NEXT, "renameat");
    if (!real_renameat)
        return -1;
    int hold = maybe_hold_after_rename(oldpath, newpath);
    if (atomic_exchange(&in_rename_hook, 1) != 0)
        hold = 0;
    int rc = real_renameat(olddirfd, oldpath, newdirfd, newpath);
    atomic_store(&in_rename_hook, 0);
    if (hold && rc == 0)
        hold_after_rename(newpath);
    return rc;
}

int renameat2(int olddirfd, const char *oldpath, int newdirfd, const char *newpath, unsigned int flags) {
    int (*real_renameat2)(int, const char *, int, const char *, unsigned int) = dlsym(RTLD_NEXT, "renameat2");
    if (!real_renameat2)
        return -1;
    int hold = maybe_hold_after_rename(oldpath, newpath);
    if (atomic_exchange(&in_rename_hook, 1) != 0)
        hold = 0;
    int rc = real_renameat2(olddirfd, oldpath, newdirfd, newpath, flags);
    atomic_store(&in_rename_hook, 0);
    if (hold && rc == 0)
        hold_after_rename(newpath);
    return rc;
}

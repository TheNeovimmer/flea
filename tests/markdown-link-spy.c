// Observe Qt's native URL dispatch without invoking a browser or requiring offscreen platform services.
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

bool markdown_desktop_open(const void *url) __asm__("_ZN16QDesktopServices7openUrlERK4QUrl");
bool markdown_desktop_open(const void *url) {
    (void)url;
    const char *path = getenv("FLEA_MARKDOWN_OPEN_LOG");
    if (!path) return false;
    FILE *log = fopen(path, "a");
    if (!log) return false;
    fputs("called\n", log);
    return fclose(log) == 0;
}

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static void shim_log(const char *event) {
    const char *path = getenv("VIEWER_SHIM_LOG");
    if (path == NULL) {
        return;
    }
    FILE *fh = fopen(path, "a");
    if (fh == NULL) {
        return;
    }
    fprintf(fh, "%ld pid=%d %s\n", (long)time(NULL), (int)getpid(), event);
    fclose(fh);
}

static void swallow_activate_ignoring_other_apps(id self, SEL cmd, BOOL flag) {
    shim_log("swallowed activateIgnoringOtherApps:");
}

static void swallow_activate(id self, SEL cmd) {
    shim_log("swallowed activate");
}

static void replace_instance_method(Class cls, SEL selector, IMP replacement, const char *name) {
    Method method = class_getInstanceMethod(cls, selector);
    if (method == NULL) {
        char line[128];
        snprintf(line, sizeof(line), "MISSING %s", name);
        shim_log(line);
        return;
    }
    method_setImplementation(method, replacement);
    char line[128];
    snprintf(line, sizeof(line), "installed %s", name);
    shim_log(line);
}

__attribute__((constructor)) static void viewer_shim_install(void) {
    replace_instance_method([NSApplication class], @selector(activateIgnoringOtherApps:),
                            (IMP)swallow_activate_ignoring_other_apps, "activateIgnoringOtherApps:");
    replace_instance_method([NSApplication class], @selector(activate),
                            (IMP)swallow_activate, "activate");
}

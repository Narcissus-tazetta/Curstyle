#include "CCursorBridge.h"

#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <string.h>

CSSymbols CSResolveSymbols(void) {
    CSSymbols s;
    s.mainConnectionID = (CSMainConnectionIDFn)dlsym(RTLD_DEFAULT, "CGSMainConnectionID");
    s.cursorNameForSystemCursor =
        (CSCursorNameForSystemCursorFn)dlsym(RTLD_DEFAULT, "CGSCursorNameForSystemCursor");
    s.registerCursorWithImages =
        (CSRegisterCursorWithImagesFn)dlsym(RTLD_DEFAULT, "CGSRegisterCursorWithImages");
    s.copyRegisteredCursorImages =
        (CSCopyRegisteredCursorImagesFn)dlsym(RTLD_DEFAULT, "CGSCopyRegisteredCursorImages");
    s.removeRegisteredCursor =
        (CSRemoveRegisteredCursorFn)dlsym(RTLD_DEFAULT, "CGSRemoveRegisteredCursor");
    s.coreCursorUnregisterAll =
        (CSCoreCursorUnregisterAllFn)dlsym(RTLD_DEFAULT, "CoreCursorUnregisterAll");
    s.coreCursorCopyImages = (CSCoreCursorCopyImagesFn)dlsym(RTLD_DEFAULT, "CoreCursorCopyImages");
    s.getCursorScale = (CSGetCursorScaleFn)dlsym(RTLD_DEFAULT, "CGSGetCursorScale");
    s.coreCursorSet = (CSCoreCursorSetFn)dlsym(RTLD_DEFAULT, "CoreCursorSet");
    return s;
}

const char* CSImagePathForSymbol(const char* symbol) {
    void* p = dlsym(RTLD_DEFAULT, symbol);
    if (p == NULL) return NULL;
    Dl_info info;
    if (dladdr(p, &info) == 0) return NULL;
    return info.dli_fname;
}

int CSScanCStrings(const char* imagePath, const char* prefix, CSStringVisitor visitor,
                   void* context) {
    size_t prefixLen = strlen(prefix);
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* name = _dyld_get_image_name(i);
        if (strcmp(name, imagePath) != 0) continue;
        const struct mach_header_64* header =
            (const struct mach_header_64*)_dyld_get_image_header(i);
        unsigned long size = 0;
        const char* data = (const char*)getsectiondata(header, "__TEXT", "__cstring", &size);
        if (data == NULL) return -1;
        int found = 0;
        const char* end = data + size;
        for (const char* cur = data; cur < end; cur += strlen(cur) + 1) {
            if (strncmp(cur, prefix, prefixLen) == 0) {
                visitor(cur, context);
                found++;
            }
        }
        return found;
    }
    return -1;
}

CSAXFCursorUnregisterAllFn CSResolveAXFCursorUnregisterAll(void) {
    static const char* path =
        "/System/Library/PrivateFrameworks/AccessibilitySupport.framework/Versions/A/Frameworks/"
        "AccessibilityFoundation.framework/Versions/A/AccessibilityFoundation";
    void* handle = dlopen(path, RTLD_LAZY);
    if (handle == NULL) return NULL;
    return (CSAXFCursorUnregisterAllFn)dlsym(handle, "AXFCursorUnregisterAll");
}

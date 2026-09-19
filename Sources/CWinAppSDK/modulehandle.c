#if defined(_WIN32)

#include <windows.h>

HMODULE CWinAppSDKContainingModule(void) {
    static const char anchor = 0;
    HMODULE module = NULL;
    if (!GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            (LPCWSTR)&anchor,
            &module)) {
        return NULL;
    }
    return module;
}

#endif

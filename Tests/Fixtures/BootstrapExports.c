#include <windows.h>
#include <appmodel.h>

static void trace(const char *message, DWORD length) {
    DWORD written;
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), message, length, &written, NULL);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)instance;
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        const char message[] = "FIXTURE_LOADED\n";
        trace(message, sizeof(message) - 1);
    } else if (reason == DLL_PROCESS_DETACH) {
        const char message[] = "FIXTURE_UNLOADED\n";
        trace(message, sizeof(message) - 1);
    }
    return TRUE;
}

#ifndef OMIT_INITIALIZE
__declspec(dllexport) HRESULT WINAPI MddBootstrapInitialize2(
    UINT32 version,
    PCWSTR tag,
    PACKAGE_VERSION minimum,
    UINT32 options
) {
    (void)version;
    (void)tag;
    (void)minimum;
    (void)options;
    const char message[] = "FIXTURE_INITIALIZE\n";
    trace(message, sizeof(message) - 1);
    #ifdef FAIL_INITIALIZE
    return E_FAIL;
    #else
    return S_OK;
    #endif
}
#endif

#ifndef OMIT_SHUTDOWN
__declspec(dllexport) void WINAPI MddBootstrapShutdown(void) {
    const char message[] = "FIXTURE_SHUTDOWN\n";
    trace(message, sizeof(message) - 1);
}
#endif

#include <windows.h>
#include <appmodel.h>

static void trace(const char *message, DWORD length) {
    DWORD written;
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), message, length, &written, NULL);
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
    return S_OK;
}
#endif

#ifndef OMIT_SHUTDOWN
__declspec(dllexport) void WINAPI MddBootstrapShutdown(void) {
    const char message[] = "FIXTURE_SHUTDOWN\n";
    trace(message, sizeof(message) - 1);
}
#endif

import Foundation

#if os(Windows)
import WinAppSDK
import WinSDK

func write(_ message: String, to handle: FileHandle = .standardOutput) {
    handle.write(Data((message + "\n").utf8))
}

func run() throws {
    let initializer = try WindowsAppRuntimeInitializer()
    withExtendedLifetime(initializer) {
        write("BOOTSTRAP_PROBE_INITIALIZED")
    }
}

// Keep deliberately crashing baseline cases from opening a system error dialog.
SetErrorMode(UINT(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX))

do {
    try run()
    write("BOOTSTRAP_PROBE_SHUTDOWN")
} catch {
    write("BOOTSTRAP_PROBE_CAUGHT_ERROR")
    write("BOOTSTRAP_PROBE_ERROR: \(error.localizedDescription) [\(String(describing: error))]", to: .standardError)
    ExitProcess(1)
}
#else
fatalError("BootstrapProbe requires Windows")
#endif

#if os(Windows)

import Foundation
import WindowsFoundation
import WinSDK

struct InitializationOperations {
    var processHasIdentity: () -> Bool
    var executableURL: () throws -> URL
    var loadBootstrap: (URL) throws -> BootstrapLibrary
    var initializeWinRT: (ThreadingModel) -> HRESULT
    var uninitializeWinRT: () -> Void
    var setDpiAwareness: () -> HRESULT
    var installerExists: (URL) -> Bool
    var runInstaller: (URL) throws -> Int32
    var report: (String) -> Void

    static var live: Self {
        Self(
            processHasIdentity: {
                var length: UInt32 = 0
                return GetCurrentPackageFullName(&length, nil) != APPMODEL_ERROR_NO_PACKAGE
            },
            executableURL: { try BootstrapLibrary.moduleURL(nil) },
            loadBootstrap: { try BootstrapLibrary.load(executableDirectory: $0) },
            initializeWinRT: { model in
                let parameter = switch model {
                    case .single: RO_INIT_SINGLETHREADED
                    case .multi: RO_INIT_MULTITHREADED
                }
                return RoInitialize(parameter)
            },
            uninitializeWinRT: { RoUninitialize() },
            setDpiAwareness: { SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE) },
            installerExists: { FileManager.default.fileExists(atPath: $0.path) },
            runInstaller: { url in
                let process = Process()
                process.executableURL = url
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            },
            report: { print($0) }
        )
    }
}

func checkInitializationResult(_ result: HRESULT, operation: String) throws {
    do {
        try CHECKED(result)
    } catch {
        throw InitializationError.runtimeFailure(
            operation: operation, code: result, detail: String(describing: error)
        )
    }
}

final class RuntimeLifetime {
    private let operations: InitializationOperations
    private var library: BootstrapLibrary?
    private var initializedWinRT = false
    private var initializedBootstrap = false

    private init(operations: InitializationOperations) {
        self.operations = operations
    }

    static func initialized(
        threadingModel: ThreadingModel, operations: InitializationOperations
    ) throws -> RuntimeLifetime {
        let lifetime = RuntimeLifetime(operations: operations)
        var completed = false
        defer {
            if !completed { lifetime.close() }
        }

        let packaged = operations.processHasIdentity()
        let directory: URL?
        if packaged {
            directory = nil
        } else {
            let executableDirectory = try operations.executableURL().deletingLastPathComponent()
            directory = executableDirectory
            lifetime.library = try operations.loadBootstrap(executableDirectory)
        }

        try checkInitializationResult(operations.initializeWinRT(threadingModel), operation: "RoInitialize")
        lifetime.initializedWinRT = true
        try checkInitializationResult(operations.setDpiAwareness(), operation: "SetProcessDpiAwareness")

        if let library = lifetime.library, let directory {
            let installer = directory.appendingPathComponent("WindowsAppRuntimeInstaller.exe")
            let installerExists = operations.installerExists(installer)
            do {
                try library.initialize(!installerExists)
            } catch {
                guard installerExists else {
                    operations.report(
                        "Windows App Runtime not found on system, and no installer was present to install it "
                        + "(expected at '\(installer.lastPathComponent)')"
                    )
                    throw error
                }
                let exitCode = try operations.runInstaller(installer)
                guard exitCode == 0 else {
                    throw InitializationError.failedToInstallWindowsAppRuntime(exitCode: exitCode)
                }
                try library.initialize(false)
            }
            lifetime.initializedBootstrap = true
        }

        completed = true
        return lifetime
    }

    func close() {
        if initializedBootstrap {
            initializedBootstrap = false
            library?.shutdown()
        }
        library?.close()
        library = nil
        if initializedWinRT {
            initializedWinRT = false
            operations.uninitializeWinRT()
        }
    }

    deinit {
        close()
    }
}

#endif

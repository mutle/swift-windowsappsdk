#if os(Windows)

import CWinAppSDK
import Foundation
import WinSDK

final class BootstrapLibrary {
    private typealias InitializeFunction = @convention(c) (
        UInt32, PCWSTR?, PACKAGE_VERSION, MddBootstrapInitializeOptions
    ) -> HRESULT
    private typealias ShutdownFunction = @convention(c) () -> Void

    static let resourceDirectory = "swift-windowsappsdk_CWinAppSDK.bundle"
    static let dllName = "Microsoft.WindowsAppRuntime.Bootstrap.dll"
    #if arch(arm64)
    static let architecture = "arm64"
    #elseif arch(x86_64)
    static let architecture = "x86_64"
    #else
    #error("Unsupported Windows architecture")
    #endif

    let initialize: (_ showUIOnNoMatch: Bool) throws -> Void
    let shutdown: () -> Void
    private var unload: (() -> Void)?

    init(
        initialize: @escaping (Bool) throws -> Void,
        shutdown: @escaping () -> Void,
        unload: @escaping () -> Void
    ) {
        self.initialize = initialize
        self.shutdown = shutdown
        self.unload = unload
    }

    func close() {
        let release = unload
        unload = nil
        release?()
    }

    deinit {
        close()
    }

    static func candidateURLs(executableDirectory: URL, moduleDirectory: URL) -> [URL] {
        var seen = Set<String>()
        return [executableDirectory, moduleDirectory].compactMap { directory in
            let url = directory
                .appendingPathComponent(resourceDirectory)
                .appendingPathComponent("bin")
                .appendingPathComponent(architecture)
                .appendingPathComponent(dllName)
                .standardizedFileURL
            return seen.insert(url.path.lowercased()).inserted ? url : nil
        }
    }

    static func load(executableDirectory: URL) throws -> BootstrapLibrary {
        guard let module = CWinAppSDKContainingModule() else {
            let code = GetLastError()
            throw InitializationError.windowsAPI(
                operation: "GetModuleHandleExW", context: "CWinAppSDK", code: code
            )
        }
        let moduleDirectory = try moduleURL(module).deletingLastPathComponent()
        let candidates = candidateURLs(
            executableDirectory: executableDirectory, moduleDirectory: moduleDirectory
        )
        var missing: [String] = []
        for candidate in candidates {
            let path = candidate.path
            let (attributes, attributeError) = path.withCString(encodedAs: UTF16.self) {
                let attributes = GetFileAttributesW($0)
                return (attributes, attributes == INVALID_FILE_ATTRIBUTES ? GetLastError() : DWORD(0))
            }
            if attributes == INVALID_FILE_ATTRIBUTES {
                let code = attributeError
                if code == DWORD(ERROR_FILE_NOT_FOUND) || code == DWORD(ERROR_PATH_NOT_FOUND) {
                    missing.append("'\(path)' (Win32 error \(code))")
                    continue
                }
                throw InitializationError.windowsAPI(
                    operation: "GetFileAttributesW", context: path, code: code
                )
            }
            return try open(path: path)
        }
        throw InitializationError.bootstrapNotFound(architecture: architecture, attempts: missing)
    }

    private static func open(path: String) throws -> BootstrapLibrary {
        let (loaded, loadError) = path.withCString(encodedAs: UTF16.self) {
            let module = LoadLibraryW($0)
            return (module, module == nil ? GetLastError() : DWORD(0))
        }
        guard let module = loaded else {
            throw InitializationError.windowsAPI(operation: "LoadLibraryW", context: path, code: loadError)
        }
        var transferred = false
        defer {
            if !transferred { release(module, path: path) }
        }

        let (initializeSymbol, initializeError) = "MddBootstrapInitialize2".withCString {
            let address = GetProcAddress(module, $0)
            return (address, address == nil ? GetLastError() : DWORD(0))
        }
        guard let initializeAddress = initializeSymbol else {
            throw InitializationError.windowsAPI(
                operation: "GetProcAddress(MddBootstrapInitialize2)", context: path, code: initializeError
            )
        }
        let (shutdownSymbol, shutdownError) = "MddBootstrapShutdown".withCString {
            let address = GetProcAddress(module, $0)
            return (address, address == nil ? GetLastError() : DWORD(0))
        }
        guard let shutdownAddress = shutdownSymbol else {
            throw InitializationError.windowsAPI(
                operation: "GetProcAddress(MddBootstrapShutdown)", context: path, code: shutdownError
            )
        }
        let initialize = unsafeBitCast(initializeAddress, to: InitializeFunction.self)
        let shutdown = unsafeBitCast(shutdownAddress, to: ShutdownFunction.self)
        let library = BootstrapLibrary(
            initialize: { showUIOnNoMatch in
                try checkInitializationResult(
                    initialize(
                        UInt32(WINDOWSAPPSDK_RELEASE_MAJORMINOR),
                        WINDOWSAPPSDK_RELEASE_VERSION_TAG_SWIFT,
                        .init(),
                        MddBootstrapInitializeOptions(
                            showUIOnNoMatch
                                ? MddBootstrapInitializeOptions_OnNoMatch_ShowUI.rawValue
                                : MddBootstrapInitializeOptions_None.rawValue
                        )
                    ),
                    operation: "MddBootstrapInitialize2 (\(path))"
                )
            },
            shutdown: { shutdown() },
            unload: { release(module, path: path) }
        )
        transferred = true
        return library
    }

    private static func release(_ module: HMODULE, path: String) {
        guard FreeLibrary(module) else {
            let code = GetLastError()
            let error = InitializationError.windowsAPI(operation: "FreeLibrary", context: path, code: code)
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            return
        }
    }

    static func moduleURL(
        _ module: HMODULE?,
        query: (HMODULE?, UnsafeMutablePointer<WCHAR>?, DWORD) -> DWORD = { GetModuleFileNameW($0, $1, $2) },
        lastError: () -> DWORD = { GetLastError() }
    ) throws -> URL {
        var capacity = 260
        while capacity <= 32768 {
            var buffer = [WCHAR](repeating: 0, count: capacity)
            let (count, pathError) = buffer.withUnsafeMutableBufferPointer {
                let count = query(module, $0.baseAddress, DWORD(capacity))
                return (count, count == 0 ? lastError() : DWORD(0))
            }
            guard count != 0 else {
                throw InitializationError.windowsAPI(
                    operation: "GetModuleFileNameW", context: "executable or owning module", code: pathError
                )
            }
            if count < capacity {
                return URL(fileURLWithPath: String(decoding: buffer.prefix(Int(count)), as: UTF16.self))
            }
            if capacity == 32768 { break }
            capacity = min(capacity * 2, 32768)
        }
        throw InitializationError.windowsAPI(
            operation: "GetModuleFileNameW",
            context: "path exceeds the Windows Unicode path limit",
            code: DWORD(ERROR_INSUFFICIENT_BUFFER)
        )
    }
}

#endif

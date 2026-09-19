#if os(Windows)

import Foundation
import WinSDK

public enum ThreadingModel {
    case single
    case multi
}

enum InitializationError: LocalizedError {
    case failedToInstallWindowsAppRuntime(exitCode: Int32)
    case bootstrapNotFound(architecture: String, attempts: [String])
    case windowsAPI(operation: String, context: String, code: DWORD)
    case runtimeFailure(operation: String, code: HRESULT, detail: String)

    var errorDescription: String? {
        switch self {
            case .failedToInstallWindowsAppRuntime(let exitCode):
                return """
                    Failed to install Windows App Runtime (installer produced \
                    exit status \(exitCode))
                    """
            case .bootstrapNotFound(let architecture, let attempts):
                return "Windows App Runtime bootstrap DLL not found for \(architecture). "
                    + "Expected Swift 6.4 .bundle resources; attempted: " + attempts.joined(separator: "; ")
            case .windowsAPI(let operation, let context, let code):
                return "\(operation) failed for '\(context)' (Win32 error \(code)): \(Self.message(for: code))"
            case .runtimeFailure(let operation, let code, let detail):
                return "\(operation) failed (HRESULT 0x\(String(UInt32(bitPattern: code), radix: 16))): \(detail)"
        }
    }

    private static func message(for code: DWORD) -> String {
        let capacity = 2048
        var buffer = [WCHAR](repeating: 0, count: capacity)
        let count = FormatMessageW(
            DWORD(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS),
            nil, code, 0, &buffer, DWORD(capacity), nil
        )
        guard count > 0 else { return "No system message is available." }
        return String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// WindowsAppRuntimeInitializer is used to properly initialize the Windows App SDK runtime, along with the Windows Runtime.
/// The runtime is initalized for the lifetime of the object, and is deinitialized when the object is deallocated.
/// Example usage:
/// ```
/// public static func main() {
///        do {
///            try withExtendedLifetime(WindowsAppRuntimeInitializer()) {
///                initialization code here
///            }
///        }
///        catch {
///            fatalError("Failed to initialize WindowsAppRuntimeInitializer: \(error)")
///        }
///    }
/// ```
public class WindowsAppRuntimeInitializer {
    private let lifetime: RuntimeLifetime

    public init(threadingModel: ThreadingModel = .single) throws {
        lifetime = try RuntimeLifetime.initialized(threadingModel: threadingModel, operations: .live)
    }

    init(threadingModel: ThreadingModel, operations: InitializationOperations) throws {
        lifetime = try RuntimeLifetime.initialized(threadingModel: threadingModel, operations: operations)
    }
}

#endif

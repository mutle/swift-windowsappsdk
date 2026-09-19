#if os(Windows)

import Foundation
import WinSDK
import XCTest
@testable import WinAppSDK

final class RuntimeInitializationTests: XCTestCase {
    private enum FixtureError: Swift.Error { case expected }

    private final class Runtime {
        var events: [String] = []
        var packaged = false
        var executableError: Swift.Error?
        var loaderError: Swift.Error?
        var roResult: HRESULT = 0
        var dpiResult: HRESULT = 0
        var bootstrapResults: [HRESULT] = [0]
        var hasInstaller = false
        var installerError: Swift.Error?
        var installerExit: Int32 = 0

        var operations: InitializationOperations {
            InitializationOperations(
                processHasIdentity: {
                    self.events.append("identity")
                    return self.packaged
                },
                executableURL: {
                    self.events.append("executable")
                    if let error = self.executableError { throw error }
                    return URL(fileURLWithPath: #"C:\app\Probe.exe"#)
                },
                loadBootstrap: { directory in
                    self.events.append("load")
                    XCTAssertEqual(directory.lastPathComponent, "app")
                    if let error = self.loaderError { throw error }
                    return BootstrapLibrary(
                        initialize: { showUI in
                            self.events.append("initialize:\(showUI)")
                            guard !self.bootstrapResults.isEmpty else {
                                XCTFail("Unexpected extra bootstrap initialization.")
                                throw FixtureError.expected
                            }
                            try checkInitializationResult(
                                self.bootstrapResults.removeFirst(), operation: "fixture initialize"
                            )
                        },
                        shutdown: { self.events.append("shutdown") },
                        unload: { self.events.append("unload") }
                    )
                },
                initializeWinRT: { model in
                    self.events.append(model == .single ? "ro:single" : "ro:multi")
                    return self.roResult
                },
                uninitializeWinRT: { self.events.append("ro-uninitialize") },
                setDpiAwareness: {
                    self.events.append("dpi")
                    return self.dpiResult
                },
                installerExists: { url in
                    self.events.append("installer-exists")
                    XCTAssertEqual(url.lastPathComponent, "WindowsAppRuntimeInstaller.exe")
                    return self.hasInstaller
                },
                runInstaller: { _ in
                    self.events.append("installer")
                    if let error = self.installerError { throw error }
                    return self.installerExit
                },
                report: { message in
                    XCTAssertTrue(message.contains("WindowsAppRuntimeInstaller.exe"))
                    self.events.append("report")
                }
            )
        }
    }

    private let started = ["identity", "executable", "load", "ro:single", "dpi", "installer-exists"]
    private let failedHRESULT = HRESULT(bitPattern: 0x80004005)

    private func assertFailure(
        _ runtime: Runtime,
        events: [String],
        diagnostic: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try WindowsAppRuntimeInitializer(threadingModel: .single, operations: runtime.operations),
            file: file, line: line
        ) { error in
            if let diagnostic {
                XCTAssertTrue(error.localizedDescription.contains(diagnostic), file: file, line: line)
            }
        }
        XCTAssertEqual(runtime.events, events, file: file, line: line)
    }

    func testSuccessfulLifetimeAndSFalseAreBalanced() throws {
        for result in [HRESULT(0), HRESULT(1)] {
            let runtime = Runtime()
            runtime.roResult = result
            var initializer: WindowsAppRuntimeInitializer? = try .init(
                threadingModel: .single, operations: runtime.operations
            )
            withExtendedLifetime(initializer) {
                XCTAssertEqual(runtime.events, started + ["initialize:true"])
            }
            initializer = nil
            XCTAssertEqual(runtime.events, started + [
                "initialize:true", "shutdown", "unload", "ro-uninitialize",
            ])
        }
    }

    func testPackagedProcessDoesNotResolveOrLoadBootstrap() throws {
        let runtime = Runtime()
        runtime.packaged = true
        var initializer: WindowsAppRuntimeInitializer? = try .init(
            threadingModel: .multi, operations: runtime.operations
        )
        withExtendedLifetime(initializer) {
            XCTAssertEqual(runtime.events, ["identity", "ro:multi", "dpi"])
        }
        initializer = nil
        XCTAssertEqual(runtime.events, ["identity", "ro:multi", "dpi", "ro-uninitialize"])
    }

    func testExecutableAndLoaderFailuresCannotRunInstaller() {
        let noExecutable = Runtime()
        noExecutable.executableError = FixtureError.expected
        noExecutable.hasInstaller = true
        assertFailure(noExecutable, events: ["identity", "executable"])

        let noLibrary = Runtime()
        noLibrary.loaderError = FixtureError.expected
        noLibrary.hasInstaller = true
        assertFailure(noLibrary, events: ["identity", "executable", "load"])
    }

    func testFailedRoInitializeUnloadsWithoutRoUninitializeOrShutdown() {
        let runtime = Runtime()
        runtime.roResult = failedHRESULT
        assertFailure(
            runtime,
            events: ["identity", "executable", "load", "ro:single", "unload"],
            diagnostic: "RoInitialize"
        )
    }

    func testDpiFailureRollsBackWinRTAndModuleWithoutShutdown() {
        let runtime = Runtime()
        runtime.dpiResult = failedHRESULT
        assertFailure(
            runtime,
            events: ["identity", "executable", "load", "ro:single", "dpi", "unload", "ro-uninitialize"],
            diagnostic: "SetProcessDpiAwareness"
        )
    }

    func testBootstrapFailureWithoutInstallerRollsBackAndReports() {
        let runtime = Runtime()
        runtime.bootstrapResults = [failedHRESULT]
        assertFailure(runtime, events: started + [
            "initialize:true", "report", "unload", "ro-uninitialize",
        ])
    }

    func testInstallerLaunchFailureAndNonzeroExitRollBack() {
        let launchFailure = Runtime()
        launchFailure.hasInstaller = true
        launchFailure.bootstrapResults = [failedHRESULT]
        launchFailure.installerError = FixtureError.expected
        assertFailure(launchFailure, events: started + [
            "initialize:false", "installer", "unload", "ro-uninitialize",
        ])

        let nonzeroExit = Runtime()
        nonzeroExit.hasInstaller = true
        nonzeroExit.bootstrapResults = [failedHRESULT]
        nonzeroExit.installerExit = 23
        assertFailure(
            nonzeroExit,
            events: started + ["initialize:false", "installer", "unload", "ro-uninitialize"],
            diagnostic: "exit status 23"
        )
    }

    func testFailedRetryDoesNotShutdown() {
        let runtime = Runtime()
        runtime.hasInstaller = true
        runtime.bootstrapResults = [failedHRESULT, failedHRESULT]
        assertFailure(runtime, events: started + [
            "initialize:false", "installer", "initialize:false", "unload", "ro-uninitialize",
        ])
    }

    func testSuccessfulRetryShutsDownOnceAndCloseIsIdempotent() throws {
        let runtime = Runtime()
        runtime.hasInstaller = true
        runtime.bootstrapResults = [failedHRESULT, 0]
        let lifetime = try RuntimeLifetime.initialized(
            threadingModel: .single, operations: runtime.operations
        )
        XCTAssertEqual(runtime.events, started + ["initialize:false", "installer", "initialize:false"])
        lifetime.close()
        lifetime.close()
        XCTAssertEqual(runtime.events, started + [
            "initialize:false", "installer", "initialize:false", "shutdown", "unload", "ro-uninitialize",
        ])
    }

    func testExistingInstallerIsNotRunWhenBootstrapSucceeds() throws {
        let runtime = Runtime()
        runtime.hasInstaller = true
        let lifetime = try RuntimeLifetime.initialized(
            threadingModel: .single, operations: runtime.operations
        )
        lifetime.close()
        XCTAssertEqual(runtime.events, started + [
            "initialize:false", "shutdown", "unload", "ro-uninitialize",
        ])
    }

    func testDiscoveryUsesOnlyBundleAndBuildArchitectureInStableOrder() {
        let executable = URL(fileURLWithPath: #"C:\app"#)
        let module = URL(fileURLWithPath: #"C:\module"#)
        let candidates = BootstrapLibrary.candidateURLs(executableDirectory: executable, moduleDirectory: module)
        XCTAssertEqual(candidates.count, 2)
        for (candidate, directory) in zip(candidates, [executable, module]) {
            XCTAssertEqual(candidate, directory
                .appendingPathComponent("swift-windowsappsdk_CWinAppSDK.bundle")
                .appendingPathComponent("bin")
                .appendingPathComponent(BootstrapLibrary.architecture)
                .appendingPathComponent("Microsoft.WindowsAppRuntime.Bootstrap.dll"))
            XCTAssertFalse(candidate.path.contains(".resources"))
        }
        #if arch(arm64)
        XCTAssertEqual(BootstrapLibrary.architecture, "arm64")
        #elseif arch(x86_64)
        XCTAssertEqual(BootstrapLibrary.architecture, "x86_64")
        #endif
        XCTAssertEqual(
            BootstrapLibrary.candidateURLs(executableDirectory: executable, moduleDirectory: executable).count, 1
        )
    }

    func testModulePathGrowsBufferWithoutUsingTruncatedResult() throws {
        let path = #"C:\app\"# + String(repeating: "x", count: 300) + #"\Probe.exe"#
        let units = Array(path.utf16)
        var capacities: [DWORD] = []
        let url = try BootstrapLibrary.moduleURL(nil, query: { _, buffer, capacity in
            capacities.append(capacity)
            guard Int(capacity) > units.count else { return capacity }
            for (index, unit) in units.enumerated() { buffer?[index] = unit }
            return DWORD(units.count)
        })
        XCTAssertEqual(capacities, [260, 520])
        XCTAssertEqual(url, URL(fileURLWithPath: path))
    }

    func testModulePathFailureAndMaximumLengthAreDiagnosable() {
        XCTAssertThrowsError(try BootstrapLibrary.moduleURL(
            nil, query: { _, _, _ in 0 }, lastError: { 126 }
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("GetModuleFileNameW"))
            XCTAssertTrue(error.localizedDescription.contains("Win32 error 126"))
        }
        var capacities: [DWORD] = []
        XCTAssertThrowsError(try BootstrapLibrary.moduleURL(nil, query: { _, _, capacity in
            capacities.append(capacity)
            return capacity
        })) { error in
            XCTAssertTrue(error.localizedDescription.contains("Win32 error 122"))
        }
        XCTAssertEqual(capacities.last, 32768)
        XCTAssertLessThan(capacities.count, 10)
    }
}

#endif

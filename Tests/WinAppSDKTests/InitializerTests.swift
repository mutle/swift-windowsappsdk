import CWinAppSDK
import Foundation
import WinAppSDK
import XCTest

public class InitiailzerTests: XCTestCase {
    #if os(Windows)
    public func testInitializer() throws {
        guard ProcessInfo.processInfo.environment["WINAPPSDK_RUN_INSTALLED_RUNTIME_TEST"] == "1" else {
            throw XCTSkip("Requires an explicitly enabled installed-runtime integration environment.")
        }
        guard let executable = Bundle.main.executableURL else {
            XCTFail("Cannot locate the test executable.")
            return
        }
        let installer = executable.deletingLastPathComponent().appendingPathComponent("WindowsAppRuntimeInstaller.exe")
        guard !FileManager.default.fileExists(atPath: installer.path) else {
            XCTFail("Installer execution is prohibited in this integration test.")
            return
        }
        XCTAssertNoThrow(try WindowsAppRuntimeInitializer())
    }
    #else
    public func testNonWindowsCompatibilityModulesImport() {
        XCTAssertTrue(true)
    }
    #endif
}

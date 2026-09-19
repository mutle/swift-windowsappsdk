import CWinAppSDK
import WinAppSDK
import XCTest

public class InitiailzerTests: XCTestCase {
    #if os(Windows)
    public func testInitializer() {
        XCTAssertNoThrow(try WindowsAppRuntimeInitializer())
    }
    #else
    public func testNonWindowsCompatibilityModulesImport() {
        XCTAssertTrue(true)
    }
    #endif
}

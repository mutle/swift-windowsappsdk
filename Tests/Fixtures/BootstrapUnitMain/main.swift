#if os(Windows)

import XCTest

let tests: [(String, (RuntimeInitializationTests) -> () throws -> Void)] = [
    ("testSuccessfulLifetimeAndSFalseAreBalanced", RuntimeInitializationTests.testSuccessfulLifetimeAndSFalseAreBalanced),
    ("testPackagedProcessDoesNotResolveOrLoadBootstrap", RuntimeInitializationTests.testPackagedProcessDoesNotResolveOrLoadBootstrap),
    ("testExecutableAndLoaderFailuresCannotRunInstaller", RuntimeInitializationTests.testExecutableAndLoaderFailuresCannotRunInstaller),
    ("testFailedRoInitializeUnloadsWithoutRoUninitializeOrShutdown", RuntimeInitializationTests.testFailedRoInitializeUnloadsWithoutRoUninitializeOrShutdown),
    ("testDpiFailureRollsBackWinRTAndModuleWithoutShutdown", RuntimeInitializationTests.testDpiFailureRollsBackWinRTAndModuleWithoutShutdown),
    ("testBootstrapFailureWithoutInstallerRollsBackAndReports", RuntimeInitializationTests.testBootstrapFailureWithoutInstallerRollsBackAndReports),
    ("testInstallerLaunchFailureAndNonzeroExitRollBack", RuntimeInitializationTests.testInstallerLaunchFailureAndNonzeroExitRollBack),
    ("testFailedRetryDoesNotShutdown", RuntimeInitializationTests.testFailedRetryDoesNotShutdown),
    ("testSuccessfulRetryShutsDownOnceAndCloseIsIdempotent", RuntimeInitializationTests.testSuccessfulRetryShutsDownOnceAndCloseIsIdempotent),
    ("testExistingInstallerIsNotRunWhenBootstrapSucceeds", RuntimeInitializationTests.testExistingInstallerIsNotRunWhenBootstrapSucceeds),
    ("testDiscoveryUsesOnlyBundleAndBuildArchitectureInStableOrder", RuntimeInitializationTests.testDiscoveryUsesOnlyBundleAndBuildArchitectureInStableOrder),
    ("testModulePathGrowsBufferWithoutUsingTruncatedResult", RuntimeInitializationTests.testModulePathGrowsBufferWithoutUsingTruncatedResult),
    ("testModulePathFailureAndMaximumLengthAreDiagnosable", RuntimeInitializationTests.testModulePathFailureAndMaximumLengthAreDiagnosable),
]

XCTMain([testCase(tests)])

#else
#error("The bounded bootstrap unit runner requires Windows.")
#endif

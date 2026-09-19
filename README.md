# swift-windowsappsdk

> [!WARNING]
> This project contains an outdated snapshot of a subset of WinRT projections generated with [swift-winrt](https://github.com/thebrowsercompany/swift-winrt), provided for illustration purposes. To use WinRT APIs in your Swift project, we recommend using [swift-winrt](https://github.com/thebrowsercompany/swift-winrt) directly to generate your own projections.

Swift Language Bindings for the Windows App SDK APIs

On non-Windows platforms, the `WinAppSDK` and `CWinAppSDK` products build as
empty compatibility modules. This keeps a single SwiftPM dependency graph
portable without exposing Windows-only APIs where they cannot be used.

These APIs are intendened to be used in conjuction with the following projects:
- [swift-winui](https://github.com/thebrowsercompany/swift-winui)
- [swift-win2d](https://github.com/thebrowsercompany/swift-win2d)

## APIs
These projections contains a subset of APIs for the Windows App SDK, minus those of WinUI (`Microsoft.UI.Xaml`). See official documentation for more information on these components:

- [API Docs](https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/)
- [Official GitHub repo](https://github.com/microsoft/WindowsAppSDK)

### SDK Versions

1. Windows SDK: `10.0.18362.0`
2. Windows App SDK: `1.5-preview1`

## Project Configuration
The bindings are generated from WinMD files, found in NuGet packages on Nuget.org. There are two key files which drive this:
1. projections.json - this specifies the project/package and which apis to include in the projection
2. generate-bindings.ps1 - this file reads `projections.json` and generates the appropriate bindings.

## Filing Issues

Please file any issues you have with this repository on https://github.com/thebrowsercompany/swift-winrt

## Known Issues and Limitations

- Bootstrap resource discovery supports Windows ARM64 and x64.

- The developer experience for consuming WinRT APIs from Swift is a work in progress. Due to current limitations, not all APIs can be generated as this causes export limit issues.

- The APIs listed in projections.json are required for the other `swift-*` projects to build. Modify a projections.json in any one of those projects could require an update here.

## Using Windows App SDK

In order to use the Windows App SDK, you need to download the Windows App SDK from here: https://aka.ms/windowsappsdk/1.5/1.5.240205001-preview1/windowsappruntimeinstall-x64.exe

### Bootstrap deployment and lifetime

This package targets Swift 6.4 SwiftBuild's generated resource layout:

```text
swift-windowsappsdk_CWinAppSDK.bundle/
  bin/arm64/Microsoft.WindowsAppRuntime.Bootstrap.dll
  bin/x86_64/Microsoft.WindowsAppRuntime.Bootstrap.dll
```

The DLLs are precompiled files owned by the `CWinAppSDK` target and copied by
the build system; they are not generated Swift code. Keep the `.bundle` beside
the executable, or beside the native module containing `CWinAppSDK` when deployed
separately. The loader selects the build architecture, checks the executable's
location first, and tries the owning module's location only if the payload is
absent there. It does not depend on the caller's working directory, search PATH
for the bootstrap DLL, or use legacy `.resources` folders. A present but invalid
DLL is an error rather than a reason to silently use another copy.

Missing payloads, failed loads, and missing bootstrap exports throw errors with
the relevant absolute paths and native error codes. These deployment errors
do not trigger the installer fallback. Both bootstrap exports are validated
before either can be invoked. WinRT and DPI initialization failures identify
the failing API and HRESULT.

Keep `WindowsAppRuntimeInitializer` alive while using the runtime, and create
and release it on the same thread. Successful bootstrap initialization is
balanced by shutdown before unloading its DLL; successful WinRT initialization
(including `S_FALSE`) is balanced exactly once. Failed initialization rolls back
what it acquired, without calling bootstrap shutdown if bootstrap never
initialized. Packaged processes bypass bootstrap loading.

Existing runtime-version matching, threading defaults, DPI behavior, and
installer policy are unchanged: if bootstrap initialization fails and
`WindowsAppRuntimeInstaller.exe` is already beside the executable, the
initializer can run it and retry. This change does not download an installer,
install a runtime proactively, or change the checked-in bootstrap DLLs.

## Bootstrap loader regressions

`Tests/check-bootstrap-loader.ps1` runs isolated Windows subprocess regressions
against the public initializer. These specify Swift 6.4 SwiftBuild's `.bundle`
layout, target-architecture selection, independence from the working directory,
and throwing diagnostics for missing DLLs or exports. Legacy `.resources`
folders must not be used. Export/initialization failures must unload the DLL
before the caller catches the error; successful lifetimes must shut down before
unloading. An owning-module-adjacent case places `WinAppSDK.dll` and its `.bundle`
outside the executable directory. Only that child's environment locates the
owning module; no process-wide or persistent DLL search configuration is changed.

The DLL fixtures return success or a controlled failure without initializing the
real Windows App Runtime. They do not install anything or show runtime-selection UI. Build and
execute these tests only in an explicitly authorized Windows environment.
Use an existing compiler environment targeting the same architecture as the
probe (ARM64 or x64); do not install or switch global toolchains for this check.
Run the positive subprocess cases in an interactive desktop session. In the
recorded Windows environment, an otherwise identical probe in SSH session 0
received `SetProcessDpiAwareness` access denied, while the same binary, payload,
working directory, and environment passed in interactive session 1. Preserve
that error when it occurs; do not weaken the initializer's DPI policy to make
a headless test pass. Record the session context with the result.

Prefer compiling the small probe source against already built, verified
WinAppSDK modules and import libraries, reusing their recorded Swift 6.4 compiler
search/link flags. Record the exact library revision separately from the
regression-suite revision. The initial baseline main `54a8e9b` has identical
initializer, C target, and manifest contents to consumed revision `4bc48b4`.
Do not interpret a baseline-artifact run as testing a later source fix.

If no compatible artifacts exist, the standalone package at
`Tests/Fixtures/BootstrapProbe` can be built with Swift 6.4 SwiftBuild using a
separate scratch directory; its local dependency points to this checkout.
Capacity-check and explicitly authorize that build first, rather than
automatically rebuilding the projection graph. Record the exact checkout
revision and build command alongside the test report.
In a fresh fixture output directory, compile the following with the existing
MSVC developer environment, substituting the absolute fixture source path:

```powershell
cl /nologo /LD /Fo:complete.obj /Fe:complete.dll C:\checkout\Tests\Fixtures\BootstrapExports.c
cl /nologo /LD /DOMIT_INITIALIZE /Fo:missing-initialize.obj /Fe:missing-initialize.dll C:\checkout\Tests\Fixtures\BootstrapExports.c
cl /nologo /LD /DOMIT_SHUTDOWN /Fo:missing-shutdown.obj /Fe:missing-shutdown.dll C:\checkout\Tests\Fixtures\BootstrapExports.c
cl /nologo /LD /DFAIL_INITIALIZE /Fo:initialize-fails.obj /Fe:initialize-fails.dll C:\checkout\Tests\Fixtures\BootstrapExports.c
```

Check every compiler exit code before proceeding; a build failure is not a
failing regression result. Prepare a support directory containing only the
architecture-matched DLL dependencies needed to launch the probe, including its
Swift runtime dependencies. Do not include a loose bootstrap DLL. Then run:

```powershell
.\Tests\check-bootstrap-loader.ps1 `
    -ProbeExecutable C:\probe\BootstrapProbe.exe `
    -SupportDirectory C:\probe-support `
    -FixtureDirectory C:\bootstrap-fixtures `
    -StageRoot C:\isolated-tests\bootstrap-new-run `
    -Architecture arm64
```

Use `x86_64` for x64. The stage must not already exist. The driver copies only
the probe and support DLLs, creates per-case fake bootstrap payloads, rejects
architecture mismatches, and never copies or launches an installer. It preserves
staged files and writes `bootstrap-loader-results.json` with subprocess output,
exit codes, paths, and probe/support/fixture hashes. The support closure is copied
once into the private stage and hard-linked within that stage to keep disk use
bounded; original build files are never hard-linked. Use a volume supporting
hard links. Staging must leave at least 3 GiB free. A crash, timeout, missing
dependency, or missing diagnostic is a failure, not a successful negative test.

These fake-DLL regressions do not replace native integration using the actual
generated resource bundle and an already installed Windows App Runtime.

`RuntimeInitializationTests` adds deterministic XCTest coverage of WinRT,
bootstrap, DPI, and installer failure paths using instance-owned fake operations.
No real installer is launched by those tests. The existing installed-runtime
smoke test is opt-in with `WINAPPSDK_RUN_INSTALLED_RUNTIME_TEST=1` in the test
process's environment and refuses to run when an installer is beside the test
executable.

For an early capacity-bounded check, the Windows executor may compile only
`Initialize.swift`, `BootstrapLibrary.swift`, and `RuntimeInitialization.swift`
as an `-enable-testing` module/library named `WinAppSDK`, linking a newly compiled
`Sources/CWinAppSDK/modulehandle.c` object and the verified dependency artifacts.
Use this checkout's `CWinAppSDK` headers, a private module cache/output directory,
and the original target/search/link flags. Compile
`Tests/WinAppSDKTests/RuntimeInitializationTests.swift` together with
`Tests/Fixtures/BootstrapUnitMain/main.swift` against that module to run the same
XCTest cases without rebuilding generated projections. Recompile the probe
against the candidate module as well.

This reduced bootstrap-only module is a test artifact, **not a replacement for
the complete WinAppSDK product**. Do not place it in a consumer build or overwrite
retained artifacts. Default SwiftBuild package validation and consumer integration
still require the full candidate with coherent exact-revision pins in an isolated,
capacity-checked build. The normal XCTest target remains the canonical test
discovery path.

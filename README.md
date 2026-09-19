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

- Only x64 architecture is supported right now

- The developer experience for consuming WinRT APIs from Swift is a work in progress. Due to current limitations, not all APIs can be generated as this causes export limit issues.

- The APIs listed in projections.json are required for the other `swift-*` projects to build. Modify a projections.json in any one of those projects could require an update here.

## Using Windows App SDK

In order to use the Windows App SDK, you need to download the Windows App SDK from here: https://aka.ms/windowsappsdk/1.5/1.5.240205001-preview1/windowsappruntimeinstall-x64.exe

## Bootstrap loader regressions

`Tests/check-bootstrap-loader.ps1` runs isolated Windows subprocess regressions
against the public initializer. These specify Swift 6.4 SwiftBuild's `.bundle`
layout, target-architecture selection, independence from the working directory,
and throwing diagnostics for missing DLLs or exports. Legacy `.resources`
folders must not be used. The regression suite is expected to fail against the
current unchecked loader until the bootstrap safety fix is implemented.

The DLL fixtures return success without initializing the real Windows App
Runtime. They do not install anything or show runtime-selection UI. Build and
execute these tests only in an explicitly authorized Windows environment.
Use an existing compiler environment targeting the same architecture as the
probe (ARM64 or x64); do not install or switch global toolchains for this check.

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

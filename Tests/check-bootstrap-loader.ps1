param(
    [Parameter(Mandatory = $true)][string]$ProbeExecutable,
    [Parameter(Mandatory = $true)][string]$SupportDirectory,
    [Parameter(Mandatory = $true)][string]$FixtureDirectory,
    [Parameter(Mandatory = $true)][string]$StageRoot,
    [Parameter(Mandatory = $true)][ValidateSet('arm64', 'x86_64')][string]$Architecture
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'Bootstrap loader regressions require Windows.'
}
if (Test-Path -LiteralPath $StageRoot) {
    throw "StageRoot must be a new isolated directory: $StageRoot"
}

function Get-PEMachine([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = [IO.BinaryReader]::new($stream)
    try {
        if ($reader.ReadUInt16() -ne 0x5a4d) { throw "Not a PE file: $Path" }
        $stream.Position = 0x3c
        $offset = $reader.ReadUInt32()
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550) { throw "Invalid PE signature: $Path" }
        return $reader.ReadUInt16()
    } finally {
        $reader.Dispose()
    }
}

function Get-PlainFile([string]$Path) {
    $file = Get-Item -LiteralPath $Path
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a regular file, not a directory or reparse point: $Path"
    }
    return $file
}

$machine = if ($Architecture -eq 'arm64') { 0xaa64 } else { 0x8664 }
$probe = Get-PlainFile $ProbeExecutable
if ((Get-PEMachine $probe.FullName) -ne $machine) { throw 'Probe architecture mismatch.' }
if ($probe.Name -ne 'BootstrapProbe.exe') { throw 'Expected BootstrapProbe.exe.' }

$support = Get-Item -LiteralPath $SupportDirectory
if (!$support.PSIsContainer -or ($support.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'SupportDirectory must be a regular directory.'
}
$supportFiles = @(Get-ChildItem -LiteralPath $support.FullName -File -Filter '*.dll')
foreach ($file in $supportFiles) {
    $null = Get-PlainFile $file.FullName
    if ($file.Name -eq 'Microsoft.WindowsAppRuntime.Bootstrap.dll') {
        throw 'SupportDirectory must not contain a loose bootstrap DLL.'
    }
    if ((Get-PEMachine $file.FullName) -ne $machine) {
        throw "Support DLL architecture mismatch: $($file.FullName)"
    }
}

$fixtures = @{}
foreach ($name in @('complete', 'missing-initialize', 'missing-shutdown')) {
    $file = Get-PlainFile (Join-Path $FixtureDirectory "$name.dll")
    if ((Get-PEMachine $file.FullName) -ne $machine) { throw "Fixture architecture mismatch: $name" }
    $fixtures[$name] = $file.FullName
}

$stagePath = [IO.Path]::GetFullPath($StageRoot)
$volume = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($stagePath))
$copyBytes = $probe.Length
foreach ($file in $supportFiles) { $copyBytes += $file.Length }
if ($volume.AvailableFreeSpace - $copyBytes - 16MB -lt 3GB) {
    throw 'Staging would leave less than the required 3 GiB free-space reserve.'
}
$root = (New-Item -ItemType Directory -Path $stagePath).FullName
$shared = (New-Item -ItemType Directory -Path (Join-Path $root 'shared-runtime')).FullName
$runtimeHashes = @{}
foreach ($file in @($probe) + $supportFiles) {
    $destination = Join-Path $shared $file.Name
    Copy-Item -LiteralPath $file.FullName -Destination $destination
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $hash) {
        throw "Runtime copy hash mismatch: $destination"
    }
    $runtimeHashes[$file.Name] = $hash
}
$dllName = 'Microsoft.WindowsAppRuntime.Bootstrap.dll'
$resourceName = 'swift-windowsappsdk_CWinAppSDK'

function Add-Payload([string]$Directory, [string]$Layout, [string]$Fixture) {
    $destination = Join-Path $Directory "$resourceName.$Layout\bin\$Architecture"
    $null = New-Item -ItemType Directory -Path $destination -Force
    $path = Join-Path $destination $dllName
    if ($Fixture -eq 'invalid-image') {
        [IO.File]::WriteAllText($path, 'This is intentionally not a DLL.')
    } else {
        Copy-Item -LiteralPath $fixtures[$Fixture] -Destination $path
    }
}

$cases = @(
    @{ name = 'bundle-different-cwd'; bundle = 'complete'; success = $true },
    @{ name = 'bundle-same-cwd'; bundle = 'complete'; success = $true; sameCwd = $true },
    @{ name = 'missing-library'; success = $false },
    @{ name = 'missing-initialize'; bundle = 'missing-initialize'; success = $false; symbol = 'MddBootstrapInitialize2'; win32 = 127 },
    @{ name = 'missing-shutdown'; bundle = 'missing-shutdown'; success = $false; symbol = 'MddBootstrapShutdown'; win32 = 127 },
    @{ name = 'legacy-only-is-ignored'; legacy = 'complete'; success = $false },
    @{ name = 'bundle-wins-over-legacy'; bundle = 'complete'; legacy = 'missing-initialize'; success = $true },
    @{ name = 'broken-bundle-does-not-fallback'; bundle = 'invalid-image'; legacy = 'complete'; success = $false; win32 = 193 },
    @{ name = 'cwd-decoys-are-ignored'; decoy = $true; success = $false },
    @{ name = 'unicode-and-spaces'; bundle = 'complete'; success = $true; unicode = $true }
)

$results = @()
foreach ($case in $cases) {
    $caseRoot = Join-Path $root $case.name
    $suffix = if ($case.ContainsKey('unicode')) { "app space $([char]0x00e9)" } else { 'app' }
    $app = (New-Item -ItemType Directory -Path (Join-Path $caseRoot $suffix) -Force).FullName
    $cwd = (New-Item -ItemType Directory -Path (Join-Path $caseRoot 'unrelated-cwd')).FullName
    if ($case.ContainsKey('sameCwd')) { $cwd = $app }
    $executable = Join-Path $app 'BootstrapProbe.exe'
    # Link only private stage copies, never the original build or dependency files.
    foreach ($file in @($probe) + $supportFiles) {
        $null = New-Item -ItemType HardLink -Path (Join-Path $app $file.Name) -Target (Join-Path $shared $file.Name)
    }
    if ($case.ContainsKey('bundle')) { Add-Payload $app 'bundle' $case.bundle }
    if ($case.ContainsKey('legacy')) { Add-Payload $app 'resources' $case.legacy }
    if ($case.ContainsKey('decoy')) {
        Add-Payload $cwd 'bundle' 'complete'
        Add-Payload $cwd 'resources' 'complete'
    }
    if (Test-Path -LiteralPath (Join-Path $app 'WindowsAppRuntimeInstaller.exe')) {
        throw 'Installer execution is prohibited in bootstrap regression stages.'
    }

    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $executable
    $start.WorkingDirectory = $cwd
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        if (!$process.Start()) { throw "Could not start case $($case.name)" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = !$process.WaitForExit(15000)
        if ($timedOut) {
            $process.Kill()
            $process.WaitForExit()
        }
        $output = $stdout.GetAwaiter().GetResult()
        $errorOutput = $stderr.GetAwaiter().GetResult()
        $exitCode = $process.ExitCode
    } finally {
        $process.Dispose()
    }

    $failures = @()
    if ($timedOut) { $failures += 'Probe timed out.' }
    if ($case.success) {
        if ($exitCode -ne 0) { $failures += "Expected exit 0; got $exitCode." }
        foreach ($marker in @('FIXTURE_INITIALIZE', 'BOOTSTRAP_PROBE_INITIALIZED', 'FIXTURE_SHUTDOWN', 'BOOTSTRAP_PROBE_SHUTDOWN')) {
            if ([regex]::Matches($output, "(?m)^$marker`r?$").Count -ne 1) {
                $failures += "Expected exactly one $marker marker."
            }
        }
        if ($output.IndexOf('FIXTURE_SHUTDOWN') -lt $output.IndexOf('BOOTSTRAP_PROBE_INITIALIZED')) {
            $failures += 'Shutdown occurred before the initialized lifetime marker.'
        }
        if ($errorOutput.Length -ne 0) { $failures += 'Unexpected stderr on success.' }
    } else {
        if ($exitCode -ne 1) { $failures += "Expected caught error with exit 1; got $exitCode." }
        foreach ($expected in @('BOOTSTRAP_PROBE_ERROR:', "$resourceName.bundle", $dllName, $app)) {
            if (!$errorOutput.Contains($expected)) { $failures += "Diagnostic omitted: $expected" }
        }
        if ($case.ContainsKey('symbol') -and !$errorOutput.Contains($case.symbol)) {
            $failures += "Diagnostic omitted missing symbol: $($case.symbol)"
        }
        if ($case.ContainsKey('win32') -and $errorOutput -notmatch "\b$($case.win32)\b") {
            $failures += "Diagnostic omitted Win32 error code: $($case.win32)"
        }
        if ($output -match 'FIXTURE_INITIALIZE|FIXTURE_SHUTDOWN|BOOTSTRAP_PROBE_INITIALIZED') {
            $failures += 'An invalid bootstrap was invoked before validation completed.'
        }
    }

    $result = [ordered]@{
        name = $case.name
        passed = ($failures.Count -eq 0)
        exitCode = $exitCode
        timedOut = $timedOut
        executable = $executable
        cwd = $cwd
        stdout = $output
        stderr = $errorOutput
        failures = $failures
    }
    $results += $result
    $label = if ($result.passed) { 'PASS' } else { 'FAIL' }
    Write-Output "$label $($case.name): exit=$exitCode"
}

$fixtureHashes = @{}
foreach ($name in $fixtures.Keys) {
    $fixtureHashes[$name] = (Get-FileHash -LiteralPath $fixtures[$name] -Algorithm SHA256).Hash
}
$report = [ordered]@{
    architecture = $Architecture
    probeSHA256 = (Get-FileHash -LiteralPath $probe.FullName -Algorithm SHA256).Hash
    runtimeSHA256 = $runtimeHashes
    fixtureSHA256 = $fixtureHashes
    usesRealBootstrap = $false
    results = $results
}
$reportPath = Join-Path $root 'bootstrap-loader-results.json'
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 8))
Write-Output "REPORT=$reportPath"
if (@($results | Where-Object { !$_.passed }).Count -ne 0) { exit 1 }

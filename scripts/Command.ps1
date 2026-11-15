param(
    [Parameter(Mandatory=$true)][string]$Action,
    [ValidateSet('windows', 'linux')][string]$TargetPlatform = 'windows',
    [ValidateSet('Debug', 'Release')][string]$BuildType = 'Release'
)
$ErrorActionPreference = 'Stop'
$ocbRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $ocbRoot
. (Join-Path $PSScriptRoot 'Platform.ps1') -TargetPlatform $TargetPlatform
$env:PATH = (Join-Path $ocbRoot 'build/TestTools/bin') + [IO.Path]::PathSeparator + $env:PATH
function invokeChecked([string]$executable, [string[]]$arguments) {
    & $executable @arguments
    if ($LASTEXITCODE -ne 0) { throw "$executable failed with exit code $LASTEXITCODE." }
}
function invokeFrontend([string[]]$arguments) {
    Push-Location -LiteralPath (Join-Path $ocbRoot 'Frontend')
    try { invokeChecked 'npm.cmd' $arguments }
    finally { Pop-Location }
}
function invokeCargo([string[]]$arguments) {
    Push-Location -LiteralPath (Join-Path $ocbRoot 'Backend')
    try { invokeChecked 'cargo.exe' $arguments }
    finally { Pop-Location }
}
function invokeTauri([string[]]$arguments) {
    Push-Location -LiteralPath (Join-Path $ocbRoot 'Backend/Desktop')
    try { invokeChecked 'node.exe' (@((Join-Path $ocbRoot 'build/Dependencies/node_modules/@tauri-apps/cli/tauri.js')) + $arguments) }
    finally { Pop-Location }
}
function splitArguments([string]$value) {
    if ($value) { @($value -split '\s+' | Where-Object { $_ }) }
}
$ocbBuildArgs = @('build', '--no-bundle')
if ($BuildType -eq 'Debug') { $ocbBuildArgs += '--debug' }
switch ($Action) {
    'check-platform' {
        Write-Output "Platform: windows / native PowerShell / MSVC x64"
        foreach ($ocbTool in @('make.exe', 'cl.exe', 'link.exe', 'rc.exe', 'node.exe', 'cargo.exe')) {
            Write-Output "$ocbTool : $((Get-Command $ocbTool).Source)"
        }
        invokeChecked 'rustc.exe' @('-vV')
    }
    'format' { invokeCargo @('fmt', '--all') }
    'test-tools' { & (Join-Path $PSScriptRoot 'TestTools.ps1') }
    'frontend-build' { invokeFrontend @('run', 'build') }
    'init' { invokeFrontend @('run', 'init'); invokeCargo @('fetch', '--locked', '--target', 'x86_64-pc-windows-msvc') }
    'build' { invokeTauri $ocbBuildArgs }
    'run' {
        if ($BuildType -eq 'Debug') { invokeTauri @('dev') }
        else {
            invokeTauri $ocbBuildArgs
            invokeChecked (Join-Path $ocbRoot 'build/Backend/release/OpenCircuitBoard.exe') @()
        }
    }
    'package' { invokeTauri @('build', '--bundles', 'nsis') }
    'core-test' { invokeCargo @('test', '--locked', '-p', 'ocb-core') }
    'core-benchmark' {
        invokeCargo (@('run', '--locked', '--release', '-p', 'ocb-core', '--bin', 'ocb-benchmark', '--') + @(splitArguments $env:CORE_BENCHMARK_ARGS))
    }
    'board-benchmark' {
        if (-not $env:BOARD_PATH) { throw 'BOARD_PATH is required.' }
        $ocbBoardPath = [IO.Path]::GetFullPath($env:BOARD_PATH)
        invokeCargo (@('run', '--locked', '--release', '-p', 'ocb-core', '--bin', 'ocb-board-benchmark', '--', $ocbBoardPath) + @(splitArguments $env:BOARD_BENCHMARK_ARGS))
    }
    'frontend-test' {
        invokeFrontend @('run', 'build')
        invokeFrontend @('test')
        invokeFrontend (@('run', 'test:browser', '--', '--config', 'Playwright.config.ts') + @(splitArguments $env:FRONTEND_TEST))
    }
    'browser-test' { invokeFrontend @('run','build'); invokeFrontend (@('run', 'test:browser', '--', '--config', 'Playwright.config.ts') + @(splitArguments $env:FRONTEND_TEST)) }
    'native-ui-test' {
        if (-not (Test-Path -LiteralPath (Join-Path $ocbRoot 'build/Backend/release/OpenCircuitBoard.exe'))) { throw 'Build the release app before testing an existing binary.' }
        invokeFrontend @('run', 'test:desktop')
    }
    'native-test' {
        if (-not (Get-Command tauri-driver.exe -ErrorAction SilentlyContinue)) { throw 'Install tauri-driver and matching EdgeDriver; see README.md.' }
        invokeTauri @('build', '--no-bundle')
        invokeFrontend @('run', 'test:desktop')
    }
    'test' {
        invokeCargo @('test', '--locked', '--workspace')
        invokeFrontend @('run', 'build')
        invokeFrontend @('test')
        invokeFrontend @('run', 'test:browser', '--', '--config', 'Playwright.config.ts')
    }
    'clean' {
        invokeCargo @('clean')
        foreach ($ocbDirectory in @('build')) {
            $ocbTarget = [IO.Path]::GetFullPath((Join-Path $ocbRoot $ocbDirectory))
            if (-not $ocbTarget.StartsWith($ocbRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Clean target is outside the workspace.' }
            if (Test-Path -LiteralPath $ocbTarget) { Remove-Item -LiteralPath $ocbTarget -Recurse -Force }
        }
    }
    default { throw "Unknown command: $Action" }
}

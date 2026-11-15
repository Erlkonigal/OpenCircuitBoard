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
function invokeTauri([string[]]$arguments) {
    Push-Location -LiteralPath (Join-Path $ocbRoot 'Desktop')
    try { invokeChecked 'node.exe' (@('../node_modules/@tauri-apps/cli/tauri.js') + $arguments) }
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
    'format' { invokeChecked 'cargo.exe' @('fmt', '--all') }
    'test-tools' { & (Join-Path $PSScriptRoot 'TestTools.ps1') }
    'frontend-build' { invokeChecked 'npm.cmd' @('run', 'build') }
    'init' { invokeChecked 'npm.cmd' @('ci'); invokeChecked 'cargo.exe' @('fetch', '--locked') }
    'build' { invokeTauri $ocbBuildArgs }
    'run' {
        if ($BuildType -eq 'Debug') { invokeTauri @('dev') }
        else {
            invokeTauri $ocbBuildArgs
            invokeChecked (Join-Path $ocbRoot 'target/release/OpenCircuitBoard.exe') @()
        }
    }
    'package' { invokeTauri @('build', '--bundles', 'nsis') }
    'core-test' { invokeChecked 'cargo.exe' @('test', '--locked', '-p', 'ocb-core') }
    'core-benchmark' {
        invokeChecked 'cargo.exe' (@('run', '--locked', '--release', '-p', 'ocb-core', '--bin', 'ocb-benchmark', '--') + @(splitArguments $env:CORE_BENCHMARK_ARGS))
    }
    'board-benchmark' {
        if (-not $env:BOARD_PATH) { throw 'BOARD_PATH is required.' }
        invokeChecked 'cargo.exe' (@('run', '--locked', '--release', '-p', 'ocb-core', '--bin', 'ocb-board-benchmark', '--', $env:BOARD_PATH) + @(splitArguments $env:BOARD_BENCHMARK_ARGS))
    }
    'frontend-test' {
        invokeChecked 'npm.cmd' @('run', 'build')
        invokeChecked 'npm.cmd' @('test')
        invokeChecked 'npm.cmd' (@('run', 'test:browser', '--', '--config', 'Playwright.config.ts') + @(splitArguments $env:FRONTEND_TEST))
    }
    'browser-test' { invokeChecked 'npm.cmd' @('run','build'); invokeChecked 'npm.cmd' (@('run', 'test:browser', '--', '--config', 'Playwright.config.ts') + @(splitArguments $env:FRONTEND_TEST)) }
    'native-ui-test' {
        if (-not (Test-Path -LiteralPath (Join-Path $ocbRoot 'target/release/OpenCircuitBoard.exe'))) { throw 'Build the release app before testing an existing binary.' }
        invokeChecked 'npm.cmd' @('run', 'test:desktop')
    }
    'native-test' {
        if (-not (Get-Command tauri-driver.exe -ErrorAction SilentlyContinue)) { throw 'Install tauri-driver and matching EdgeDriver; see README.md.' }
        invokeTauri @('build', '--no-bundle')
        invokeChecked 'npm.cmd' @('run', 'test:desktop')
    }
    'test' {
        invokeChecked 'cargo.exe' @('test', '--locked', '--workspace')
        invokeChecked 'npm.cmd' @('run', 'build')
        invokeChecked 'npm.cmd' @('test')
        invokeChecked 'npm.cmd' @('run', 'test:browser', '--', '--config', 'Playwright.config.ts')
    }
    'clean' {
        invokeChecked 'cargo.exe' @('clean')
        foreach ($ocbDirectory in @('build', 'dist', 'test-results', 'playwright-report')) {
            $ocbTarget = [IO.Path]::GetFullPath((Join-Path $ocbRoot $ocbDirectory))
            if (-not $ocbTarget.StartsWith($ocbRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Clean target is outside the workspace.' }
            if (Test-Path -LiteralPath $ocbTarget) { Remove-Item -LiteralPath $ocbTarget -Recurse -Force }
        }
    }
    default { throw "Unknown command: $Action" }
}

param([ValidateSet('windows', 'linux')][string]$TargetPlatform = 'windows')
$ErrorActionPreference = 'Stop'
if ($TargetPlatform -ne 'windows' -or $env:OS -ne 'Windows_NT') {
    throw 'Windows targets require native Windows PowerShell. Use native Linux Bash for Linux targets.'
}
if ($env:MSYSTEM -or $env:WSL_DISTRO_NAME) {
    throw 'Run Windows make from native PowerShell, outside MSYS2, Git Bash, or WSL.'
}
foreach ($ocbTool in @('make.exe', 'node.exe', 'npm.cmd', 'cargo.exe', 'rustc.exe')) {
    $ocbResolved = Get-Command $ocbTool -CommandType Application -ErrorAction Stop
    if ($ocbResolved.Source -match '(?i)[\\/](msys\d*|mingw\d*|ucrt64|cygwin\d*)[\\/]') {
        throw "$ocbTool must come from a native Windows installation: $($ocbResolved.Source)"
    }
}
$ocbVsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $ocbVsWhere)) {
    throw 'Install Visual Studio Build Tools with Desktop development with C++ and a Windows SDK.'
}
$ocbVsPath = (& $ocbVsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
if (-not $ocbVsPath) { throw 'Visual Studio x64 C++ build tools were not found.' }
Import-Module (Join-Path $ocbVsPath 'Common7/Tools/Microsoft.VisualStudio.DevShell.dll')
Enter-VsDevShell -VsInstallPath $ocbVsPath -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
foreach ($ocbTool in @('cl.exe', 'link.exe')) {
    $ocbResolved = Get-Command $ocbTool -CommandType Application -ErrorAction Stop
    if (-not $ocbResolved.Source.StartsWith($ocbVsPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$ocbTool must belong to the selected Visual Studio installation."
    }
}
$ocbRc = Get-Command rc.exe -CommandType Application -ErrorAction Stop
if (-not $env:WindowsSdkDir -or -not $ocbRc.Source.StartsWith($env:WindowsSdkDir, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'A matching Windows SDK resource compiler is required.'
}
$env:RUSTUP_TOOLCHAIN = 'stable-x86_64-pc-windows-msvc'
$ocbRustVersion = & rustc.exe -vV
if ($LASTEXITCODE -ne 0 -or -not ($ocbRustVersion -contains 'host: x86_64-pc-windows-msvc')) {
    throw 'Install Rust with rustup toolchain install stable-x86_64-pc-windows-msvc.'
}
& node.exe -e "if(process.platform!=='win32' || process.arch!=='x64' || process.config.variables.shlib_suffix==='dll.a' || process.config.variables.node_target_type==='shared_library') process.exit(1)"
if ($LASTEXITCODE -ne 0) { throw 'Install standard x64 Windows Node.js.' }

$ErrorActionPreference = 'Stop'
$ocbRoot = Split-Path -Parent $PSScriptRoot
$ocbBin = Join-Path $ocbRoot 'build/TestTools/bin'
if (-not (Test-Path -LiteralPath (Join-Path $ocbBin 'tauri-driver.exe'))) {
    & cargo.exe install tauri-driver --locked --root (Join-Path $ocbRoot 'build/TestTools')
    if ($LASTEXITCODE -ne 0) { throw 'tauri-driver installation failed.' }
}
$ocbEdge = Join-Path ${env:ProgramFiles(x86)} 'Microsoft/Edge/Application/msedge.exe'
if (-not (Test-Path -LiteralPath $ocbEdge)) { $ocbEdge = Join-Path $env:ProgramFiles 'Microsoft/Edge/Application/msedge.exe' }
$ocbVersion = (Get-Item -LiteralPath $ocbEdge).VersionInfo.ProductVersion
$ocbDriver = Join-Path $ocbBin 'msedgedriver.exe'
if ((Test-Path -LiteralPath $ocbDriver) -and ((& $ocbDriver --version) -like "*$ocbVersion*")) { return }
$ocbArchive = Join-Path $ocbRoot 'build/TestTools/EdgeDriver.zip'
Invoke-WebRequest -UseBasicParsing -Uri "https://msedgedriver.microsoft.com/$ocbVersion/edgedriver_win64.zip" -OutFile $ocbArchive
Expand-Archive -LiteralPath $ocbArchive -DestinationPath $ocbBin -Force
& $ocbDriver --version
if ($LASTEXITCODE -ne 0) { throw 'EdgeDriver installation failed.' }

<#
重新編譯 Uninstall-McAfee.msi。
只有維護者需要跑這支腳本；一般使用者直接下載 dist\Uninstall-McAfee.msi 使用即可，不需要裝任何工具。
#>

$ErrorActionPreference = "Stop"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "找不到 dotnet SDK，請先安裝 .NET SDK：https://dotnet.microsoft.com/download"
}

$toolsPath = Join-Path $env:USERPROFILE ".dotnet\tools"
if ($env:PATH -notlike "*$toolsPath*") {
    $env:PATH += ";$toolsPath"
}

if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
    Write-Host "安裝 WiX Toolset v5(dotnet 工具，免費、不需要另外同意授權)..." -ForegroundColor Cyan
    dotnet tool install --global wix --version 5.0.2
}

# 安裝完成後要跳出「是否立即執行」的勾選框(ExitDialog),需要 UI + Util 這兩個
# 官方擴充套件；版本要釘住跟核心工具一樣的 5.0.2,不然預設抓到的最新版
# 可能跟 WiX 5 核心不相容。
$existingExt = wix extension list -g 2>$null
if ($existingExt -notmatch "WixToolset\.UI\.wixext") {
    wix extension add -g WixToolset.UI.wixext/5.0.2
}
if ($existingExt -notmatch "WixToolset\.Util\.wixext") {
    wix extension add -g WixToolset.Util.wixext/5.0.2
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path (Split-Path -Parent $scriptDir) "Dist"
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

Push-Location $scriptDir
try {
    wix build Uninstall-McAfee.wxs -arch x64 -ext WixToolset.UI.wixext -ext WixToolset.Util.wixext -o (Join-Path $distDir "Uninstall-McAfee.msi")
} finally {
    Pop-Location
}

Remove-Item (Join-Path $distDir "Uninstall-McAfee.wixpdb") -ErrorAction SilentlyContinue

Write-Host "完成：$distDir\Uninstall-McAfee.msi" -ForegroundColor Green

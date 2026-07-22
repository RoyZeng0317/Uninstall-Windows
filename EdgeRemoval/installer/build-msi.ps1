<#
重新編譯 Uninstall-Edge.msi。
只有維護者需要跑這支腳本；一般使用者直接下載 dist\Uninstall-Edge.msi 使用即可，不需要裝任何工具。
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

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$distDir = Join-Path (Split-Path -Parent $scriptDir) "dist"
New-Item -ItemType Directory -Force -Path $distDir | Out-Null

Push-Location $scriptDir
try {
    wix build Uninstall-Edge.wxs -arch x64 -o (Join-Path $distDir "Uninstall-Edge.msi")
} finally {
    Pop-Location
}

Write-Host "完成：$distDir\Uninstall-Edge.msi" -ForegroundColor Green

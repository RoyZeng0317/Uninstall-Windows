<#
徹底解除安裝 Microsoft Edge。
先建立系統還原點,再下載並執行 ShadowWhisperer/Remove-MS-Edge 的 Edge.bat(只移除 Edge 本體,保留 WebView2)。
詳見同目錄 README.md。
#>

param(
    [switch]$SkipRestorePoint,
    # 由 MSI 安裝程式的 CustomAction 呼叫時帶入:當下已由 Windows Installer 以提升權限執行,
    # 不需要再自我 relaunch,也不能跳出任何互動式提示(Session 0 沒有桌面,Read-Host 會卡死)。
    [switch]$Unattended
)

$ErrorActionPreference = "Stop"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($Unattended) {
        Write-Host "非提升權限環境,且處於無人值守模式,無法自動提權,結束。" -ForegroundColor Red
        exit 1
    }
    Write-Host "需要系統管理員權限,重新啟動中..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"" -Verb RunAs
    exit
}

if ($Unattended) {
    $logPath = Join-Path (Split-Path -Parent $PSCommandPath) "Uninstall-Edge.log"
    try { Start-Transcript -Path $logPath -Append -ErrorAction SilentlyContinue | Out-Null } catch {}
}

Write-Host "=== 1/4 關閉 Edge 相關程序 ===" -ForegroundColor Cyan
Stop-Process -Name "msedge", "msedgewebview2", "MicrosoftEdgeUpdate" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

if (-not $SkipRestorePoint) {
    Write-Host "=== 2/4 建立系統還原點 ===" -ForegroundColor Cyan
    try {
        Enable-ComputerRestore -Drive "C:\"
        Checkpoint-Computer -Description "Before-Edge-Removal-Tool" -RestorePointType "MODIFY_SETTINGS"
        Write-Host "還原點建立成功。" -ForegroundColor Green
    } catch {
        Write-Host "還原點建立失敗: $_" -ForegroundColor Yellow
        if ($Unattended -or -not [Environment]::UserInteractive) {
            Write-Host "無人值守模式,略過確認,繼續執行。" -ForegroundColor Yellow
        } else {
            $answer = Read-Host "要不要在沒有還原點的情況下繼續? [Y/N]"
            if ($answer -notmatch "^[Yy]") { exit 1 }
        }
    }
}

Write-Host "=== 3/4 下載並執行 Edge 移除工具 (ShadowWhisperer/Remove-MS-Edge) ===" -ForegroundColor Cyan
$scriptDir = Split-Path -Parent $PSCommandPath
$edgeBatPath = Join-Path $scriptDir "Edge.bat"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ShadowWhisperer/Remove-MS-Edge/master/Batch/Edge.bat" -OutFile $edgeBatPath

$proc = Start-Process cmd.exe -ArgumentList "/c", "`"$edgeBatPath`"" -Wait -PassThru
Write-Host "Edge.bat 結束代碼: $($proc.ExitCode)"

Write-Host "=== 4/4 驗證移除結果 ===" -ForegroundColor Cyan
$stillExists = (Test-Path "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe") -or
               (Test-Path "C:\Program Files\Microsoft\Edge\Application\msedge.exe")

if (-not $stillExists) {
    Write-Host "Microsoft Edge 已成功移除。建議重新開機完成清理。" -ForegroundColor Green
} else {
    Write-Host "msedge.exe 仍然存在,移除可能未完全成功,請檢查 $edgeBatPath 同目錄下的 Edge_dbg.log。" -ForegroundColor Red
}

if ($Unattended) {
    try { Stop-Transcript | Out-Null } catch {}
}

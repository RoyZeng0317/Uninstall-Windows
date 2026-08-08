<#
徹底解除安裝 OneDrive(Windows 11 內建、控制台/設定 App 移除不乾淨時使用)。
先建立系統還原點,關閉 OneDrive 相關程序,執行官方 OneDriveSetup.exe /uninstall,
再清除安裝殘留(登錄機碼、檔案總管導覽窗格圖示、開機自動啟動、排程工作)。
**不會刪除** %USERPROFILE%\OneDrive 資料夾裡使用者的個人檔案,詳見同目錄 README.md。
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
    $logPath = Join-Path (Split-Path -Parent $PSCommandPath) "Uninstall-OneDrive.log"
    try { Start-Transcript -Path $logPath -Append -ErrorAction SilentlyContinue | Out-Null } catch {}
}

$clsid = "{018D5C66-4533-4307-9B53-224DE2ED1FE6}"

Write-Host "=== 1/6 關閉 OneDrive 相關程序 ===" -ForegroundColor Cyan
Stop-Process -Name "OneDrive", "OneDriveStandaloneUpdater", "FileCoAuth" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

if (-not $SkipRestorePoint) {
    Write-Host "=== 2/6 建立系統還原點 ===" -ForegroundColor Cyan
    try {
        Enable-ComputerRestore -Drive "C:\"
        Checkpoint-Computer -Description "Before-OneDrive-Removal-Tool" -RestorePointType "MODIFY_SETTINGS"
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

Write-Host "=== 3/6 執行 OneDrive 官方解除安裝程式 (OneDriveSetup.exe /uninstall) ===" -ForegroundColor Cyan
$setupCandidates = New-Object System.Collections.Generic.List[string]

# 2020 年之後的版本:安裝於 per-machine Program Files 下的版本號子資料夾
$machineRoots = @(
    (Join-Path $env:ProgramFiles "Microsoft OneDrive"),
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft OneDrive")
)
foreach ($root in $machineRoots) {
    if (Test-Path $root) {
        Get-ChildItem -Path $root -Filter "OneDriveSetup.exe" -Recurse -ErrorAction SilentlyContinue |
            ForEach-Object { $setupCandidates.Add($_.FullName) }
    }
}

# 舊版:內建於系統目錄的 per-user 安裝程式
$legacyPaths = @(
    (Join-Path $env:SystemRoot "SysWOW64\OneDriveSetup.exe"),
    (Join-Path $env:SystemRoot "System32\OneDriveSetup.exe")
)
foreach ($p in $legacyPaths) {
    if (Test-Path $p) { $setupCandidates.Add($p) }
}

$setupCandidates = $setupCandidates | Select-Object -Unique

if ($setupCandidates.Count -eq 0) {
    Write-Host "找不到 OneDriveSetup.exe,可能尚未安裝或先前已移除,略過此步驟。" -ForegroundColor Yellow
} else {
    foreach ($setupExe in $setupCandidates) {
        Write-Host "執行 `"$setupExe`" /uninstall ..." -ForegroundColor White
        Start-Process -FilePath $setupExe -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue
        if ($setupExe -like "*Program Files*") {
            Write-Host "執行 `"$setupExe`" /uninstall /allusers ..." -ForegroundColor White
            Start-Process -FilePath $setupExe -ArgumentList "/uninstall", "/allusers" -Wait -ErrorAction SilentlyContinue
        }
    }
}
Start-Sleep -Seconds 2

Write-Host "=== 4/6 清除安裝殘留資料夾與登錄機碼 ===" -ForegroundColor Cyan
Write-Host "(不會刪除 $($env:USERPROFILE)\OneDrive 裡的個人檔案,只清除程式本身的安裝與快取資料)" -ForegroundColor DarkGray
$leftoverDirs = @(
    (Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive"),
    (Join-Path $env:ProgramData "Microsoft OneDrive"),
    (Join-Path $env:ProgramFiles "Microsoft OneDrive"),
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft OneDrive")
)
foreach ($dir in $leftoverDirs) {
    if (Test-Path $dir) {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDrive" -ErrorAction SilentlyContinue
Remove-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "OneDriveSetup" -ErrorAction SilentlyContinue

$clsidPaths = @(
    "HKCU:\SOFTWARE\Classes\CLSID\$clsid",
    "HKCU:\SOFTWARE\Classes\Wow6432Node\CLSID\$clsid",
    "HKLM:\SOFTWARE\Classes\CLSID\$clsid",
    "HKLM:\SOFTWARE\Classes\WOW6432Node\CLSID\$clsid"
)
foreach ($p in $clsidPaths) {
    if (Test-Path $p) { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "=== 5/6 移除排程工作 ===" -ForegroundColor Cyan
Get-ScheduledTask -TaskName "OneDrive*" -ErrorAction SilentlyContinue |
    Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "=== 6/6 驗證移除結果 ===" -ForegroundColor Cyan
$stillRunning = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
$stillInstalled = $false
foreach ($dir in $machineRoots + $legacyPaths) {
    if (Test-Path $dir) { $stillInstalled = $true }
}

if (-not $stillRunning -and -not $stillInstalled) {
    Write-Host "OneDrive 程式本體已成功移除。建議重新開機完成清理。" -ForegroundColor Green
} else {
    Write-Host "仍偵測到 OneDrive 相關程序或安裝檔案,移除可能未完全成功,請檢查同目錄下的 Uninstall-OneDrive.log。" -ForegroundColor Red
}
Write-Host "提醒:$($env:USERPROFILE)\OneDrive 資料夾(如果裡面還有你的個人檔案)不會被自動刪除,請自行確認備份後再手動處理。" -ForegroundColor Yellow

if ($Unattended) {
    try { Stop-Transcript | Out-Null } catch {}
}

<#
徹底解除安裝 McAfee(Control Panel / 設定 App 無法移除時使用)。
先建立系統還原點,停止 McAfee 相關程序與服務,再下載並執行 McAfee 官方的
McAfee Consumer Product Removal 工具(MCPR.exe),下載後驗證數位簽章
確實來自 McAfee 才會執行。
詳見同目錄 README.md。
#>

param(
    [switch]$SkipRestorePoint,
    # 選用:略過自我提權判斷與所有「是否繼續」互動式提示(改成失敗就警告後
    # 直接繼續,不中斷),並把過程寫進同目錄的 Uninstall-McAfee.log。
    # 注意:MCPR.exe 本身一定會跳出視窗(McAfee 官方工具沒有可靠的靜默安裝
    # 開關,新版已移除 -s 靜默參數),所以就算是 -Unattended 模式,還是需要
    # 使用者手動點過 MCPR 的精靈畫面。msi 安裝包(見 installer/*.wxs)是在
    # 使用者當下的互動式工作階段啟動這支腳本(不是背景執行),所以不會帶
    # -Unattended,直接沿用一般的自我提權 + 互動式提示。
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
    $logPath = Join-Path (Split-Path -Parent $PSCommandPath) "Uninstall-McAfee.log"
    try { Start-Transcript -Path $logPath -Append -ErrorAction SilentlyContinue | Out-Null } catch {}
}

Write-Host "=== 1/5 關閉 McAfee 相關程序 ===" -ForegroundColor Cyan
$mcafeeProcessNames = @(
    "mcshield", "mfemms", "mfevtps", "mfefire", "mfeann",
    "McUICnt", "Mcx2Svc", "MSC", "McCSPServiceHost", "McAWFwk",
    "McAfeeMPP", "mcapexe", "McTray", "mfeesp"
)
Stop-Process -Name $mcafeeProcessNames -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

if (-not $SkipRestorePoint) {
    Write-Host "=== 2/5 建立系統還原點 ===" -ForegroundColor Cyan
    try {
        Enable-ComputerRestore -Drive "C:\"
        Checkpoint-Computer -Description "Before-McAfee-Removal-Tool" -RestorePointType "MODIFY_SETTINGS"
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

Write-Host "=== 3/5 下載 McAfee 官方移除工具 (MCPR.exe) ===" -ForegroundColor Cyan
$scriptDir = Split-Path -Parent $PSCommandPath
$mcprPath = Join-Path $scriptDir "MCPR.exe"
Invoke-WebRequest -Uri "https://download.mcafee.com/molbin/iss-loc/SupportTools/MCPR/MCPR.exe" -OutFile $mcprPath

Write-Host "=== 4/5 驗證數位簽章 ===" -ForegroundColor Cyan
$sig = Get-AuthenticodeSignature -FilePath $mcprPath
if ($sig.Status -ne "Valid" -or $sig.SignerCertificate.Subject -notmatch "McAfee") {
    Write-Host "下載的檔案簽章驗證失敗(狀態: $($sig.Status),簽署者: $($sig.SignerCertificate.Subject))。" -ForegroundColor Red
    Write-Host "為安全起見,不會執行此檔案。請自行到 McAfee 官網確認下載連結是否已變更。" -ForegroundColor Red
    if ($Unattended) { try { Stop-Transcript | Out-Null } catch {} }
    exit 1
}
Write-Host "簽章驗證通過,簽署者: $($sig.SignerCertificate.Subject)" -ForegroundColor Green

Write-Host "=== 5/5 執行 MCPR.exe ===" -ForegroundColor Cyan
Write-Host "接下來會跳出 McAfee 官方移除精靈視窗,請依畫面指示操作(通常是按幾次「下一步」/輸入圖片驗證碼)。" -ForegroundColor Yellow
Write-Host "MCPR 是 McAfee 官方工具,目前新版本已不支援可靠的靜默安裝參數,所以這一步無法完全自動化。" -ForegroundColor Yellow
$proc = Start-Process -FilePath $mcprPath -Wait -PassThru
Write-Host "MCPR.exe 結束代碼: $($proc.ExitCode)"

Write-Host "=== 驗證移除結果 ===" -ForegroundColor Cyan
$remaining = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "McAfee" } |
    Select-Object -ExpandProperty DisplayName

if (-not $remaining) {
    Write-Host "登錄機碼中已找不到 McAfee 相關項目。建議重新開機完成清理。" -ForegroundColor Green
} else {
    Write-Host "仍偵測到以下 McAfee 相關項目,移除可能未完全成功:" -ForegroundColor Red
    $remaining | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    Write-Host "可重新執行本腳本,或參考同目錄 README.md 的疑難排解章節。" -ForegroundColor Yellow
}

if ($Unattended) {
    try { Stop-Transcript | Out-Null } catch {}
}

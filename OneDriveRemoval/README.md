# 徹底解除安裝 OneDrive(控制台/設定 App 無法強制移除時)

紀錄實際排查與解決過程,含最終有效方法(供日後參考排錯)。

## 問題背景

Windows 11 內建的 OneDrive 常見狀況:「設定 → 應用程式」裡找不到解除安裝選項、點了沒反應,或移除後檔案總管導覽窗格仍留著 OneDrive 圖示、開機仍自動啟動,殘留一堆登錄機碼與資料夾。

## 有效解法

不使用來路不明的「強制刪除登錄機碼/檔案」腳本,而是用 **OneDrive 官方自帶的解除安裝程式 `OneDriveSetup.exe /uninstall`**(這是微軟自己內建在系統裡的解除安裝參數,不是第三方工具),再補上官方解除安裝程式沒清乾淨的殘留。

`Uninstall-OneDrive.ps1` 把整個流程自動化:
1. 關閉 OneDrive 相關程序(`OneDrive.exe`、`FileCoAuth.exe` 等),避免檔案被鎖住
2. 建立系統還原點
3. 找出本機所有 `OneDriveSetup.exe`(新版安裝在 `Program Files\Microsoft OneDrive` 版本號子資料夾,舊版內建於系統目錄),逐一執行 `/uninstall`(新版另外補跑一次 `/uninstall /allusers`)
4. 清除安裝殘留:程式本身的安裝目錄與快取資料夾、開機自動啟動登錄機碼、檔案總管導覽窗格的 OneDrive 圖示(CLSID)
5. 移除殘留的 OneDrive 排程工作
6. 檢查是否還有 OneDrive 程序或安裝檔案殘留

> **這一步是全自動、靜默執行的**:跟 McAfee 的 MCPR.exe 不同,`OneDriveSetup.exe /uninstall` 本身不會跳出精靈視窗,所以整個流程(含 msi 安裝)不需要手動點擊任何畫面。

> **不會刪除的東西**:`%USERPROFILE%\OneDrive` 資料夾(如果裡面還有你尚未搬移的個人檔案)**不會被自動刪除**,腳本只清除程式本身的安裝與快取資料,避免誤刪使用者資料。如果確認裡面沒有需要保留的檔案,移除完成後可自行手動刪除。

### 執行前必做:建立系統還原點

這個工具會移除安裝目錄與多使用者登錄機碼,屬於較深層的系統變更。**務必先建立系統還原點**,萬一有問題可以直接還原(腳本預設會自動建立):

```powershell
Enable-ComputerRestore -Drive "C:\"
Checkpoint-Computer -Description "Before-OneDrive-Removal-Tool" -RestorePointType "MODIFY_SETTINGS"
```

> 若最近 24 小時內已經建立過還原點,系統預設每 1440 分鐘只允許建立一次,這裡會顯示警告但不影響後續步驟,可以忽略繼續。

### 方法 A(推薦):直接安裝 .msi,雙擊執行

不需要裝 Git、不需要處理 PowerShell 執行原則、不需要貼指令。下載 [`Uninstall-OneDrive.msi`](https://github.com/RoyZeng0317/Uninstall-Windows/releases/download/onedrive-v1.0.0/Uninstall-OneDrive.msi)(點擊連結會直接觸發瀏覽器下載,不會先跳到 GitHub 網頁預覽),**直接雙擊**:

1. 雙擊 `Uninstall-OneDrive.msi`
2. 跳出 UAC 提示,按「是」授權
3. 安裝程式會自動以系統管理員權限執行移除腳本(略過還原點的互動確認,無人值守模式,全程不需要手動點擊)
4. 完成後,可在 `C:\Program Files\Uninstall-OneDrive-Tool\Uninstall-OneDrive.log` 查看完整執行紀錄,確認 OneDrive 是否移除成功
5. 想重跑一次(例如 OneDrive 之後被 Windows Update 或 OEM 預載重新裝回來),先在「設定 → 應用程式」移除 **Uninstall OneDrive Tool**,再重新雙擊 msi 即可(這個安裝包本身不是要長期保留的軟體,只是包裝移除動作用的載體)

> 這個 msi 是用 [WiX Toolset](https://wixtoolset.org/) 從同目錄的 [`Uninstall-OneDrive.ps1`](./Uninstall-OneDrive.ps1) 打包出來的,行為與方法 B 完全一致,只是省去手動開 PowerShell 的步驟。維護者如需重新編譯,見 [`Installer/build-msi.ps1`](./Installer/build-msi.ps1)。

### 方法 B:手動執行 PowerShell 腳本

見同目錄下的 [`Uninstall-OneDrive.ps1`](./Uninstall-OneDrive.ps1),已把以上步驟整合成一個腳本。**先切換到這個腳本所在的資料夾**,再用系統管理員身分執行:

```powershell
cd "路徑\到\Uninstall-Windows\OneDriveRemoval"
.\Uninstall-OneDrive.ps1
```

腳本內部會自己判斷目前是否為系統管理員權限,不是的話會自動跳出 UAC 提示重新啟動,**不需要**先另外開一個系統管理員 PowerShell 視窗再執行一次。

## 疑難排解(方法 B,手動執行腳本時)

| 錯誤訊息 | 原因 | 解法 |
|---|---|---|
| `.\Uninstall-OneDrive.ps1 : 無法辨識...詞彙是否為 Cmdlet...` | 目前所在目錄不是腳本所在的資料夾,`.\` 相對路徑找不到檔案 | 先 `cd` 到 `OneDriveRemoval` 資料夾,或改用完整路徑執行 |
| `因為這個系統上已停用指令碼執行...` | PowerShell 執行原則(Execution Policy)預設是 `Restricted`,擋掉所有 `.ps1` | 在同一個視窗先執行 `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force`,只影響當前視窗,關掉就恢復,不動系統設定 |
| 移除後檔案總管導覽窗格仍看得到 OneDrive 圖示 | 檔案總管行程快取了舊的登錄機碼內容 | 重新開機(腳本執行完會提示),或手動重啟檔案總管:工作管理員找到「Windows 檔案總管」→重新啟動 |

如果不想處理前兩個坑,直接用**方法 A 的 .msi** 即可,雙擊沒有這些問題。

## 執行後驗證清單

```powershell
Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue                                    # 應無輸出
Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive"                                              # 應為 False
Test-Path "$env:ProgramFiles\Microsoft OneDrive"                                              # 應為 False
Get-ScheduledTask -TaskName "OneDrive*" -ErrorAction SilentlyContinue                          # 應無輸出
Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OneDrive -ErrorAction SilentlyContinue                       # 應無輸出
```

全部確認乾淨後,**重新開機**讓變更(尤其是檔案總管導覽窗格圖示)完全生效。

## 注意事項

- 這個做法**不可逆的部分**是刪除安裝目錄與登錄機碼,但已用系統還原點做保險。
- **不會**自動刪除 `%USERPROFILE%\OneDrive` 資料夾裡的個人檔案,避免誤刪尚未備份的資料;確認不需要後請自行手動刪除。
- 如果之後又被 Windows Update 或 OEM 預載重新裝回 OneDrive,可重新執行同一支腳本(或重新雙擊 msi)移除。
- 此方法僅使用 OneDrive 內建的官方解除安裝參數與標準 Windows 登錄機碼/工作排程 API,不涉及任何第三方或來路不明的工具。

# 徹底解除安裝 Microsoft Edge(Windows 11)

紀錄實際排查與解決過程,含最終有效方法與失敗過的嘗試(供日後參考排錯)。

## 問題背景

Windows 11 把 Edge 當成系統元件保護,直接用 `setup.exe --uninstall --force-uninstall` 通常會被擋下。

## 失敗過的嘗試(僅供參考,不需要重做)

以下方法在本機測試**都無效**,原因是 `chrome\installer\util\shell_util.cc` 內部寫死了一層「sticky」保護,與下列因素**無關**:

| 嘗試方法 | 結果 |
|---|---|
| `setup.exe --uninstall --system-level --force-uninstall`(未提權) | 需要系統管理員權限,無效 |
| 同上,以系統管理員權限執行 | 被擋下,log 顯示 `Browser/WebView is sticky, uninstall not allowed.`,結束代碼 93 |
| 安裝並登記第三方瀏覽器(如三星瀏覽器)為預設 | 已正確登記於 `HKLM\SOFTWARE\Clients\StartMenuInternet`,仍被擋下 |
| 將登錄機碼 `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge` 的 `NoRemove` 從 `1` 改成 `0` | 只影響「設定」App 裡的解除安裝按鈕顯示,不影響 `setup.exe` 內部判斷,仍被擋下 |

## 有效解法

使用社群維護的 **[ShadowWhisperer/Remove-MS-Edge](https://github.com/ShadowWhisperer/Remove-MS-Edge)** 專案裡的 `Edge.bat`(只移除 Edge 本體,**不動 WebView2**,因為 Widgets、Outlook 新版等內建功能依賴 WebView2)。

該腳本會:
1. 下載一份經過 SHA256 雜湊驗證的修改版 `setup.exe`,繞過內部 sticky 檢查
2. 解鎖並移除 Edge 的 AppX 套件(直接操作 AppX 狀態資料庫)
3. 清除 Edge 相關的資料夾、服務、排程工作、登錄機碼殘留

### 執行前必做:建立系統還原點

這個工具會直接操作 Windows AppX 資料庫與多使用者登錄機碼,屬於較深層的系統變更。**務必先建立系統還原點**,萬一有問題可以直接還原:

```powershell
Enable-ComputerRestore -Drive "C:\"
Checkpoint-Computer -Description "Before-Edge-Removal-Tool" -RestorePointType "MODIFY_SETTINGS"
```

> 若最近 24 小時內已經建立過還原點,系統預設每 1440 分鐘只允許建立一次,這裡會顯示警告但不影響後續步驟,可以忽略繼續。

### 方法 A(推薦):直接安裝 .msi,雙擊執行

不需要裝 Git、不需要處理 PowerShell 執行原則、不需要貼指令。下載 [`dist/Uninstall-Edge.msi`](./dist/Uninstall-Edge.msi),**直接雙擊**:

1. 雙擊 `Uninstall-Edge.msi`
2. 跳出 UAC 提示,按「是」授權
3. 安裝程式會自動以系統管理員權限執行移除腳本(略過還原點的互動確認,無人值守模式)
4. 完成後,可在 `C:\Program Files\Uninstall-Edge-Tool\Uninstall-Edge.log` 查看完整執行紀錄,確認 Edge 是否移除成功
5. 想重跑一次,先在「設定 → 應用程式」移除 **Uninstall Edge Tool**,再重新雙擊 msi 即可(這個安裝包本身不是要長期保留的軟體,只是包裝移除動作用的載體)

> 這個 msi 是用 [WiX Toolset](https://wixtoolset.org/) 從同目錄的 [`Uninstall-Edge.ps1`](./Uninstall-Edge.ps1) 打包出來的,行為與方法 B 完全一致,只是省去手動開 PowerShell 的步驟。維護者如需重新編譯,見 [`installer/build-msi.ps1`](./installer/build-msi.ps1)。

### 方法 B:手動執行 PowerShell 腳本

見同目錄下的 [`Uninstall-Edge.ps1`](./Uninstall-Edge.ps1),已把以上步驟整合成一個腳本。**先切換到這個腳本所在的資料夾**,再用系統管理員身分執行:

```powershell
cd "路徑\到\Uninstall-Windows\EdgeRemoval"
.\Uninstall-Edge.ps1
```

腳本內部會自己判斷目前是否為系統管理員權限,不是的話會自動跳出 UAC 提示重新啟動,**不需要**先另外開一個系統管理員 PowerShell 視窗再執行一次。

## 疑難排解(方法 B,手動執行腳本時)

| 錯誤訊息 | 原因 | 解法 |
|---|---|---|
| `.\Uninstall-Edge.ps1 : 無法辨識...詞彙是否為 Cmdlet...` | 目前所在目錄不是腳本所在的資料夾,`.\` 相對路徑找不到檔案 | 先 `cd` 到 `EdgeRemoval` 資料夾,或改用完整路徑執行 |
| `因為這個系統上已停用指令碼執行...` | PowerShell 執行原則(Execution Policy)預設是 `Restricted`,擋掉所有 `.ps1` | 在同一個視窗先執行 `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force`,只影響當前視窗,關掉就恢復,不動系統設定 |

如果不想處理這兩個坑,直接用**方法 A 的 .msi** 即可,雙擊沒有這些問題。

## 執行後驗證清單

```powershell
Test-Path "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"   # 應為 False
Get-AppxPackage -AllUsers *MicrosoftEdge*                                  # 應無輸出
Get-Service edgeupdate, edgeupdatem -ErrorAction SilentlyContinue          # 應無輸出
Get-StartApps "*edge*"                                                     # 應無輸出
```

全部確認乾淨後,**重新開機**讓變更完全生效。

## 注意事項

- 這個做法**不可逆的部分**是刪除登錄機碼與檔案,但已用系統還原點做保險。
- WebView2 執行環境刻意保留,不要額外移除,否則可能影響其他內建 App。
- 如果之後 Windows Update 又把 Edge 裝回來,代表更新流程重新建立了相關套件,可重新執行同一支腳本移除。
- 此方法依賴第三方維護的開源工具,微軟未來版本更新可能讓此方法失效,需留意 [ShadowWhisperer/Remove-MS-Edge](https://github.com/ShadowWhisperer/Remove-MS-Edge) 是否有更新。

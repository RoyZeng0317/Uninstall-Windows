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

### 執行移除

見同目錄下的 [`Uninstall-Edge.ps1`](./Uninstall-Edge.ps1),已把以上步驟整合成一個腳本。用系統管理員身分執行:

```powershell
.\Uninstall-Edge.ps1
```

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

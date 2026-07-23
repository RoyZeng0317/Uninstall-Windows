# 徹底解除安裝 McAfee(控制台/設定 App 無法強制移除時)

紀錄實際排查與解決過程,含最終有效方法(供日後參考排錯)。

## 問題背景

McAfee 常見的無法移除狀況:「設定 → 應用程式」或「控制台 → 程式和功能」裡點「解除安裝」沒反應、卡住、或跳出錯誤訊息,原因通常是殘留的服務/驅動程式鎖住了檔案,或解除安裝程式本身損毀。

## 有效解法

不使用來路不明的「強制刪除登錄機碼/檔案」腳本(容易留下殘留、甚至傷到系統),而是用 **McAfee 官方自己提供的移除工具**:**McAfee Consumer Product Removal tool(MCPR.exe)**,這是 McAfee 官方針對「控制台移除不掉」這個情境專門提供的解法。

`Uninstall-McAfee.ps1` 把整個流程自動化:
1. 停用常見的 McAfee 程序(`mcshield`、`mfemms`、`McUICnt` 等),避免檔案被鎖住
2. 建立系統還原點
3. 從 McAfee 官方下載位址取得 `MCPR.exe`
4. **驗證數位簽章**(必須是有效簽章、簽署者為 McAfee)才會執行,避免下載連結遭竄改或中間人置換成惡意檔案
5. 執行 `MCPR.exe`,並在結束後檢查登錄機碼裡是否還有 McAfee 殘留項目

> **這一步無法完全自動化(靜默執行)**:MCPR.exe 一定會跳出官方的移除精靈視窗,需要手動點過(通常是「下一步」+ 圖片驗證碼)。實測新版 MCPR 已經拿掉舊版曾經支援的 `-s` 靜默安裝參數,所以坊間流傳的「完全靜默移除」做法目前多半對新版無效;硬是用舊版繞過,風險是版本太舊可能認不得新的 McAfee 產品組合,清得不乾淨。因此這裡選擇「自動化到只剩最後點幾下」,而不是假裝能做到全自動卻清不乾淨。

### 執行前必做:建立系統還原點

這個工具會移除系統服務、驅動程式與多使用者登錄機碼,屬於較深層的系統變更。**務必先建立系統還原點**,萬一有問題可以直接還原(腳本預設會自動建立):

```powershell
Enable-ComputerRestore -Drive "C:\"
Checkpoint-Computer -Description "Before-McAfee-Removal-Tool" -RestorePointType "MODIFY_SETTINGS"
```

> 若最近 24 小時內已經建立過還原點,系統預設每 1440 分鐘只允許建立一次,這裡會顯示警告但不影響後續步驟,可以忽略繼續。

### 方法 A(推薦):直接安裝 .msi,雙擊執行

不需要裝 Git、不需要處理 PowerShell 執行原則、不需要貼指令。下載 [`Uninstall-McAfee.msi`](https://github.com/RoyZeng0317/Uninstall-Windows/releases/download/mcafee-v1.0.0/Uninstall-McAfee.msi)(點擊連結會直接觸發瀏覽器下載,不會先跳到 GitHub 網頁預覽),**直接雙擊**:

1. 雙擊 `Uninstall-McAfee.msi`
2. 跳出 UAC 提示,按「是」授權
3. 安裝過程會自動執行移除腳本,接著會跳出 **McAfee 官方的移除精靈視窗**,依畫面指示點過去即可(這一步是 McAfee 自己的設計,無法跳過)
4. 完成後,可在 `C:\Program Files\Uninstall-McAfee-Tool\Uninstall-McAfee.log` 查看完整執行紀錄,確認 McAfee 是否移除成功
5. 想重跑一次,先在「設定 → 應用程式」移除 **Uninstall McAfee Tool**,再重新雙擊 msi 即可(這個安裝包本身不是要長期保留的軟體,只是包裝移除動作用的載體)

> 這個 msi 是用 [WiX Toolset](https://wixtoolset.org/) 從同目錄的 [`Uninstall-McAfee.ps1`](./Uninstall-McAfee.ps1) 打包出來的,行為與方法 B 完全一致,只是省去手動開 PowerShell 的步驟。維護者如需重新編譯,見 [`installer/build-msi.ps1`](./installer/build-msi.ps1)。

### 方法 B:手動執行 PowerShell 腳本

見同目錄下的 [`Uninstall-McAfee.ps1`](./Uninstall-McAfee.ps1),已把以上步驟整合成一個腳本。**先切換到這個腳本所在的資料夾**,再用系統管理員身分執行:

```powershell
cd "路徑\到\Uninstall-Windows\McAfee"
.\Uninstall-McAfee.ps1
```

腳本內部會自己判斷目前是否為系統管理員權限,不是的話會自動跳出 UAC 提示重新啟動,**不需要**先另外開一個系統管理員 PowerShell 視窗再執行一次。

## 疑難排解(方法 B,手動執行腳本時)

| 錯誤訊息 | 原因 | 解法 |
|---|---|---|
| `.\Uninstall-McAfee.ps1 : 無法辨識...詞彙是否為 Cmdlet...` | 目前所在目錄不是腳本所在的資料夾,`.\` 相對路徑找不到檔案 | 先 `cd` 到 `McAfee` 資料夾,或改用完整路徑執行 |
| `因為這個系統上已停用指令碼執行...` | PowerShell 執行原則(Execution Policy)預設是 `Restricted`,擋掉所有 `.ps1` | 在同一個視窗先執行 `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force`,只影響當前視窗,關掉就恢復,不動系統設定 |
| `下載的檔案簽章驗證失敗` | 下載到的 `MCPR.exe` 簽章無效或簽署者不是 McAfee(下載連結可能已失效或被竄改) | 不要繼續執行該檔案;到 [McAfee 官網](https://www.mcafee.com/support/?articleId=TS101331)確認目前最新的官方下載連結,更新腳本裡的網址 |
| MCPR 視窗跳出後沒有反應/卡住 | MCPR 本身在等待畫面上的操作(如圖片驗證碼) | 切到該視窗手動完成精靈畫面,這一步無法自動化 |

如果不想處理前兩個坑,直接用**方法 A 的 .msi** 即可,雙擊沒有這些問題(第三、四點是 MCPR 自身的行為,兩個方法都一樣會遇到)。

## 執行後驗證清單

```powershell
Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                  "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" |
    Where-Object { $_.DisplayName -match "McAfee" }                                          # 應無輸出

Get-Service | Where-Object { $_.DisplayName -match "McAfee" -or $_.Name -match "^mc|^mfe" }   # 應無輸出(或僅剩無關服務)

Get-Process | Where-Object { $_.ProcessName -match "^mc|^mfe" } -ErrorAction SilentlyContinue # 應無輸出
```

全部確認乾淨後,**重新開機**讓變更完全生效。

## 注意事項

- 這個做法**不可逆的部分**是移除服務、驅動程式與登錄機碼,但已用系統還原點做保險。
- 腳本下載回來的 `MCPR.exe` 會經過**數位簽章驗證**才會執行,不是來路不明的第三方工具。
- MCPR 精靈視窗的操作**無法完全自動化**,這是 McAfee 官方工具本身的限制,不是這個專案的 bug。
- 如果之後又重新裝回 McAfee(例如 OEM 預載、Windows Update 重新推送),可重新執行同一支腳本移除。
- 此方法依賴 McAfee 官方持續提供 `MCPR.exe` 於目前的下載位址,若 McAfee 未來更換網址或下線該工具,需要更新腳本裡的下載連結。

# Dual PC Profiles

完整設計見 [design.md](design.md)。

## 已確認的機器

- PC：`PC-DAMON-2609`，使用者 `user`，IP `192.168.16.85`
- NB：`NB-DAMON-2205`，使用者 `damon.liu`，IP `192.168.16.54`

IP 或帳號改變時先修改 [config.psd1](config.psd1)，再於兩台電腦重新執行安裝器。

## 前置條件

兩台電腦都需要：

- PowerShell 7
- AutoHotkey v2
- PowerToys，且 Mouse Without Borders 已完成配對
- OpenSSH Client 與 Server
- 同時登入 `config.psd1` 指定的本機使用者
- `192.168.16.*` 內網連線

PC 需要 Spacedesk Driver；NB 需要 Spacedesk Windows Viewer。請先在 Viewer 啟用：

- 自動連線到 `192.168.16.85`
- 自動重新連線
- 連線後全螢幕

首次安裝前，請先手動讓 Windows 記住：

- PC profile：PC 以 LG 為主螢幕，Spacedesk 為延伸螢幕。
- NB profile：NB 以 LG 為主螢幕，內建螢幕為延伸螢幕。
- mix profile：NB 僅使用內建螢幕。

## 安裝

安裝器必須在兩台電腦上分別以系統管理員 PowerShell 7 執行。

PC：

```powershell
cd C:\Users\user\Documents\pc_setup\dual-pc
.\install.ps1 -Role PC
```

NB 的專案路徑可不同：

```powershell
.\install.ps1 -Role NB
```

第一次執行會：

- 部署程式至 `C:\Program Files\DualPcProfiles`
- 建立互動式排程工作
- 建立專用 Ed25519 SSH 金鑰
- 建立 AutoHotkey 開機捷徑並啟動熱鍵
- 建立限定另一台電腦內網 IP 的 TCP 22 SSH 規則，不修改既有的一般 SSH 規則
- PC 記錄並停用 Spacedesk 原本過度寬鬆的入站規則，再建立只允許 NB IP 連入 TCP 28252 的規則

Mouse Without Borders 透過目前 PowerToys 安裝包隨附且簽署的 DSC module 與 `PowerToys.Settings.exe` 切換，不依賴 WinGet Configuration 或 Microsoft Store。

### 交換並授權公鑰

兩台電腦各自產生：

```text
%USERPROFILE%\.ssh\dual_pc_profiles_ed25519.pub
```

將 PC 的 `.pub` 安全複製到 NB，將 NB 的 `.pub` 安全複製到 PC。只交換 `.pub`，不得複製無副檔名的私鑰。

在 PC 授權 NB 公鑰：

```powershell
.\install.ps1 -Role PC -PeerPublicKeyPath C:\Temp\nb-dual-pc.pub
```

在 NB 授權 PC 公鑰：

```powershell
.\install.ps1 -Role NB -PeerPublicKeyPath C:\Temp\pc-dual-pc.pub
```

安裝器加入的 SSH key 只能從設定中的 peer 內網 IP 呼叫受限入口，不能取得一般 shell、轉送連接埠或配置 PTY。若帳號屬於 Administrators，Windows OpenSSH 會使用所有系統管理員共用的 `administrators_authorized_keys`；forced command 與來源 IP 限制仍會套用。

### 首次確認 SSH host key

PC 執行：

```powershell
ssh -i "$env:USERPROFILE\.ssh\dual_pc_profiles_ed25519" damon.liu@192.168.16.54 noop
```

NB 執行：

```powershell
ssh -i "$env:USERPROFILE\.ssh\dual_pc_profiles_ed25519" user@192.168.16.85 noop
```

核對 fingerprint 後接受 host key。受限入口應拒絕 `noop`，這是正常結果；目的只是安全寫入 `known_hosts`。

## 診斷

安裝後分別執行：

```powershell
.\diagnose.ps1
```

尚未安裝時可由原始碼指定角色檢查：

```powershell
.\diagnose.ps1 -Role PC
.\diagnose.ps1 -Role NB
```

任何檢查失敗都不應開始 profile 切換。PowerToys 或 Spacedesk 更新後也應重新診斷。

## 熱鍵

- `Ctrl+Alt+F9`：profile-PC
- `Ctrl+Alt+F10`：profile-mix
- `Ctrl+Alt+F12`：profile-NB
- 加上 `Shift`：強制重新套用並顯示 HDMI／鍵鼠提示

測試時也可直接執行：

```powershell
& 'C:\Program Files\DualPcProfiles\dual-pc.ps1' -Command Request -Profile mix
```

## IP 變更

只修改 [config.psd1](config.psd1)：

```powershell
PC.IP = '新的 PC IP'
NB.IP = '新的 NB IP'
```

實際檔案使用 PowerShell data file 語法，請修改對應 hashtable 中的 `IP` 值。修改後，在 PC 與 NB 都重新執行各自的 `install.ps1`；PC 的 Spacedesk 防火牆來源 IP 也會同步更新。

## 記錄與復原

執行狀態與最近 30 天記錄位於：

```text
%LOCALAPPDATA%\DualPcProfiles
```

切換失敗後不會自動 rollback。修正錯誤後使用 `Shift + profile 熱鍵` 強制重新套用。

## 卸載

在對應電腦以系統管理員 PowerShell 7 執行：

```powershell
.\uninstall.ps1 -Role PC
.\uninstall.ps1 -Role NB
```

加上 `-KeepLogs` 可保留記錄。卸載器會還原安裝前的 Spacedesk 防火牆規則，不會移除 PowerToys、Spacedesk、AutoHotkey 或日常 SSH 設定。

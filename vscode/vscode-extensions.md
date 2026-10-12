# VS Code Extensions

清單檔：`vscode/extensions.json`，用 `pwsh vscode/sync-vscode.ps1 -Extensions [-Prune]` 同步。所有 profile 共用 Default 的 settings，所以 theme 以 `settings.json` 的 `workbench.colorTheme`（JetBrains Darcula）為準，沒被選用的 theme／icon theme 不裝。不裝 Docker 相關套件。

`-Prune` 會移除清單沒列的 extension，所以 extension pack 與相依會一起帶進來的成員（例如 `ms-python.python` → `debugpy`、`vscode-pylance`、`vscode-python-envs`）也要列出來。

## Common

所有 profile 都裝。

| extension | 用途 |
|---|---|
| `anthropic.claude-code` | Claude Code（Ctrl+L、Ctrl+Alt+I／K） |
| `openai.chatgpt` | Codex（Ctrl+Alt+L、Shift+Alt+K） |
| `openai.codex-audio` | Codex 語音（chatgpt 相依） |
| `mhutchie.git-graph` | Git Graph |
| `ms-vscode-remote.remote-containers` | Dev Containers |
| `ms-vscode-remote.remote-ssh` | Remote SSH |
| `ms-vscode-remote.remote-ssh-edit` | Remote SSH 編輯 ssh config（remote-ssh 相依） |
| `ms-vscode-remote.remote-wsl` | WSL |
| `ms-vscode.remote-explorer` | Remote Explorer（remote-ssh pack 成員） |
| `shd101wyy.markdown-preview-enhanced` | Markdown 預覽（`settings.json` 有設定它） |
| `yzhang.markdown-all-in-one` | Markdown 編輯（Alt+B／I／M） |
| `johnpapa.vscode-peacock` | 視窗配色 |
| `ms-vscode.powershell` | PowerShell 編輯、debugging 與 PSScriptAnalyzer |
| `iliazeus.vscode-ansi` | ANSI log 上色 |
| `naumovs.color-highlight` | 色碼預覽 |


## Default

新視窗預設值。只放寫文件、看資料需要的套件。Common 之外：

| extension | 用途 |
|---|---|
| `anan.jetbrains-darcula-theme` | color theme |
| `redhat.vscode-yaml` | YAML |

## Python

由原 Default 複製，for Python Development。Common 之外：

| extension | 用途 |
|---|---|
| `anan.jetbrains-darcula-theme` | color theme |
| `sirtori.indenticator` | 縮排範圍提示 |
| `shardulm94.trailing-spaces` | 行尾空白 |
| `janisdd.vscode-edit-csv` | CSV 表格編輯 |
| `ms-python.python` | Python |
| `charliermarsh.ruff` | Python lint、format 與 import 排序 |
| `ms-python.vscode-pylance` | Pylance（python 相依） |
| `ms-python.debugpy` | Python debugger（python 相依） |
| `ms-python.vscode-python-envs` | Python 環境（python 相依） |

## .NET

for .Net(C#) Development。Common 之外：

| extension | 用途 |
|---|---|
| `anan.jetbrains-darcula-theme` | color theme |
| `ms-dotnettools.csharp` | C# |
| `ms-dotnettools.vscode-dotnet-runtime` | .NET runtime（csharp 相依） |
| `patcx.vscode-nuget-gallery` | NuGet |
| `dotjoshjohnson.xml` | XML（csproj、xaml） |

## Flutter

For Flutter Development。用 Catppuccin，不用 Darcula。Common 之外：

| extension | 用途 |
|---|---|
| `catppuccin.catppuccin-vsc` | color theme |
| `catppuccin.catppuccin-vsc-icons` | icon theme |
| `dart-code.dart-code` | Dart |
| `dart-code.flutter` | Flutter |
| `jeroen-meijer.pubspec-assist` | pubspec 加套件 |
| `usernamehw.errorlens` | 行內顯示錯誤 |

settings 是所有 profile 共用的，所以 theme 寫在 idt-siteeye workspace 的 `.vscode/settings.json`：

```json
"workbench.colorTheme": "Catppuccin Mocha",
"workbench.iconTheme": "catppuccin-mocha"
```

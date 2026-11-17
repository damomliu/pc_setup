# 以 SSHFS-Win（\\sshfs.kr\<host>，key 認證）將 SSH host 的遠端 / 掛載成磁碟機代號（遠端 /a/b 對應 X:\a\b），供 Yazi（Herdr Prefix, Y）瀏覽遠端檔案。
# 用法：sshfs-mount.ps1 <Host> [-Drive X] | -Unmount <X: | Host> | -List
# 注意：必須存成 UTF-8 with BOM，否則 Windows PowerShell 5.1 會以 cp950 解析而壞掉。
# 部署位置：%APPDATA%\herdr\sshfs-mount.ps1；需先安裝 WinFsp 與 SSHFS-Win。
param(
    [Parameter(Position = 0)][string]$HostName,
    [string]$Drive,
    [string]$Unmount,
    [switch]$List
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

function Fail {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
    exit 1
}
# 回傳 @{ Drive = 'Z:'; Remote = '\\sshfs.k\nb' } 清單，只含 sshfs 的 mapping
function Get-SshfsMappings {
    $result = @()
    foreach ($line in (net use 2>$null)) {
        if ($line -match '([A-Za-z]:)\s+(\\\\sshfs\S*)') {
            $result += [pscustomobject]@{ Drive = $Matches[1].ToUpper(); Remote = $Matches[2] }
        }
    }
    return $result
}

if ($List) {
    $maps = Get-SshfsMappings
    if (!$maps) { Write-Output '沒有 sshfs 掛載'; exit 0 }
    $maps | ForEach-Object { '{0}  {1}' -f $_.Drive, $_.Remote }
    exit 0
}

if ($Unmount) {
    $target = $Unmount
    if ($target -notmatch '^[A-Za-z]:?$') {
        $found = Get-SshfsMappings | Where-Object { $_.Remote -match ('^\\\\sshfs(\.[a-z]+)?\\' + [regex]::Escape($Unmount) + '(\\|$)') } | Select-Object -First 1
        if (!$found) { Fail "找不到 host 的掛載：$Unmount" }
        $target = $found.Drive
    }
    $target = $target.TrimEnd(':').ToUpper() + ':'
    net use $target /delete /y
    if ($LASTEXITCODE -ne 0) { Fail "卸載 $target 失敗" }
    exit 0
}

if (!$HostName) { Fail '用法：sshfs-mount.ps1 <Host> [-Drive X] | -Unmount <X: | Host> | -List' }
if (!(Test-Path "$env:ProgramFiles\SSHFS-Win") -and !(Test-Path "${env:ProgramFiles(x86)}\SSHFS-Win")) {
    Fail '找不到 SSHFS-Win，請先安裝：winget install --id WinFsp.WinFsp -e 與 winget install --id SSHFS-Win.SSHFS-Win -e'
}

$unc = '\\sshfs.kr\' + $HostName
$existing = Get-SshfsMappings | Where-Object { $_.Remote -match ('^\\\\sshfs(\.[a-z]+)?\\' + [regex]::Escape($HostName) + '(\\|$)') } | Select-Object -First 1
if ($existing) {
    if ($existing.Remote -ne $unc) { Fail "$($existing.Drive) 已掛載為 $($existing.Remote)（非 $unc），請先 sshfs-mount.ps1 -Unmount $($existing.Drive)" }
    Write-Output "已掛載：$($existing.Drive)  $($existing.Remote)"
    exit 0
}

if ($Drive) {
    $letter = $Drive.TrimEnd(':').ToUpper()
} else {
    $used = [IO.DriveInfo]::GetDrives().Name | ForEach-Object { $_.Substring(0, 1).ToUpper() }
    $used += (Get-SshfsMappings | ForEach-Object { $_.Drive.Substring(0, 1) })
    $letter = [char[]](90..68) | Where-Object { $used -notcontains [string]$_ } | Select-Object -First 1
    if (!$letter) { Fail '沒有可用的磁碟機代號' }
}
$output = net use "${letter}:" $unc 2>&1
if ($LASTEXITCODE -ne 0) { Fail ("掛載失敗：net use ${letter}: $unc`n" + ($output -join "`n")) }
Write-Output "已掛載：${letter}:  $unc"

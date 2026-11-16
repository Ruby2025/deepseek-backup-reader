@echo off
rem DeepSeek backup renamer for Windows. Put this file next to your backup folders and double-click it.
setlocal
set "DS_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText($env:DS_SELF,[Text.Encoding]::UTF8); $m='#PS'+'START'; Invoke-Expression $t.Substring($t.LastIndexOf($m))"
echo.
pause
exit /b
#PSSTART
# DeepSeek 备份重命名（Windows 版）：把 chat_sessions 里以 id 命名的文件，按 chat_session_index.json 的标题改名。
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $env:DS_SELF
$IndexName = 'chat_session_index.json'
$MapName = '重命名对照表.csv'
$Utf8Bom = New-Object System.Text.UTF8Encoding $true
$Reserved = @('CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9','LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9')

function Clean([string]$title) {
    $t = ([string]$title).Normalize([System.Text.NormalizationForm]::FormC)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $t.ToCharArray()) {
        if (([int]$c -lt 32) -or ('\/:*?"<>|'.IndexOf($c) -ge 0)) { [void]$sb.Append('_') } else { [void]$sb.Append($c) }
    }
    $t = $sb.ToString().Trim().TrimStart('.').Trim()
    if ($t.Length -gt 80) { $t = $t.Substring(0, 80) }
    $t = $t.TrimEnd(' ', '.')
    if ($t -eq '') { $t = '未命名对话' }
    if ($Reserved -contains $t.ToUpperInvariant()) { $t = '_' + $t }
    return $t
}
function Key([string]$name) { return $name.Normalize([System.Text.NormalizationForm]::FormC).ToLowerInvariant() }
function Iso($v) {
    if ($v -is [DateTime]) { return $v.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
    if ($null -eq $v) { return '' }
    return [string]$v
}
function Stamp([string]$s) {
    if ($s.Length -ge 16) { return $s.Substring(0, 10) + ' ' + $s.Substring(11, 2) + $s.Substring(14, 2) }
    if ($s.Length -ge 10) { return $s.Substring(0, 10) }
    return $s
}
function CsvCell([string]$s) {
    if ($s -match '[",\r\n]') { return '"' + $s.Replace('"', '""') + '"' }
    return $s
}
function IsBackup([string]$p) {
    return (Test-Path -LiteralPath (Join-Path $p $IndexName) -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $p 'chat_sessions') -PathType Container)
}

function Rename-Backup([string]$folder) {
    $parsed = ConvertFrom-Json ([System.IO.File]::ReadAllText((Join-Path $folder $IndexName), [System.Text.Encoding]::UTF8))
    $index = @($parsed | ForEach-Object { $_ })
    $cs = Join-Path $folder 'chat_sessions'
    $existing = @{}
    foreach ($n in [System.IO.Directory]::GetFileSystemEntries($cs)) { $existing[(Key ([System.IO.Path]::GetFileName($n)))] = $true }

    $rows = @{}
    $mapPath = Join-Path $folder $MapName
    $hadMap = Test-Path -LiteralPath $mapPath
    if ($hadMap) {
        $first = $true
        foreach ($r in (Import-Csv -LiteralPath $mapPath -Encoding UTF8 -Header 'id', 'title', 'file', 'files', 'created', 'updated')) {
            if ($first) { $first = $false; continue }
            if ($r.id) { $rows[$r.id] = @([string]$r.id, [string]$r.title, [string]$r.file, [string]$r.files, [string]$r.created, [string]$r.updated) }
        }
    }

    $dup = @{}
    foreach ($x in $index) { $k = Key (Clean $x.title); $dup[$k] = 1 + [int]$dup[$k] }
    $used = @{}
    foreach ($r in $rows.Values) { if ($r[2].EndsWith('.json')) { $used[(Key $r[2].Substring(0, $r[2].Length - 5))] = $true } }

    $renamed = 0
    foreach ($x in $index) {
        $sid = [string]$x.id
        $srcJson = Join-Path $cs ($sid + '.json')
        $srcDir = Join-Path $cs ($sid + '_files')
        $hasJson = Test-Path -LiteralPath $srcJson -PathType Leaf
        $hasDir = Test-Path -LiteralPath $srcDir -PathType Container
        if (-not $hasJson -and -not $hasDir) { continue }
        $created = Iso $x.inserted_at
        if ($rows.ContainsKey($sid) -and $rows[$sid][2].EndsWith('.json')) {
            $base = $rows[$sid][2].Substring(0, $rows[$sid][2].Length - 5)      # 之前已经定过名字，沿用
        } else {
            $base = Clean $x.title
            $isDup = $dup[(Key $base)] -gt 1
            if ($isDup) { $base = $base + ' (' + (Stamp $created) + ')' }
            $taken = { param($b) $used.ContainsKey((Key $b)) -or $existing.ContainsKey((Key ($b + '.json'))) -or $existing.ContainsKey((Key ($b + '_files'))) }
            if ((& $taken $base) -and -not $isDup) { $base = $base + ' (' + (Stamp $created) + ')' }
            if (& $taken $base) { $base = $base + ' [' + $sid.Substring(0, [Math]::Min(8, $sid.Length)) + ']' }
        }
        $used[(Key $base)] = $true
        $dstJson = Join-Path $cs ($base + '.json')
        $dstDir = Join-Path $cs ($base + '_files')
        $filesName = ''
        if ($rows.ContainsKey($sid)) { $filesName = $rows[$sid][3] }
        if ($hasJson) {
            if (Test-Path -LiteralPath $dstJson) { Write-Host ('  跳过（目标已存在）：' + $base + '.json'); continue }
            [System.IO.File]::Move($srcJson, $dstJson)
            $existing[(Key ($base + '.json'))] = $true
            $renamed++
        }
        if ($hasDir) {
            if (Test-Path -LiteralPath $dstDir) { Write-Host ('  跳过（目标已存在）：' + $base + '_files') }
            else {
                [System.IO.Directory]::Move($srcDir, $dstDir)
                $existing[(Key ($base + '_files'))] = $true
                $filesName = $base + '_files'
            }
        }
        $rows[$sid] = @($sid, [string]$x.title, ($base + '.json'), $filesName, $created, (Iso $x.updated_at))
    }

    if ($renamed -gt 0 -or -not $hadMap) {
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('id,标题,新文件名,附件文件夹,创建时间,更新时间')
        $done = @{}
        $order = New-Object System.Collections.Generic.List[string]
        foreach ($x in $index) { $i = [string]$x.id; if ($rows.ContainsKey($i) -and -not $done.ContainsKey($i)) { $order.Add($i); $done[$i] = $true } }
        foreach ($i in $rows.Keys) { if (-not $done.ContainsKey($i)) { $order.Add($i); $done[$i] = $true } }
        foreach ($i in $order) { $lines.Add((($rows[$i] | ForEach-Object { CsvCell $_ }) -join ',')) }
        [System.IO.File]::WriteAllText($mapPath, (($lines -join "`r`n") + "`r`n"), $Utf8Bom)
    }
    return @($renamed, $index.Count)
}

$folders = New-Object System.Collections.Generic.List[string]
if (IsBackup $Root) { $folders.Add($Root) }
foreach ($d in ([System.IO.Directory]::GetDirectories($Root) | Sort-Object)) {
    if (-not ([System.IO.Path]::GetFileName($d)).StartsWith('.') -and (IsBackup $d)) { $folders.Add($d) }
}
if ($folders.Count -eq 0) { Write-Host '这里没有找到 DeepSeek 备份文件夹（需要包含 chat_session_index.json 和 chat_sessions）。' }
$total = 0
foreach ($p in $folders) {
    $name = [System.IO.Path]::GetFileName($p)
    try { $r = Rename-Backup $p }
    catch { Write-Host ('× ' + $name + '：出错了 —— ' + $_.Exception.Message); continue }
    $total += $r[0]
    $tail = ''
    if ($r[0] -eq 0) { $tail = '（已经全部改过名）' }
    Write-Host ('√ ' + $name + '：共 ' + $r[1] + ' 个对话，本次重命名 ' + $r[0] + ' 个' + $tail)
}
Write-Host ''
Write-Host ('完成，本次一共重命名 ' + $total + ' 个对话。对照表在每个备份文件夹里的「' + $MapName + '」。')

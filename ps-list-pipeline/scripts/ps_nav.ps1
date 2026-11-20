# ps_nav.ps1 v2 -- 纯 PowerShell 把 App 导航到「搜索结果 → 商品」页（零 Python）
# 用法：
#   .\ps_nav.ps1 -App dewu -Keyword Nike
#   .\ps_nav.ps1 -App xhs  -Keyword adidas
#   .\ps_nav.ps1 -App dy   -Keyword ai
#
# 说明：关键词只能 ASCII（adb input text 限制）。中文请手动搜好后直接用 ps_collect.ps1。

param(
    [Parameter(Mandatory = $true)][ValidateSet('dewu', 'xhs', 'dy')][string]$App,
    [Parameter(Mandatory = $true)][string]$Keyword,
    [string]$AdbPath = ''
)

$ErrorActionPreference = 'Stop'
if ($Keyword -notmatch '^[A-Za-z0-9 _.-]+$') {
    throw '自动输入只支持字母、数字、空格、点、横线和下划线；其他关键词请手动搜索后使用 -NoNav'
}

function Find-Adb {
    if ($AdbPath -and (Test-Path $AdbPath)) { return $AdbPath }
    if ($env:ADB_PATH -and (Test-Path $env:ADB_PATH)) { return $env:ADB_PATH }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw '找不到 adb'
}
$script:ADB = Find-Adb

function Adb {
    param([string[]]$A)
    $ErrorActionPreference='Continue' # PS 5.1 wraps native stderr even on exit 0.
    $result=((& $script:ADB @A 2>&1) | ForEach-Object { "$_" }) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "ADB 执行失败：$result" }
    return $result
}
function Tap([int]$x, [int]$y) { $null = Adb @('shell', "input tap $x $y") }
function TypeText([string]$s) { $null = Adb @('shell', "input text `"$s`"") }
function PressEnter { $null = Adb @('shell', 'input keyevent 66') }
function Fg { return ((Adb @('shell', 'dumpsys window')) -split "`n" | Where-Object { $_ -match 'mCurrentFocus=' }) }

function GetNodes {
    $xml = ''
    for ($i = 0; $i -lt 3; $i++) {
        $null = Adb @('shell', 'uiautomator dump /sdcard/_ui.xml')
        $xml = Adb @('shell', 'cat /sdcard/_ui.xml')
        if ($xml -and $xml.Contains('<hierarchy')) { break }
        Start-Sleep -Milliseconds 700
    }
    $list = @()
    if (-not $xml) { return $list }
    foreach ($nm in [regex]::Matches($xml, '<node[^>]*>')) {
        $tag = $nm.Value
        $t = ''; $d = ''; $c = ''
        $tm = [regex]::Match($tag, 'text="([^"]*)"'); if ($tm.Success) { $t = $tm.Groups[1].Value }
        $dm = [regex]::Match($tag, 'content-desc="([^"]*)"'); if ($dm.Success) { $d = $dm.Groups[1].Value }
        $cm = [regex]::Match($tag, 'class="([^"]*)"'); if ($cm.Success) { $c = $cm.Groups[1].Value }
        $bm = [regex]::Match($tag, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
        if (-not $bm.Success) { continue }
        $list += [pscustomobject]@{
            text = $t.Replace([string][char]0x200b, '').Trim()
            desc = $d.Replace([string][char]0x200b, '').Trim()
            cls  = $c
            x1   = [int]$bm.Groups[1].Value; y1 = [int]$bm.Groups[2].Value
            x2   = [int]$bm.Groups[3].Value; y2 = [int]$bm.Groups[4].Value
        }
    }
    return $list
}

function FindNode {
    param($Nodes, [string]$Match, [int]$MaxY = 9999, [int]$MinWidth = 0)
    foreach ($n in $Nodes) {
        if ($n.y1 -gt $MaxY) { continue }
        if (($n.x2 - $n.x1) -lt $MinWidth) { continue }
        $hay = "$($n.text) $($n.desc)"
        if ($hay.Contains($Match)) { return $n }
    }
    return $null
}

function FindEditText {
    param($Nodes, [int]$MaxY = 9999)
    foreach ($n in $Nodes) {
        if ($n.y1 -gt $MaxY) { continue }
        if ($n.cls -and $n.cls.Contains('EditText')) { return $n }
    }
    return $null
}

function TapNode($n) {
    if ($null -eq $n) { return $false }
    Tap ([int](($n.x1 + $n.x2) / 2)) ([int](($n.y1 + $n.y2) / 2))
    return $true
}

function ClearAndType([string]$kw) {
    $null = Adb @('shell', 'input keyevent KEYCODE_MOVE_END')
    for ($i = 0; $i -lt 40; $i++) { $null = Adb @('shell', 'input keyevent 67') }
    TypeText $kw
    Start-Sleep -Milliseconds 900
    PressEnter
    Start-Sleep -Seconds 5
}

switch ($App) {
    'dewu' {
        Write-Output '[得物] 启动…'
        $null = Adb @('shell', 'am force-stop com.shizhuang.duapp')
        Start-Sleep -Milliseconds 800
        $null = Adb @('shell', 'monkey -p com.shizhuang.duapp -c android.intent.category.LAUNCHER 1')
        Start-Sleep -Seconds 4.5
        $ns = GetNodes
        # The home-page search button and input area have different actions.
        # Open the input area instead of submitting the suggested query.
        Tap 450 220
        Start-Sleep -Seconds 2.5
        $ns = GetNodes
        $box = FindEditText $ns 340
        if (-not $box) { throw '得物未打开搜索输入框，请手动搜索后用 -NoNav' }
        $null = TapNode $box
        Start-Sleep -Milliseconds 1200
        ClearAndType $Keyword
        $ns = GetNodes
        $tab = FindNode $ns '商品' 460
        if ($tab) { $null = TapNode $tab; Start-Sleep -Seconds 3.5 }
    }
    'xhs' {
        Write-Output '[小红书] 启动…'
        $null = Adb @('shell', 'am force-stop com.xingin.xhs')
        Start-Sleep -Milliseconds 800
        $null = Adb @('shell', 'monkey -p com.xingin.xhs -c android.intent.category.LAUNCHER 1')
        Start-Sleep -Seconds 5
        $ns = GetNodes
        $entry = FindNode $ns '搜索' 340
        if ($entry) { $null = TapNode $entry; Start-Sleep -Seconds 2.5 }
        $ns = GetNodes
        $box = FindEditText $ns 340
        if (-not $box) { $box = FindNode $ns '搜索' 340 180 }
        $null = TapNode $box
        Start-Sleep -Milliseconds 1200
        ClearAndType $Keyword
        $ns = GetNodes
        $tab = FindNode $ns '商品' 500
        if ($tab) { $null = TapNode $tab; Start-Sleep -Seconds 3.5 }
    }
    'dy' {
        Write-Output '[抖音] 启动…'
        $null = Adb @('shell', 'am force-stop com.ss.android.ugc.aweme')
        Start-Sleep -Milliseconds 800
        $null = Adb @('shell', 'monkey -p com.ss.android.ugc.aweme -c android.intent.category.LAUNCHER 1')
        Start-Sleep -Seconds 6
        $ns = GetNodes
        $mall = FindNode $ns '商城' 300
        if ($mall) { $null = TapNode $mall; Start-Sleep -Seconds 3.5 }
        $ns = GetNodes
        $entry = FindNode $ns '搜索' 420
        if ($entry) { $null = TapNode $entry; Start-Sleep -Seconds 2.5 }
        $ns = GetNodes
        $box = FindEditText $ns 420
        if (-not $box) { $box = FindNode $ns '搜索' 420 180 }
        $null = TapNode $box
        Start-Sleep -Milliseconds 1200
        ClearAndType $Keyword
        $ns = GetNodes
        $tab = FindNode $ns '商品' 460
        if ($tab) { $null = TapNode $tab; Start-Sleep -Seconds 4 }
        $ns = GetNodes
        $grid = FindNode $ns '单列' 700
        if ($grid) {
            Write-Output '  切到双列…'
            $null = TapNode $grid
            Start-Sleep -Seconds 3
        }
    }
}

$verified = @(GetNodes | Where-Object { $_.y1 -lt 480 -and ($_.text -eq $Keyword -or $_.desc -eq $Keyword) })
if (-not $verified.Count) { throw '搜索词未出现在结果页顶部，已停止；请手动搜索后使用 -NoNav' }
Write-Output "前台: $(Fg)"
Write-Output '导航完成'

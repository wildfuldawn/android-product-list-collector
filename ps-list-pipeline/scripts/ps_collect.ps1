# ps_collect.ps1 v2 -- 纯 PowerShell 采集商品卡（零 Python）
# 依赖：adb（手机调试）+ Windows 自带 .NET。不需要 Python / Excel / Office。
#
# 用法（先让 App 停在「商品」结果页）：
#   .\ps_collect.ps1 -App dewu -Limit 3 -Csv dewu.csv -ImageDir imgs\dewu
#
# 产出 CSV：序号 / 应用 / 标题 / 价格 / 已售 / 首图

param(
    [Parameter(Mandatory = $true)][ValidateSet('dewu', 'xhs', 'dy')][string]$App,
    [int]$Limit = 3,
    [string]$Csv = '',
    [string]$ImageDir = '',
    [string]$AdbPath = '',
    [switch]$KeepScreen
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing | Out-Null

function Find-Adb {
    if ($AdbPath -and (Test-Path $AdbPath)) { return $AdbPath }
    if ($env:ADB_PATH -and (Test-Path $env:ADB_PATH)) { return $env:ADB_PATH }
    $built = 'D:\Codex\pachong\android-touch-script\tools\android-sdk\platform-tools\adb.exe'
    if (Test-Path $built) { return $built }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw '找不到 adb：请用 -AdbPath 指定，或设置环境变量 ADB_PATH'
}
$script:ADB = Find-Adb

function Adb {
    param([string[]]$ArgsList)
    return ((& $script:ADB @ArgsList 2>&1) | ForEach-Object { "$_" }) -join "`n"
}

function AdbBytes {
    param([string[]]$ArgsList)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:ADB
    $psi.Arguments = ($ArgsList -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $ms = New-Object System.IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms)
    $p.WaitForExit()
    return $ms.ToArray()
}

$dev = Adb @('devices')
if ($dev -notmatch '\tdevice') { throw '手机没连上：先 adb connect <IP>:<端口>' }

$cfg = @{
    dewu = @{
        name = '得物'; headerY = 560; colLeft = @(51, 585); colRight = @(687, 1221)
        minTitleH = 55; titleMin = 10; titleMax = 130; imageGap = 64
        skip = @('¥', '人付款', '人加购', '包邮', '关注', '榜', '降价')
        quoteAware = $false
    }
    xhs = @{
        name = '小红书'; headerY = 900; colLeft = @(52, 593); colRight = @(679, 1220)
        minTitleH = 0; titleMin = 8; titleMax = 120; imageGap = 8
        skip = @('¥', '已售', '加购', '立减', '好评率', '券后', '关注后', '满', '“', '”',
                 '销量', '旗舰店', '专营店', '专卖店', '官方店', '退货包运费')
        quoteAware = $true
    }
    dy = @{
        name = '抖音'; headerY = 560; colLeft = @(43, 594); colRight = @(671, 1222)
        minTitleH = 0; titleMin = 8; titleMax = 130; imageGap = 8
        skip = @('¥', '已售', '人看过', '人付款', '回头客', '好评', '粉丝', '官方正品', '直播')
        quoteAware = $false
    }
}[$App]

if (-not $Csv) { $Csv = "$App.csv" }
if (-not $ImageDir) { $ImageDir = "imgs\$App" }
New-Item -ItemType Directory -Force -Path $ImageDir | Out-Null
$workDir = (Get-Location).Path

Write-Output "[1/4] dump 界面…"
$xmlText = ''
for ($i = 0; $i -lt 3; $i++) {
    $null = Adb @('shell', 'uiautomator dump /sdcard/_ui.xml')
    $xmlText = Adb @('shell', 'cat /sdcard/_ui.xml')
    if ($xmlText -and $xmlText.Contains('<hierarchy')) { break }
    Start-Sleep -Milliseconds 800
}
if (-not $xmlText) { throw 'uiautomator dump 失败（App 可能不在前台）' }

Write-Output "[2/4] 解析…"
$all = New-Object System.Collections.ArrayList
foreach ($m in [regex]::Matches($xmlText, '<node[^>]*>')) {
    $tag = $m.Value
    $t = ''
    $tm = [regex]::Match($tag, 'text="([^"]*)"')
    if ($tm.Success) { $t = $tm.Groups[1].Value }
    if (-not $t) {
        $dm = [regex]::Match($tag, 'content-desc="([^"]*)"')
        if ($dm.Success) { $t = $dm.Groups[1].Value }
    }
    if (-not $t) { continue }
    $bm = [regex]::Match($tag, 'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
    if (-not $bm.Success) { continue }
    $x1 = [int]$bm.Groups[1].Value; $y1 = [int]$bm.Groups[2].Value
    $x2 = [int]$bm.Groups[3].Value; $y2 = [int]$bm.Groups[4].Value

    $t = $t.Replace([string][char]0x200b, '').Replace([string][char]0x200c, '').Replace([string][char]0x200d, '')
    $t = $t.Replace("`r", ' ').Replace("`n", ' ').Trim()
    if (-not $t) { continue }
    $null = $all.Add([pscustomobject]@{
            t = $t; x1 = $x1; y1 = $y1; x2 = $x2; y2 = $y2
            h = ($y2 - $y1); w = ($x2 - $x1); cx = [int](($x1 + $x2) / 2)
        })
}
$nodes = $all.ToArray()
Write-Output "  节点 $($nodes.Count) 个"

$cards = @()
foreach ($n in $nodes) {
    if ($n.y1 -lt $cfg.headerY) { continue }
    if ($n.w -lt 280) { continue }
    if ($n.h -lt $cfg.minTitleH) { continue }
    if ($n.t.Length -lt $cfg.titleMin -or $n.t.Length -gt $cfg.titleMax) { continue }
    $bad = $false
    foreach ($w in $cfg.skip) { if ($n.t.Contains($w)) { $bad = $true; break } }
    if ($bad) { continue }
    $cards += $n
}
$seen = @{}
$uniq = @()
foreach ($c in ($cards | Sort-Object y1, x1)) {
    if ($seen.ContainsKey($c.t)) { continue }
    $seen[$c.t] = 1
    $uniq += $c
}
Write-Output "  标题候选 $($uniq.Count) 个"
if ($uniq.Count -eq 0) { throw '没解析到商品卡（确认停在「商品」结果页）' }
$cards = $uniq | Select-Object -First $Limit

Write-Output "[3/4] 截图…"
$shotRel = Join-Path $ImageDir '_screen.png'
$shotAbs = Join-Path $workDir $shotRel
$bytes = AdbBytes @('exec-out', 'screencap -p')
if ($bytes.Length -lt 8 -or $bytes[0] -ne 0x89) { throw '截图失败' }
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $shotAbs) | Out-Null
[System.IO.File]::WriteAllBytes($shotAbs, $bytes)
$img = [System.Drawing.Image]::FromFile($shotAbs)
Write-Output ("  截图 {0}x{1}" -f $img.Width, $img.Height)

Write-Output "[4/4] 裁图 + 提取字段…"
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$rows = @()
$idx = 0
foreach ($c in $cards) {
    $idx++
    $isLeft = $c.cx -lt 636
    $col = if ($isLeft) { $cfg.colLeft } else { $cfg.colRight }
    $cw = $col[1] - $col[0]

    $bottom = $c.y1 - $cfg.imageGap
    if ($cfg.quoteAware) {
        $quote = $nodes | Where-Object {
            $_.y2 -le $c.y1 -and ($c.y1 - $_.y2) -lt 140 -and
            (($_.cx -lt 636) -eq $isLeft) -and
            ($_.t.StartsWith([string][char]0x201C) -or $_.t.EndsWith([string][char]0x201D))
        } | Sort-Object y2 -Descending | Select-Object -First 1
        if ($quote) { $bottom = $quote.y2 - 4 }
    }
    $top = $bottom - $cw
    if ($top -lt $cfg.headerY) { $top = $cfg.headerY }
    $height = $bottom - $top

    $outRel = Join-Path $ImageDir ("{0:D3}.jpg" -f $idx)
    $outAbs = Join-Path $workDir $outRel
    $firstImg = ''
    if ($height -gt 120 -and $bottom -le $img.Height -and $top -ge 0) {
        $rect = New-Object System.Drawing.Rectangle($col[0], $top, $cw, $height)
        $bmp = New-Object System.Drawing.Bitmap($cw, $height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $cw, $height)), $rect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]88)
        $bmp.Save($outAbs, $codec, $ep)
        $bmp.Dispose()
        $firstImg = $outAbs
    } else {
        Write-Output "  #$idx 图片区域异常（top=$top bottom=$bottom），跳过图片"
    }

    $price = ''
    $sameCol = $nodes | Where-Object {
        (($_.cx -lt 636) -eq $isLeft) -and $_.y1 -gt $c.y1 -and ($_.y1 - $c.y1) -le 260
    }
    $nums = @()
    foreach ($n in $sameCol) {
        foreach ($mm in [regex]::Matches($n.t, '[¥￥]\s*([0-9]+(\.[0-9]+)?)')) {
            $nums += [double]$mm.Groups[1].Value
        }
    }
    if ($nums.Count -gt 0) { $price = '¥' + ($nums | Measure-Object -Minimum).Minimum }

    $sold = ''
    foreach ($n in $sameCol) {
        $mm = [regex]::Match($n.t, '已售\s*([0-9.]+(万|\+)*)')
        if (-not $mm.Success) { $mm = [regex]::Match($n.t, '([0-9.]+(万|\+)*)\s*人付款') }
        if ($mm.Success) { $sold = $mm.Groups[1].Value; break }
    }

    $rows += [pscustomobject]@{
        序号 = $idx
        应用 = $cfg.name
        标题 = $c.t
        价格 = $price
        已售 = $sold
        首图 = $firstImg
    }
    Write-Output ("  {0}  {1,-8} {2,-8} {3}" -f $idx, $price, $sold, $c.t.Substring(0, [Math]::Min(30, $c.t.Length)))
}
$img.Dispose()
if (-not $KeepScreen) { Remove-Item -LiteralPath $shotAbs -Force -ErrorAction SilentlyContinue }

$rows | Export-Csv -LiteralPath $Csv -NoTypeInformation -Encoding UTF8
$withImg = ($rows | Where-Object { $_.首图 }).Count
Write-Output ""
Write-Output "完成：$($rows.Count) 条（带图 $withImg）-> $Csv"

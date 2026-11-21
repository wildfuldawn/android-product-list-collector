# PowerShell 5.1 + ADB only. Saves a checkpoint after every accepted card.
param(
    [Parameter(Mandatory=$true)][ValidateSet('dewu','xhs','dy')][string]$App,
    [ValidateRange(1,100000)][int]$Limit=50,
    [string]$Csv='', [string]$ImageDir='', [string]$AdbPath='', [string]$Serial='',
    [ValidateRange(1,10000)][int]$MaxScroll=100,
    [switch]$KeepScreen, [switch]$Resume, [string]$ReplayDir='', [string]$LayoutFile=''
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'list_core.ps1')
$layoutProfile=if ($LayoutFile) { Get-Content -LiteralPath $LayoutFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
if (-not $Csv) { $Csv="$App.csv" }
$Csv=[IO.Path]::GetFullPath($Csv)
if (-not $ImageDir) { $ImageDir=Join-Path (Split-Path -Parent $Csv) ([IO.Path]::GetFileNameWithoutExtension($Csv)+'_images') }
$ImageDir=[IO.Path]::GetFullPath($ImageDir)
if ((Test-Path -LiteralPath $Csv) -and -not $Resume) { throw 'CSV 已存在，请换新路径或使用 -Resume' }
$rows=New-Object System.Collections.ArrayList
$seen=@{}
if ($Resume -and (Test-Path -LiteralPath $Csv)) {
    foreach ($row in @(Import-Csv -LiteralPath $Csv -Encoding UTF8)) {
        if ($row.应用 -ne (Get-ListConfig $App).name) { throw '续采 CSV 与当前 App 不一致' }
        if (-not $row.标题 -or -not (Test-Path -LiteralPath $row.首图)) { throw '续采数据缺少标题或图片' }
        $null=$rows.Add($row); $seen[$row.标题]=$true
    }
}
if ($rows.Count -ge $Limit) { Write-Output "已有 $($rows.Count) 条，已达到目标"; return }
$null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Csv),$ImageDir
function Invoke-Adb([string[]]$Arguments) {
    $ErrorActionPreference='Continue'
    if ($Serial) { $Arguments=@('-s',$Serial)+$Arguments }
    $output=(& $script:ADB @Arguments 2>&1 | ForEach-Object { "$_" }) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "ADB 执行失败：$output" }
    return $output
}
function Save-AdbScreen([string]$Path) {
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$script:ADB
    if ($Serial -and $Serial -notmatch '^[A-Za-z0-9_.:-]+$') { throw '无效的设备编号' }
    $psi.Arguments=if ($Serial) { '-s '+$Serial+' exec-out screencap -p' } else { 'exec-out screencap -p' }
    $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $p=[Diagnostics.Process]::Start($psi)
    $stderr=$p.StandardError.ReadToEndAsync()
    try {
        $fs=[IO.File]::Create($Path)
        try { $p.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Dispose() }
        $p.WaitForExit()
        if ($p.ExitCode -ne 0) { throw "截图失败：$($stderr.Result)" }
    } finally { $p.Dispose() }
}
if ($ReplayDir) {
    $frames=@(Get-ChildItem -LiteralPath $ReplayDir -Filter '*.xml' -File | Sort-Object Name)
    if (-not $frames.Count) { throw '回放目录没有 XML/PNG 配对数据' }
} else {
    . (Join-Path $PSScriptRoot 'device.ps1')
    $script:ADB=Find-ProductAdb $AdbPath
    $devices=Invoke-ProductAdb $script:ADB @('devices')
    if ($Serial) {
        if ($devices -notmatch ('(?m)^'+[regex]::Escape($Serial)+'\s+device\s*$')) { throw '选定的手机未连接或未授权' }
    } elseif (@([regex]::Matches($devices,'(?m)^\S+\s+device\s*$')).Count -ne 1) { throw '请连接一台已授权手机，或用 -Serial 选择设备' }
}
$noNew=0
Save-ListCheckpoint $rows.ToArray() $Csv
try {
    for ($screen=1; $screen -le $MaxScroll -and $rows.Count -lt $Limit; $screen++) {
        $shot=Join-Path $ImageDir ('_screen_'+[guid]::NewGuid().ToString('N')+'.png')
        $owned=-not [bool]$ReplayDir
        if ($ReplayDir) {
            if ($screen -gt $frames.Count) { break }
            $xmlText=[IO.File]::ReadAllText($frames[$screen-1].FullName)
            $shot=[IO.Path]::ChangeExtension($frames[$screen-1].FullName,'.png')
        } else {
            $null=Invoke-Adb @('shell','uiautomator dump /sdcard/_ui.xml')
            $xmlText=Invoke-Adb @('shell','cat /sdcard/_ui.xml')
            Save-AdbScreen $shot
        }
        $img=$null
        try {
            $nodes=@(Read-ListNodes $xmlText)
            $img=[Drawing.Image]::FromFile($shot)
            if ($owned -and $KeepScreen) { [IO.File]::WriteAllText([IO.Path]::ChangeExtension($shot,'.xml'),$xmlText) }
            if ($img.Width -ge $img.Height) { throw '请将手机转为竖屏，并进入双列商品搜索结果页' }
            if ($layoutProfile) { Set-ProductLayoutProfile $layoutProfile $App $img.Width $img.Height }
            $referenceHeight=[int][Math]::Round($img.Height*1272.0/$img.Width)
            $nodes=@(ConvertTo-ReferenceNodes $nodes $img.Width)
            $headerLimit=(Get-ListConfig $App).headerY+80
            if (-not $ReplayDir -and -not @($nodes | Where-Object { $_.t -eq '商品' -and $_.y1 -lt $headerLimit }).Count) { throw '未识别到商品页签，请先在手机手动进入商品搜索结果页' }
            $cards=@(Get-ListCards $nodes $App)
            $added=0; $skipped=0
            foreach ($c in $cards) {
                if ($rows.Count -ge $Limit) { break }
                if ($seen.ContainsKey($c.t)) { continue }
                $box=Get-ListImageBox $c $App 1272 $referenceHeight
                if (-not $box) { $skipped++; continue }
                $box=ConvertTo-DeviceBox $box $img.Width $img.Height
                $index=$rows.Count+1
                $out=Join-Path $ImageDir ('{0:D3}_{1}.png' -f $index,[guid]::NewGuid().ToString('N'))
                $bitmap=New-Object Drawing.Bitmap($box.w,$box.h)
                $g=[Drawing.Graphics]::FromImage($bitmap)
                try {
                    $rect=New-Object Drawing.Rectangle($box.x,$box.y,$box.w,$box.h)
                    $dest=New-Object Drawing.Rectangle(0,0,$box.w,$box.h)
                    $g.DrawImage($img,$dest,$rect,[Drawing.GraphicsUnit]::Pixel)
                    $bitmap.Save($out,[Drawing.Imaging.ImageFormat]::Png)
                } finally { $g.Dispose(); $bitmap.Dispose() }
                $null=$rows.Add([pscustomobject][ordered]@{
                    序号=$index; 应用=(Get-ListConfig $App).name; 标题=$c.t; 价格=$c.price; 已售=$c.sold
                    店铺=$c.shop; 好评率=$c.goodrate; 店铺销量=$c.sales; 几年老店=$c.old; 首图=$out
                    图片说明='屏幕裁图，可能含 App 浮层，未修补遮挡像素'
                })
                $seen[$c.t]=$true
                Save-ListCheckpoint $rows.ToArray() $Csv
                $added++
            }
            Write-Output "第 $screen 屏：实际新增 $added，累计 $($rows.Count)/$Limit；不完整图片跳过 $skipped"
            $noNew=if ($added) { 0 } else { $noNew+1 }
            $swipeX=[int]($img.Width/2); $swipeFrom=[int]($img.Height*0.76); $swipeTo=[int]($img.Height*0.51)
        } finally {
            if ($img) { $img.Dispose() }
            if ($owned -and -not $KeepScreen -and (Test-Path -LiteralPath $shot)) { Remove-Item -LiteralPath $shot -Force }
        }
        if ($rows.Count -ge $Limit -or $noNew -ge 4) { break }
        if (-not $ReplayDir) {
            $null=Invoke-Adb @('shell',"input swipe $swipeX $swipeFrom $swipeX $swipeTo 300")
            Start-Sleep -Milliseconds 2200
        }
    }
} finally {
    Save-ListCheckpoint $rows.ToArray() $Csv
    Write-Output "已保存 $($rows.Count)/$Limit 条：$Csv"
}

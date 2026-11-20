# Default successful output is a single self-contained workbook.
param(
    [Parameter(Mandatory=$true)][ValidateSet('dewu','xhs','dy')][string]$App,
    [Parameter(Mandatory=$true)][string]$Keyword,
    [ValidateRange(1,100000)][int]$Limit=50,
    [string]$OutDir='out', [string]$AdbPath='', [string]$ReplayDir='',
    [ValidateRange(1,10000)][int]$MaxScroll=100,
    [switch]$NoNav, [switch]$KeepData
)
$ErrorActionPreference='Stop'
$OutDir=[IO.Path]::GetFullPath($OutDir)
$null=New-Item -ItemType Directory -Force -Path $OutDir
$job=Join-Path $OutDir ('.work_'+$App+'_'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $job
$csv=Join-Path $job 'progress.csv'
$imgDir=Join-Path $job 'images'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$xlsx=Join-Path $OutDir ($App+'_'+$stamp+'.xlsx')
$failure=$null
try {
    if (-not $NoNav -and -not $ReplayDir) {
        & (Join-Path $PSScriptRoot 'ps_nav.ps1') -App $App -Keyword $Keyword -AdbPath $AdbPath
    }
    & (Join-Path $PSScriptRoot 'ps_collect.ps1') -App $App -Limit $Limit -Csv $csv -ImageDir $imgDir -AdbPath $AdbPath -MaxScroll $MaxScroll -ReplayDir $ReplayDir
} catch { $failure=$_ }
$rows=if (Test-Path -LiteralPath $csv) { @(Import-Csv -LiteralPath $csv -Encoding UTF8) } else { @() }
if (-not $rows.Count) { throw "没有采到数据，进度保留在 $job。$failure" }
if ($rows.Count -lt $Limit) { $xlsx=Join-Path $OutDir ([IO.Path]::GetFileNameWithoutExtension($xlsx)+'_部分.xlsx') }
# Paths are internal inputs only. The public workbook contains embedded images.
& (Join-Path $PSScriptRoot 'make_xlsx.ps1') -Csv $csv -ImageColumn 首图 -Out $xlsx -ImageWidth 160 -FreezeHeader
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=[IO.Compression.ZipFile]::OpenRead($xlsx)
try {
    $embedded=@($zip.Entries | Where-Object { $_.FullName -like 'xl/media/*' }).Count
    if ($embedded -ne $rows.Count) { throw "图片嵌入数 $embedded 与记录数 $($rows.Count) 不符，临时数据保留" }
} finally { $zip.Dispose() }
if (-not $failure -and -not $KeepData) {
    $resolvedJob=[IO.Path]::GetFullPath($job)
    $parent=[IO.Directory]::GetParent($resolvedJob).FullName
    if ($parent -ne $OutDir -or [IO.Path]::GetFileName($resolvedJob) -notlike '.work_*') { throw '临时目录校验失败' }
    Remove-Item -LiteralPath $resolvedJob -Recurse -Force
} else { Write-Output "续采/核查数据：$job" }
Write-Output "完成：$($rows.Count)/$Limit 条。Excel：$xlsx"
if ($failure) { throw "已导出部分 Excel，采集错误：$failure" }

# run_all.ps1 -- 一条命令跑完：导航 → 采集 → 出带图 Excel（零 Python）
#
# 用法：
#   .\run_all.ps1 -App dewu -Keyword Nike  -Limit 20
#   .\run_all.ps1 -App xhs  -Keyword adidas -Limit 20
#   .\run_all.ps1 -App dy   -Keyword ai     -Limit 20
#
# 产物：
#   out\<App>_<时间>.xlsx   带图表格
#   out\<App>_<时间>.csv    原始数据
#   out\imgs\<App>\*.jpg    首图

param(
    [Parameter(Mandatory = $true)][ValidateSet('dewu', 'xhs', 'dy')][string]$App,
    [Parameter(Mandatory = $true)][string]$Keyword,
    [int]$Limit = 20,
    [string]$OutDir = 'out',
    [switch]$NoNav,
    [switch]$NoExcel
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$csv = Join-Path $OutDir "$App`_$stamp.csv"
$imgDir = Join-Path $OutDir "imgs\$App"
$xlsx = Join-Path $OutDir "$App`_$stamp.xlsx"

if (-not $NoNav) {
    Write-Output "=== 1/3 导航：$App / $Keyword ==="
    & (Join-Path $here 'ps_nav.ps1') -App $App -Keyword $Keyword
    Start-Sleep -Seconds 2
} else {
    Write-Output '=== 1/3 跳过导航（用当前页面）==='
}

Write-Output "=== 2/3 采集：$Limit 条 ==="
& (Join-Path $here 'ps_collect.ps1') -App $App -Limit $Limit -Csv $csv -ImageDir $imgDir
if (-not (Test-Path $csv)) { throw '采集失败，没有生成 CSV' }

if ($NoExcel) {
    Write-Output "=== 跳过出表 ==="
    Write-Output "CSV: $csv"
    return
}

Write-Output '=== 3/3 出表 ==='
& (Join-Path $here 'make_xlsx.ps1') -Csv $csv -ImageColumn 首图 -Out $xlsx -ImageWidth 160 -FreezeHeader

Write-Output ''
Write-Output "完成："
Write-Output "  表格 $xlsx"
Write-Output "  数据 $csv"
Write-Output "  图片 $imgDir"

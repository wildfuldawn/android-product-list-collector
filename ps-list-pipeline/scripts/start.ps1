$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding
Write-Host '手机商品列表采集（无需 Python）'
$app=Read-Host '平台：1 小红书 / 2 得物 / 3 抖音'
$apps=@{'1'='xhs';'2'='dewu';'3'='dy'}
if (-not $apps.ContainsKey($app)) { throw '请选择 1、2 或 3' }
$keyword=Read-Host '搜索词（已在手机搜好时可直接回车）'
$limit=0
if (-not [int]::TryParse((Read-Host '采集数量，例如 10 或 50'),[ref]$limit) -or $limit -lt 1) { throw '数量必须是正整数' }
$noNav=-not [bool]$keyword
if ($noNav) { $keyword='current' }
& (Join-Path $PSScriptRoot 'run_all.ps1') -App $apps[$app] -Keyword $keyword -Limit $limit -NoNav:$noNav -OutDir (Join-Path (Split-Path -Parent $PSScriptRoot) '结果')

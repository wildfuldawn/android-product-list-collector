$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding
try {
    Write-Host '手机商品列表采集（Windows 免 Python 版）'
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') { throw '当前 PowerShell 受到限制，请在普通 Windows 桌面直接运行。受限 AI 工具或企业策略可能不支持本程序。' }
    Add-Type -AssemblyName System.Drawing
    . (Join-Path $PSScriptRoot 'device.ps1')
    $adb=Find-ProductAdb
    $serial=Select-ProductDevice $adb
    $apps=@{'1'='xhs';'2'='dewu';'3'='dy'}
    $app=Read-Host '平台：1 小红书 / 2 得物 / 3 抖音'
    if (-not $apps.ContainsKey($app)) { throw '请选择 1、2 或 3' }
    Write-Host '请在手机上手动搜索关键词，进入“商品”结果页，使用竖屏双列列表，保持解锁。'
    Write-Host '换手机或更改 App 字体/显示缩放后，请先采 3 条，检查标题、价格、图片是否匹配。'
    $null=Read-Host '页面准备好后按回车'
    $limit=0
    $text=Read-Host '采集数量（直接回车先测试 3 条）'
    if (-not $text) { $text='3' }
    if (-not [int]::TryParse($text,[ref]$limit) -or $limit -lt 1) { throw '数量必须是正整数' }
    & (Join-Path $PSScriptRoot 'run_all.ps1') -App $apps[$app] -Keyword current -Limit $limit -NoNav -Serial $serial -AdbPath $adb -OutDir (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '结果')
} catch {
    Write-Host "运行失败：$_" -ForegroundColor Red
    Write-Host '无需改成 Python。若错误来自 AI 工具的命令安全检查，请直接在 Windows 桌面运行启动采集.cmd；企业电脑需由管理员确认允许的运行方式。'
    exit 1
}

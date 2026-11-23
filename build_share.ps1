# Explicit allowlist: never include device profiles, captures, credentials, or results.
param([string]$AdbDirectory='',[string]$OutputDirectory='dist')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
if (-not $AdbDirectory) {
    $AdbDirectory=Join-Path $root 'tools\platform-tools'
    if (-not (Test-Path -LiteralPath $AdbDirectory)) { $AdbDirectory=Join-Path $root 'tools' }
}
foreach($file in @('adb.exe','AdbWinApi.dll','AdbWinUsbApi.dll','NOTICE.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $AdbDirectory $file))) { throw "缺少 ADB 组件或许可证：$file。使用完整 Android Platform Tools 目录。" }
}
$output=[IO.Path]::GetFullPath($OutputDirectory)
$null=New-Item -ItemType Directory -Force -Path $output
$stage=Join-Path $output ('.share-stage-'+[guid]::NewGuid().ToString('N'))
$package=Join-Path $stage '手机商品采集工作流'
$null=New-Item -ItemType Directory -Path $package
try {
    foreach($file in @('README.md','AGENTS.md','启动采集.cmd','build_share.ps1')) { Copy-Item -LiteralPath (Join-Path $root $file) -Destination $package }
    foreach($dir in @('scripts','tests','references')) {
        $source=Join-Path $root ('ps-list-pipeline\'+$dir)
        $target=Join-Path $package ('ps-list-pipeline\'+$dir)
        $null=New-Item -ItemType Directory -Path $target -Force
        $patterns=if ($dir -eq 'references') { @('*.md') } else { @('*.ps1') }
        foreach($pattern in $patterns) { Get-ChildItem -LiteralPath $source -File -Filter $pattern | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $target } }
    }
    Copy-Item -LiteralPath (Join-Path $root 'ps-list-pipeline\SKILL.md') -Destination (Join-Path $package 'ps-list-pipeline')
    $rankTarget=Join-Path $package 'hongguo-rank-pipeline'
    $null=New-Item -ItemType Directory -Path $rankTarget -Force
    foreach($file in @('README.md','SKILL.md')) { Copy-Item -LiteralPath (Join-Path $root ('hongguo-rank-pipeline\'+$file)) -Destination $rankTarget }
    foreach($dir in @('scripts','tests')) {
        $target=Join-Path $rankTarget $dir
        $null=New-Item -ItemType Directory -Path $target -Force
        Get-ChildItem -LiteralPath (Join-Path $root ('hongguo-rank-pipeline\'+$dir)) -File -Filter '*.ps1' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $target }
    }
    $tools=Join-Path $package 'tools'
    $null=New-Item -ItemType Directory -Path $tools
    foreach($file in @('adb.exe','AdbWinApi.dll','AdbWinUsbApi.dll','NOTICE.txt')) { Copy-Item -LiteralPath (Join-Path $AdbDirectory $file) -Destination $tools }
    $zip=Join-Path $output ('手机商品采集工作流_免Python_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.zip')
    Compress-Archive -LiteralPath $package -DestinationPath $zip -CompressionLevel Optimal
    Write-Output "分享包：$zip"
} finally {
    $resolved=[IO.Path]::GetFullPath($stage)
    if ([IO.Directory]::GetParent($resolved).FullName -eq $output -and [IO.Path]::GetFileName($resolved) -like '.share-stage-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

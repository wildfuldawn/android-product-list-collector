# Capture evidence for an agent without navigating or assuming a device layout.
param([string]$AdbPath='', [string]$Serial='', [string]$OutDir='inspection')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'device.ps1')
. (Join-Path $PSScriptRoot 'list_core.ps1')
$adb=Find-ProductAdb $AdbPath
$devices=@(Get-ProductDevices $adb)
if (-not $Serial) {
    if ($devices.Count -ne 1) { throw '请用 -Serial 明确选择一台已授权手机' }
    $Serial=$devices[0]
}
if ($Serial -notin $devices -or $Serial -notmatch '^[A-Za-z0-9_.:-]+$') { throw '手机未授权或设备编号无效' }
$OutDir=[IO.Path]::GetFullPath($OutDir)
if (Test-Path -LiteralPath $OutDir) { throw '核查目录已存在，请使用新目录以保留旧证据' }
$null=New-Item -ItemType Directory -Path $OutDir -Force
$null=Invoke-ProductAdb $adb @('-s',$Serial,'shell','uiautomator dump /sdcard/_product_inspect.xml')
$xml=Invoke-ProductAdb $adb @('-s',$Serial,'shell','cat /sdcard/_product_inspect.xml')
[IO.File]::WriteAllText((Join-Path $OutDir 'page.xml'),$xml)
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName=$adb; $psi.Arguments='-s '+$Serial+' exec-out screencap -p'
$psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
$process=[Diagnostics.Process]::Start($psi)
$stderr=$process.StandardError.ReadToEndAsync()
try {
    $stream=[IO.File]::Create((Join-Path $OutDir 'page.png'))
    try { $process.StandardOutput.BaseStream.CopyTo($stream) } finally { $stream.Dispose() }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw $stderr.Result }
} finally { $process.Dispose() }
Add-Type -AssemblyName System.Drawing
$image=[Drawing.Image]::FromFile((Join-Path $OutDir 'page.png'))
try {
    $nodes=@(ConvertTo-ReferenceNodes @(Read-ListNodes $xml) $image.Width)
    $nodes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'nodes-reference.json') -Encoding UTF8
    [pscustomobject]@{screenWidth=$image.Width;screenHeight=$image.Height;referenceWidth=1272;referenceHeight=[int][Math]::Round($image.Height*1272.0/$image.Width);textNodeCount=$nodes.Count} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutDir 'screen.json') -Encoding UTF8
} finally { $image.Dispose() }
Write-Output "只读核查证据已保存：$OutDir"

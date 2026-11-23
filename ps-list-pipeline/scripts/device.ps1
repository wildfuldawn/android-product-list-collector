# Resolve only supplied, bundled, or PATH tools; no machine-specific paths.
function Find-ProductAdb([string]$Explicit='') {
    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit -PathType Leaf)) { throw '指定的 adb.exe 不存在' }
        return [IO.Path]::GetFullPath($Explicit)
    }
    $root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach($candidate in @((Join-Path $root 'tools\adb.exe'),(Join-Path $root 'tools\platform-tools\adb.exe'),$env:ADB_PATH)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    $cmd=Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw '找不到 ADB，请完整解压分享包（包含 tools 目录），或指定 -AdbPath'
}
function Invoke-ProductAdb([string]$Adb, [string[]]$AdbArguments) {
    $ErrorActionPreference='Continue'
    $result=(& $Adb @AdbArguments 2>&1 | ForEach-Object { "$_" }) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw $result }
    $result
}
function Get-ProductDevices([string]$Adb) {
    $result=Invoke-ProductAdb $Adb @('devices')
    foreach($line in $result -split "`n") {
        if ($line -match '^(\S+)\s+device\s*$') { $Matches[1] }
    }
}
# adb shell cat 会把 UTF-8 界面文本按控制台代码页解码，中文和引号可能被破坏；
# 统一改为 pull 到本地后按 UTF-8 读取，保证标题与价格原样进入解析器。
function Get-ProductUiXml([string]$Adb,[string]$Serial,[string]$LocalPath,[string]$Remote='/sdcard/_product_ui.xml') {
    $null=Invoke-ProductAdb $Adb @('-s',$Serial,'shell','uiautomator dump',$Remote)
    # adb.exe 在中文 Windows 上按本机代码页接收路径参数，含中文的本地路径会写入失败；
    # 统一先 pull 到 ASCII 临时文件再读，最后另存到调用方指定位置。
    $tmp=[IO.Path]::Combine([IO.Path]::GetTempPath(),('pslist_ui_'+[guid]::NewGuid().ToString('N')+'.xml'))
    try {
        $pull=Invoke-ProductAdb $Adb @('-s',$Serial,'pull',$Remote,$tmp)
        if (-not (Test-Path -LiteralPath $tmp)) { throw "拉取界面 XML 失败：$pull" }
        $text=[IO.File]::ReadAllText($tmp,[Text.Encoding]::UTF8)
        if ($LocalPath) { [IO.File]::WriteAllText($LocalPath,$text,(New-Object Text.UTF8Encoding($false))) }
        $text
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}
function Test-ProductEndpoint([string]$Endpoint) {
    if ($Endpoint -notmatch '^(\d{1,3}(?:\.\d{1,3}){3}):(\d{1,5})$') { return $false }
    $ip=$null
    return [Net.IPAddress]::TryParse($Matches[1],[ref]$ip) -and [int]$Matches[2] -gt 0 -and [int]$Matches[2] -le 65535
}
function Select-ProductDevice([string]$Adb) {
    for($attempt=0;$attempt -lt 5;$attempt++) {
        $devices=@(Get-ProductDevices $Adb)
        if ($devices.Count -eq 1) { return $devices[0] }
        if ($devices.Count -gt 1) {
            for($i=0;$i -lt $devices.Count;$i++) { Write-Host ("{0}. {1}" -f ($i+1),$devices[$i]) }
            $choice=0
            if ([int]::TryParse((Read-Host '选择要采集的手机编号'),[ref]$choice) -and $choice -ge 1 -and $choice -le $devices.Count) { return $devices[$choice-1] }
            continue
        }
        Write-Host '未发现已授权手机。USB：连接数据线并在手机上允许调试。无线：电脑手机须同网。'
        $endpoint=Read-Host '输入无线调试连接 IP:端口；输入 p 先配对；USB 已授权则回车重试；q 退出'
        if ($endpoint -eq 'q') { throw '已取消连接' }
        if ($endpoint -eq 'p') {
            $pairEndpoint=Read-Host '输入“使用配对码配对设备”中的 IP:端口'
            $code=Read-Host '输入手机上的六位配对码'
            if (-not (Test-ProductEndpoint $pairEndpoint) -or $code -notmatch '^\d{6}$') { Write-Host '配对地址或配对码格式不正确'; continue }
            try { $null=Invoke-ProductAdb $Adb @('pair',$pairEndpoint,$code); Write-Host '配对成功。下一步输入无线调试主页面的连接地址。' } catch { Write-Host "配对失败：$_" }
        } elseif ($endpoint) {
            if (-not (Test-ProductEndpoint $endpoint)) { Write-Host '请使用 IP:端口 格式'; continue }
            try { Write-Host (Invoke-ProductAdb $Adb @('connect',$endpoint)) } catch { Write-Host "连接失败：$_" }
        }
    }
    throw '没有连接到已授权手机，请检查手机调试授权和数据线/网络后重试'
}

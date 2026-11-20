# ocr.ps1 -- 用 Windows 自带 OCR（WinRT）识别图片，输出 JSON 行
#   powershell -File ocr.ps1 -ImagePath shot.png [-Lang zh-Hans-CN] [-Json out.json]
# 输出每行：{"text":"...","x":123,"y":456,"w":78,"h":32}

param(
    [Parameter(Mandatory = $true)][string]$ImagePath,
    [string]$Lang = 'zh-Hans-CN',
    [string]$Json = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null

[Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Graphics.Imaging.BitmapDecoder, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.StorageFile, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null
[Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime] | Out-Null

# IAsyncOperation<T> -> Task<T> 适配器（避免反引号，用 char 96 拼名字）
$genericName = 'IAsyncOperation' + [char]96 + '1'
$asTaskGeneric = $null
foreach ($m in [System.WindowsRuntimeSystemExtensions].GetMethods()) {
    if ($m.Name -ne 'AsTask') { continue }
    $ps = $m.GetParameters()
    if ($ps.Count -eq 1 -and $ps[0].ParameterType.Name -eq $genericName) {
        $asTaskGeneric = $m
        break
    }
}
if ($null -eq $asTaskGeneric) { Write-Error '找不到 AsTask 适配器'; exit 3 }

function Await-Op {
    param($Operation, [Type]$ResultType)
    $mi = $asTaskGeneric.MakeGenericMethod($ResultType)
    $task = $mi.Invoke($null, @($Operation))
    $task.Wait(-1) | Out-Null
    $task.Result
}

$full = (Resolve-Path -LiteralPath $ImagePath).Path

$file = Await-Op ([Windows.Storage.StorageFile]::GetFileFromPathAsync($full)) ([Windows.Storage.StorageFile])
$stream = Await-Op ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await-Op ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await-Op ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])

$language = New-Object Windows.Globalization.Language($Lang)
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
if ($null -eq $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
if ($null -eq $engine) { Write-Error "没有可用的 OCR 引擎（$Lang）"; exit 2 }

$result = Await-Op ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])

$out = @()
foreach ($line in $result.Lines) {
    $x = [double]::MaxValue
    $y = [double]::MaxValue
    $x2 = 0.0
    $y2 = 0.0
    foreach ($w in $line.Words) {
        $r = $w.BoundingRect
        if ($r.X -lt $x) { $x = $r.X }
        if ($r.Y -lt $y) { $y = $r.Y }
        if (($r.X + $r.Width) -gt $x2) { $x2 = $r.X + $r.Width }
        if (($r.Y + $r.Height) -gt $y2) { $y2 = $r.Y + $r.Height }
    }
    $obj = [pscustomobject]@{
        text = $line.Text
        x    = [int]$x
        y    = [int]$y
        w    = [int]($x2 - $x)
        h    = [int]($y2 - $y)
    }
    $out += ($obj | ConvertTo-Json -Compress)
}

if ($Json) {
    Set-Content -LiteralPath $Json -Value ($out -join "`n") -Encoding UTF8
    Write-Output "OCR 行数 $($out.Count) -> $Json"
} else {
    $out | ForEach-Object { Write-Output $_ }
}

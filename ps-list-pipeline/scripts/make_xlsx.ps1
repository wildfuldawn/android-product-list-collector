# make_xlsx.ps1 -- 不装任何东西（不用 Python、不用 Excel、不用 Office），把图片放进 xlsx
#
# 原理：xlsx = zip + 一组 OOXML 文本；PowerShell 自带 System.IO.Compression 能打 zip，
#       System.Drawing 能读图片尺寸。图片字节直接塞进 xl/media/，再用 drawing1.xml 声明贴哪儿。
#
# 用法：
#   # 1) 从 CSV 生成（CSV 里有一列是图片路径）
#   powershell -ExecutionPolicy Bypass -File make_xlsx.ps1 `
#       -Csv data.csv -ImageColumn 首图 -Out 结果.xlsx -ImageWidth 150
#
#   # 2) 直接给数据（不写 CSV）
#   $rows = @(
#       [pscustomobject]@{ 序号='1'; 标题='Nike Dunk'; 价格='¥516'; 首图='D:\img\1.jpg' }
#   )
#   .\make_xlsx.ps1 -Rows $rows -ImageColumn 首图 -Out out.xlsx
#
#   # 3) 直接把一整个文件夹的图片做成表（每张图一行）
#   .\make_xlsx.ps1 -ImageFolder D:\crops -Out 全部图片.xlsx -ImageWidth 120

param(
    [string]$Csv = '',
    [object[]]$Rows = $null,
    [string]$ImageColumn = '首图',
    [string]$ImageFolder = '',
    [string]$Out = 'out.xlsx',
    [string]$SheetName = 'Sheet1',
    [int]$ImageWidth = 150,
    [int]$ImageHeight = 0,          # 0 = 按原图比例算
    [double[]]$Widths = $null,
    [switch]$FreezeHeader
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing | Out-Null
Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

# ---------- 取数据 ----------
if ($ImageFolder) {
    $files = Get-ChildItem -LiteralPath $ImageFolder -File -Include *.jpg, *.jpeg, *.png -Recurse |
             Sort-Object Name
    $i = 0
    $Rows = @()
    foreach ($f in $files) {
        $i++
        $Rows += [pscustomobject]@{ 序号 = $i; 文件名 = $f.Name; 首图 = $f.FullName }
    }
    if (-not $PSBoundParameters.ContainsKey('ImageColumn')) { $ImageColumn = '首图' }
}
elseif ($Csv) {
    if (-not (Test-Path -LiteralPath $Csv)) { throw "找不到 CSV: $Csv" }
    $Rows = @(Import-Csv -LiteralPath $Csv -Encoding UTF8)
}
if (-not $Rows -or $Rows.Count -eq 0) { throw '没有数据：请用 -Csv / -Rows / -ImageFolder 提供' }

# 列名（按第一条的属性顺序）
$headers = @($Rows[0].PSObject.Properties.Name)
if (-not $Widths) {
    $Widths = @($headers | ForEach-Object {
        switch ($_) {
            '序号' { 7 }; '应用' { 11 }; '标题' { 50 }; '店铺' { 24 }
            '首图' { 25 }; '图片说明' { 38 }; default { 14 }
        }
    })
}

# ---------- 工具 ----------
function Esc([string]$s) {
    if ($null -eq $s) { return '' }
    return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}

function ColLetter([int]$idx) {          # 1 -> A
    $s = ''
    while ($idx -gt 0) {
        $r = ($idx - 1) % 26
        $s = [char](65 + $r) + $s
        $idx = [int][math]::Floor(($idx - 1) / 26)
    }
    return $s
}

$EMU = 9525     # 1px = 9525 EMU
$utf8 = New-Object System.Text.UTF8Encoding($false)

# ---------- 收集图片 ----------
$imgColIdx = [array]::IndexOf($headers, $ImageColumn) + 1     # 0 表示没有这一列
$images = @()      # @{ row=; col=; path=; ext=; w=; h= }
$mediaBytes = @()

if ($imgColIdx -gt 0) {
    for ($r = 0; $r -lt $Rows.Count; $r++) {
        $p = [string]$Rows[$r].$ImageColumn
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        try {
            $img = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $p).Path)
            $iw = $img.Width
            $ih = $img.Height
            $img.Dispose()
        } catch { continue }

        $w = $ImageWidth
        $h = if ($ImageHeight -gt 0) { $ImageHeight } else { [int][math]::Round($iw * ($ImageWidth / [double]$iw)) }
        if ($ImageHeight -le 0) { $h = [int][math]::Round($ih * ($ImageWidth / [double]$iw)) }

        $ext = [System.IO.Path]::GetExtension($p).ToLower().TrimStart('.')
        if ($ext -eq 'jpe') { $ext = 'jpeg' }
        if ($ext -ne 'png' -and $ext -ne 'jpeg' -and $ext -ne 'jpg') { continue }
        if ($ext -eq 'jpg') { $ext = 'jpeg' }

        $idx = $images.Count + 1
        $mediaBytes += , @{ name = "xl/media/image$idx.$ext"; bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $p).Path); ext = $ext }
        $images += @{ row = ($r + 2); col = $imgColIdx; w = $w; h = $h; id = $idx }
    }
}

# ---------- sheet1.xml ----------
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
[void]$sb.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">')

if ($FreezeHeader) {
    [void]$sb.Append('<sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>')
} else {
    [void]$sb.Append('<sheetViews><sheetView workbookViewId="0"/></sheetViews>')
}

# 列宽
if ($Widths) {
    [void]$sb.Append('<cols>')
    for ($i = 1; $i -le $Widths.Count; $i++) {
        [void]$sb.Append("<col min=`"$i`" max=`"$i`" width=`"$([double]$Widths[$i-1])`" customWidth=`"1`"/>")
    }
    [void]$sb.Append('</cols>')
}

[void]$sb.Append('<sheetData>')

# 表头
[void]$sb.Append('<row r="1" ht="28" customHeight="1">')
for ($c = 1; $c -le $headers.Count; $c++) {
    $ref = (ColLetter $c) + '1'
    [void]$sb.Append("<c r=`"$ref`" s=`"1`" t=`"inlineStr`"><is><t xml:space=`"preserve`">$(Esc $headers[$c-1])</t></is></c>")
}
[void]$sb.Append('</row>')

# 数据行
for ($r = 0; $r -lt $Rows.Count; $r++) {
    $rowNum = $r + 2
    # 有图的行给个行高
    $imgRow = $images | Where-Object { $_.row -eq $rowNum } | Select-Object -First 1
    if ($imgRow) {
        [void]$sb.Append("<row r=`"$rowNum`" ht=`"$([math]::Round(($imgRow.h + 6) * 0.75, 1))`" customHeight=`"1`">")
    } else {
        [void]$sb.Append("<row r=`"$rowNum`">")
    }
    for ($c = 1; $c -le $headers.Count; $c++) {
        $ref = (ColLetter $c) + $rowNum
        $v = [string]$Rows[$r].($headers[$c-1])
        if ($c -eq $imgColIdx) { $v='' } # Embedded picture, never expose a temporary file path.
        if ([string]::IsNullOrEmpty($v)) { [void]$sb.Append("<c r=`"$ref`"/>"); continue }
        if ($headers[$c-1] -eq '价格' -and $v -match '^[¥￥]([0-9]+(?:\.[0-9]+)?)$') {
            [void]$sb.Append("<c r=`"$ref`" s=`"2`"><v>$($Matches[1])</v></c>")
            continue
        }
        $num = 0.0
        if ([double]::TryParse($v, [ref]$num) -and $v -notmatch '^0\d') {
            [void]$sb.Append("<c r=`"$ref`"><v>$v</v></c>")
        } else {
            [void]$sb.Append("<c r=`"$ref`" t=`"inlineStr`"><is><t xml:space=`"preserve`">$(Esc $v)</t></is></c>")
        }
    }
    [void]$sb.Append('</row>')
}
[void]$sb.Append('</sheetData>')
if ($images.Count -gt 0) { [void]$sb.Append('<drawing r:id="rId1"/>') }
[void]$sb.Append('</worksheet>')
$sheetXml = $sb.ToString()

# ---------- drawing1.xml ----------
$drawXml = ''
$drawRels = ''
if ($images.Count -gt 0) {
    $d = New-Object System.Text.StringBuilder
    [void]$d.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    [void]$d.Append('<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">')
    $n = 0
    foreach ($im in $images) {
        $n++
        $cx = $im.w * $EMU
        $cy = $im.h * $EMU
        [void]$d.Append("<xdr:oneCellAnchor><xdr:from><xdr:col>$($im.col-1)</xdr:col><xdr:colOff>19050</xdr:colOff><xdr:row>$($im.row-1)</xdr:row><xdr:rowOff>19050</xdr:rowOff></xdr:from><xdr:ext cx=`"$cx`" cy=`"$cy`"/>")
        [void]$d.Append("<xdr:pic><xdr:nvPicPr><xdr:cNvPr id=`"$($n+1)`" name=`"Picture $n`"/><xdr:cNvPicPr><a:picLocks noChangeAspect=`"1`"/></xdr:cNvPicPr></xdr:nvPicPr>")
        [void]$d.Append("<xdr:blipFill><a:blip xmlns:r=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships`" r:embed=`"rId$n`"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>")
        [void]$d.Append("<xdr:spPr><a:xfrm><a:off x=`"0`" y=`"0`"/><a:ext cx=`"$cx`" cy=`"$cy`"/></a:xfrm><a:prstGeom prst=`"rect`"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor>")
    }
    [void]$d.Append('</xdr:wsDr>')
    $drawXml = $d.ToString()

    $rr = New-Object System.Text.StringBuilder
    [void]$rr.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')
    for ($i = 1; $i -le $images.Count; $i++) {
        $ext = $mediaBytes[$i - 1].ext
        [void]$rr.Append("<Relationship Id=`"rId$i`" Type=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image`" Target=`"../media/image$i.$ext`"/>")
    }
    [void]$rr.Append('</Relationships>')
    $drawRels = $rr.ToString()
}

# ---------- 其它固定部件 ----------
$exts = $mediaBytes | ForEach-Object { $_.ext } | Sort-Object -Unique
$ct = New-Object System.Text.StringBuilder
[void]$ct.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
[void]$ct.Append('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>')
foreach ($e in $exts) {
    $mt = if ($e -eq 'png') { 'image/png' } else { 'image/jpeg' }
    [void]$ct.Append("<Default Extension=`"$e`" ContentType=`"$mt`"/>")
}
[void]$ct.Append('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
[void]$ct.Append('<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>')
[void]$ct.Append('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>')
if ($images.Count -gt 0) {
    [void]$ct.Append('<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>')
}
[void]$ct.Append('</Types>')

$rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'

$workbook = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="' + (Esc $SheetName) + '" sheetId="1" r:id="rId1"/></sheets></workbook>'

$wbRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'

$styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0F9D8F"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'

# Keep titles readable and prices sortable; preserve the existing OOXML writer.
[xml]$styleDoc=$styles
$styleNs='http://schemas.openxmlformats.org/spreadsheetml/2006/main'
$numFmts=$styleDoc.CreateElement('numFmts',$styleNs)
$numFmts.SetAttribute('count','1')
$currencyFmt=$styleDoc.CreateElement('numFmt',$styleNs)
$currencyFmt.SetAttribute('numFmtId','164')
$currencyFmt.SetAttribute('formatCode','"¥"0.00')
$null=$numFmts.AppendChild($currencyFmt)
$null=$styleDoc.DocumentElement.PrependChild($numFmts)
$cellXfs=$styleDoc.styleSheet.cellXfs
foreach ($xf in @($cellXfs.xf)) {
    $alignment=$styleDoc.CreateElement('alignment',$styleNs)
    $alignment.SetAttribute('vertical','center')
    $alignment.SetAttribute('wrapText','1')
    if ($xf.fontId -eq '1') { $alignment.SetAttribute('horizontal','center') }
    $null=$xf.AppendChild($alignment)
    $xf.SetAttribute('applyAlignment','1')
}
$currencyXf=$cellXfs.xf[0].CloneNode($true)
$currencyXf.SetAttribute('numFmtId','164')
$currencyXf.SetAttribute('applyNumberFormat','1')
$null=$cellXfs.AppendChild($currencyXf)
$cellXfs.SetAttribute('count','3')
$styles=$styleDoc.OuterXml

$sheetRels = $null
if ($images.Count -gt 0) {
    $sheetRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/></Relationships>'
}

# ---------- 打 zip ----------
$outPath = [System.IO.Path]::GetFullPath($Out)
$dir = [System.IO.Path]::GetDirectoryName($outPath)
if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Force }

$fs = [System.IO.File]::Open($outPath, [System.IO.FileMode]::Create)
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)

function AddEntry($archive, [string]$name, [string]$text) {
    $entry = $archive.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
    $s = $entry.Open()
    $bytes = $utf8.GetBytes($text)
    $s.Write($bytes, 0, $bytes.Length)
    $s.Dispose()
}

function AddEntryBytes($archive, [string]$name, [byte[]]$bytes) {
    $entry = $archive.CreateEntry($name, [System.IO.Compression.CompressionLevel]::Optimal)
    $s = $entry.Open()
    $s.Write($bytes, 0, $bytes.Length)
    $s.Dispose()
}

AddEntry $zip '[Content_Types].xml' $ct.ToString()
AddEntry $zip '_rels/.rels' $rootRels
AddEntry $zip 'xl/workbook.xml' $workbook
AddEntry $zip 'xl/_rels/workbook.xml.rels' $wbRels
AddEntry $zip 'xl/styles.xml' $styles
AddEntry $zip 'xl/worksheets/sheet1.xml' $sheetXml
if ($sheetRels) { AddEntry $zip 'xl/worksheets/_rels/sheet1.xml.rels' $sheetRels }
if ($images.Count -gt 0) {
    AddEntry $zip 'xl/drawings/drawing1.xml' $drawXml
    AddEntry $zip 'xl/drawings/_rels/drawing1.xml.rels' $drawRels
    foreach ($m in $mediaBytes) { AddEntryBytes $zip $m.name $m.bytes }
}
$zip.Dispose()
$fs.Dispose()

$size = [math]::Round((Get-Item -LiteralPath $outPath).Length / 1KB, 1)
Write-Output "OK $outPath  ($($Rows.Count) 行 / $($images.Count) 图 / $size KB)"

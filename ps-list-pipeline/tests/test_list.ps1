$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$scripts=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
. (Join-Path $scripts 'list_core.ps1')
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
$dir=Join-Path ([IO.Path]::GetTempPath()) ('product-list-test-'+[guid]::NewGuid().ToString('N'))
$frames=Join-Path $dir 'frames'
$null=New-Item -ItemType Directory -Path $frames -Force
try {
    Assert (-not (Test-Shop '3年老店')) '店龄标签不能作为店铺名'
    Assert (Test-Shop '欧阳袜哈的店') '真实店名不能被店龄过滤误伤'
    $xml='<hierarchy><node text="近期店铺销量TOP3" bounds="[52,1230][593,1282]"/>'+
        '<node text="&quot;这个材料还是不错的&quot;" bounds="[52,1293][593,1345]"/>'+
        '<node text="测试女款秋冬纯棉袜子" bounds="[52,1359][593,1430]"/>'+
        '<node text="券后¥8.99已售2297" bounds="[52,1526][510,1601]"/>'+
        '<node text="示例袜子旗舰店" bounds="[136,1637][361,1686]"/>'+
        '<node text="测试男款四季运动袜子" bounds="[679,1359][1220,1430]"/>'+
        '<node text="¥9.9已售18.2万+" bounds="[679,1526][1028,1601]"/></hierarchy>'
    [IO.File]::WriteAllText((Join-Path $frames '01.xml'),$xml)
    $image=New-Object Drawing.Bitmap(1272,2772)
    try { $image.Save((Join-Path $frames '01.png'),[Drawing.Imaging.ImageFormat]::Png) } finally { $image.Dispose() }
    $cards=@(Get-ListCards @(Read-ListNodes $xml) 'xhs')
    Assert ($cards.Count -eq 2) '促销词或评价被当成商品'
    Assert ($cards[0].quoteY -eq 1293) 'ASCII 引号/XML 实体未识别'
    $box=Get-ListImageBox $cards[0] 'xhs'
    Assert ($box.bottom -eq 1287 -and $box.bottom -lt 1293) '评价行被裁入图片'
    Assert ($cards[0].price -eq '¥8.99' -and $cards[1].sold -eq '18.2万+') '两列价格/销量串行'
    Assert (-not (Get-ListImageBox ([pscustomobject]@{cx=100;y1=900;quoteY=0}) 'xhs')) '顶部半图应跳过'
    foreach ($t in @('近期店铺销量top3','本周热销好物销量榜','回购榜精选商品TOP2')) {
        Assert (-not (Test-ListTitle ([pscustomobject]@{t=$t;y1=1359;w=541;h=71}) 'xhs' (Get-ListConfig 'xhs'))) '促销过滤回归'
    }
    foreach ($app in @('dewu','dy')) {
        $other=@(Get-ListCards @(Read-ListNodes '<hierarchy><node text="测试品牌运动长筒袜商品" bounds="[52,1400][593,1471]"/><node text="¥39.90已售23" bounds="[52,1550][593,1600]"/></hierarchy>') $app)
        Assert ($other.Count -eq 1 -and $other[0].price -eq '¥39.90') "$app 基础解析回归"
    }
    $dewuXml='<hierarchy><node resource-id="com.shizhuang.duapp:id/search_image" bounds="[23,741][613,1331]"/>'+ '<node text="测试品牌运动长筒袜商品" bounds="[51,1300][585,1363]"/><node text="¥ 4 8" bounds="[51,1394][122,1457]"/><node text="¥169" bounds="[136,1399][310,1455]"/></hierarchy>'
    $dewuCards=@(Get-ListCards @(Read-ListNodes $dewuXml) 'dewu')
    Assert ($dewuCards[0].price -eq '¥48') '得物分隔数字或划线价解析错误'
    $dewuBox=Get-ListImageBox $dewuCards[0] 'dewu'
    Assert ($dewuBox.y -eq 741 -and $dewuBox.bottom -eq 1236) '得物裁图包含顶部筛选栏'
    $csv=Join-Path $dir 'exact.csv'
    & (Join-Path $scripts 'ps_collect.ps1') -App xhs -Limit 1 -Csv $csv -ReplayDir $frames
    Assert (@(Import-Csv -LiteralPath $csv).Count -eq 1) '目标数量超采'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $dir 'exact_images') -Filter '*.png').Count -eq 1) '出现多余裁图'
    & (Join-Path $scripts 'ps_collect.ps1') -App xhs -Limit 2 -Csv $csv -ReplayDir $frames -Resume
    Assert (@(Import-Csv -LiteralPath $csv).Count -eq 2) '续采丢失/重复记录'
    $outputDir=Join-Path $dir 'workbook-only'
    & (Join-Path $scripts 'run_all.ps1') -App xhs -Keyword test -Limit 2 -ReplayDir $frames -OutDir $outputDir
    $outputs=@(Get-ChildItem -LiteralPath $outputDir -Force)
    Assert ($outputs.Count -eq 1 -and $outputs[0].Extension -eq '.xlsx') '成功后未做到只保留 Excel'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($outputs[0].FullName)
    try {
        Assert (@($zip.Entries | Where-Object { $_.FullName -like 'xl/media/*' }).Count -eq 2) 'Excel 图片嵌入丢失'
        $reader=New-Object IO.StreamReader($zip.GetEntry('xl/worksheets/sheet1.xml').Open())
        try { $sheetText=$reader.ReadToEnd() } finally { $reader.Dispose() }
        Assert ($sheetText -notmatch [regex]::Escape($dir)) 'Excel 暴露临时图片路径'
        Assert ($sheetText -match '<v>8.99</v>') '价格未保存为数值'
    } finally { $zip.Dispose() }
    [IO.File]::WriteAllText((Join-Path $frames '02.xml'),'<hierarchy><broken>')
    $broken=Join-Path $dir 'interrupted.csv'
    $failed=$false
    try { & (Join-Path $scripts 'ps_collect.ps1') -App xhs -Limit 5 -Csv $broken -ReplayDir $frames } catch { $failed=$true }
    Assert ($failed -and @(Import-Csv -LiteralPath $broken).Count -eq 2) '异常后检查点丢失'
    Write-Output 'PASS: promo, quotes, crop, columns, dewu/dy, exact count, resume, interrupted checkpoint, standalone workbook'
} finally {
    $resolved=[IO.Path]::GetFullPath($dir)
    $expected=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Directory]::GetParent($resolved).FullName -eq $expected -and [IO.Path]::GetFileName($resolved) -like 'product-list-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

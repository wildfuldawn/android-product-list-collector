$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$scripts=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
function Assert($ok,[string]$message){if(-not $ok){throw $message}}
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('hongguo-test-'+[guid]::NewGuid().ToString('N'))
$frames=Join-Path $tmp 'frames';$null=New-Item -ItemType Directory -Path $frames -Force
try{
    $cards=foreach($i in 1..2){$y=300+($i-1)*300;'<node text="" bounds="[0,{0}][720,{1}]"><node text="" bounds="[20,{0}][140,{2}]"><node text="{3}" bounds="[20,{0}][50,{4}]"/></node><node text="测试短剧{3}" bounds="[170,{0}][600,{4}]"/><node text="真人剧" bounds="[170,{4}][250,{5}]"/><node text="都市" bounds="[260,{4}][320,{5}]"/><node text="甲" bounds="[330,{4}][350,{5}]"/><node text="乙" bounds="[360,{4}][380,{5}]"/><node text="99万推荐" bounds="[500,{0}][680,{4}]"/><node text="测试剧情简介，保留完整列表文案。" bounds="[170,{5}][680,{6}]"/><node text=""><node text="评分9.1" bounds="[170,{6}][280,{7}]"/></node><node text="101万热度" bounds="[280,{6}][390,{7}]"/><node text="3.2万次点赞" bounds="[400,{6}][550,{7}]"/></node>' -f $y,($y+240),($y+170),$i,($y+40),($y+80),($y+120),($y+160)}
    $xml='<hierarchy><node text="推荐榜" bounds="[100,100][200,150]"/><node text="" bounds="[0,200][720,1500]">'+($cards -join '')+'</node></hierarchy>'
    [IO.File]::WriteAllText((Join-Path $frames '01.xml'),$xml)
    $bitmap=New-Object Drawing.Bitmap(720,1600);try{$bitmap.Save((Join-Path $frames '01.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
    $capture=Join-Path $tmp 'capture'
    & (Join-Path $scripts 'collect_rank.ps1') -Limit 1 -OutDir $capture -ReplayDir $frames
    $rows=Get-Content -LiteralPath (Join-Path $capture 'ranking.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert (@($rows).Count -eq 1) '目标数量超采'
    Assert ($rows.rating -eq '9.1') '嵌套评分没有读出'
    Assert ($rows.description -eq '测试剧情简介，保留完整列表文案。') '文案字段错误'
    Assert (@(Get-ChildItem -LiteralPath (Join-Path $capture 'posters') -File).Count -eq 1) '多余封面'
    & (Join-Path $scripts 'collect_rank.ps1') -Limit 2 -OutDir $capture -ReplayDir $frames -Resume
    $rows=Get-Content -LiteralPath (Join-Path $capture 'ranking.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($rows.Count -eq 2 -and @($rows|ForEach-Object {$_.rank}|Sort-Object -Unique).Count -eq 2) '续采丢失/重复排名'
    $output=Join-Path $tmp 'excel'
    & (Join-Path $scripts 'run_rank.ps1') -Limit 2 -OutDir $output -ReplayDir $frames
    $files=@(Get-ChildItem -LiteralPath $output -Force)
    Assert ($files.Count -eq 1 -and $files[0].Extension -eq '.xlsx') '正常导出后不止一个 Excel'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($files[0].FullName)
    try{Assert (@($zip.Entries|Where-Object {$_.FullName -like 'xl/media/*'}).Count -eq 2) 'Excel 封面未嵌入'}finally{$zip.Dispose()}
    $partialFailed=$false;$partialOutput=Join-Path $tmp 'partial'
    try{& (Join-Path $scripts 'run_rank.ps1') -Limit 3 -OutDir $partialOutput -ReplayDir $frames}catch{$partialFailed=$true}
    Assert ($partialFailed -and @(Get-ChildItem -LiteralPath $partialOutput -Filter '*_部分.xlsx').Count -eq 1) '未采满不得当成完整成功'
    $contextPath=Join-Path $capture 'context.json';$context=Get-Content -LiteralPath $contextPath -Raw -Encoding UTF8|ConvertFrom-Json
    $context.startedAt=(Get-Date).AddDays(-1).ToString('o');$context|ConvertTo-Json|Set-Content -LiteralPath $contextPath -Encoding UTF8
    $expired=$false
    try{& (Join-Path $scripts 'collect_rank.ps1') -Limit 2 -OutDir $capture -ReplayDir $frames -Resume}catch{$expired=$true}
    Assert $expired '不同日期的检查点不能续采混用'
    [IO.File]::WriteAllText((Join-Path $frames '02.xml'),$xml.Replace('测试短剧1','榜单已变化'))
    Copy-Item -LiteralPath (Join-Path $frames '01.png') -Destination (Join-Path $frames '02.png')
    $failed=$false;$changed=Join-Path $tmp 'changed'
    try{& (Join-Path $scripts 'collect_rank.ps1') -Limit 3 -OutDir $changed -ReplayDir $frames}catch{$failed=$true}
    $saved=Get-Content -LiteralPath (Join-Path $changed 'ranking.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert ($failed -and $saved.Count -eq 2) '榜单变化应停止并保留已采记录'
    Write-Output 'PASS: exact count, nested rating, description, rank merge, resume, embedded Excel, changed-board stop'
}finally{
    $full=[IO.Path]::GetFullPath($tmp)
    if([IO.Directory]::GetParent($full).FullName -eq [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') -and [IO.Path]::GetFileName($full) -like 'hongguo-test-*'){Remove-Item -LiteralPath $full -Recurse -Force}
}

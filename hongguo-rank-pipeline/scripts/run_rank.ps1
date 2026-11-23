param([ValidateRange(1,1000)][int]$Limit=50,[string]$AdbPath='',[string]$Serial='',
    [string]$TypeFilter='全部',[string]$Category='总榜',[string]$OutDir='结果',
    [string]$ReplayDir='',[switch]$KeepData,[int]$MaxScreens=45)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$OutDir=[IO.Path]::GetFullPath($OutDir)
$null=New-Item -ItemType Directory -Path $OutDir -Force
$lockDir=Join-Path $root '.agent-work'
$null=New-Item -ItemType Directory -Path $lockDir -Force
try{$lock=[IO.File]::Open((Join-Path $lockDir 'hongguo-running.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw '已有红果采集任务运行，已跳过本次，避免定时任务重叠操作手机'}
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$job=Join-Path $OutDir ('.hongguo-'+$stamp+'-'+[guid]::NewGuid().ToString('N'))
$failure=$null
try{
    try{& (Join-Path $PSScriptRoot 'collect_rank.ps1') -Limit $Limit -OutDir $job -AdbPath $AdbPath -Serial $Serial -TypeFilter $TypeFilter -Category $Category -ReplayDir $ReplayDir -MaxScreens $MaxScreens}catch{$failure=$_}
    $state=Join-Path $job 'ranking.json'
    if(-not (Test-Path -LiteralPath $state)){throw "未获取榜单，核查数据：$job。$failure"}
    $data=Get-Content -LiteralPath $state -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not @($data).Count){throw "没有榜单记录，核查数据：$job。$failure"}
    $rows=@(foreach($r in $data){[pscustomobject][ordered]@{
        排名=$r.rank;剧名=$r.title;类型=$r.type;题材=$r.category;人物信息=$r.people
        推荐数=$r.recommend;热度=$r.heat;点赞=$r.likes;评分=$r.rating;标签=$r.tag
        榜单文案=$r.description;封面=$r.poster;榜单='推荐榜';类型筛选=$TypeFilter;分类筛选=$Category
        采集时间=$r.captured_at;榜单范围=$(if($ReplayDir){'离线证据回放验证，不是本次实时采集'}else{'当前账号可见；排序可能包含个人兴趣'})
    }})
    $partial=$rows.Count -lt $Limit -or @($rows|Where-Object {-not $_.封面}).Count -gt 0
    $suffix=if($partial){'_部分'}else{''}
    if($ReplayDir){$suffix='_回放验证'+$suffix}
    $xlsx=Join-Path $OutDir ('红果推荐榜_'+$stamp+$suffix+'.xlsx')
    $writer=Join-Path $root 'ps-list-pipeline\scripts\make_xlsx.ps1'
    & $writer -Rows $rows -ImageColumn 封面 -Out $xlsx -SheetName 推荐榜 -ImageWidth 130 -FreezeHeader -Widths @(7,42,12,12,24,18,18,19,9,9,86,22,12,14,14,24,40)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($xlsx)
    try{if(@($zip.Entries|Where-Object {$_.FullName -like 'xl/media/*'}).Count -ne @($rows|Where-Object {$_.封面}).Count){throw 'Excel 内嵌封面数量不匹配，已保留原始数据'}}finally{$zip.Dispose()}
    if(-not $KeepData -and -not $failure -and -not $partial){
        $full=[IO.Path]::GetFullPath($job)
        if([IO.Directory]::GetParent($full).FullName -eq $OutDir -and [IO.Path]::GetFileName($full) -like '.hongguo-*'){Remove-Item -LiteralPath $full -Recurse -Force}
    }else{Write-Output "核查/续采数据：$job"}
    Write-Output "已导出 $($rows.Count)/$Limit 条：$xlsx"
    if($failure){throw "已导出已获得的数据；采集停止原因：$failure"}
    if($partial){throw '已导出部分结果并保留进度，但数量或封面未达到目标；不能标记为完整成功'}
}finally{$lock.Dispose()}

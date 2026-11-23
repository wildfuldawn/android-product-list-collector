param([ValidateRange(1,1000)][int]$Limit=50,[ValidateRange(1,500)][int]$MaxScreens=45,
    [string]$OutDir='hongguo-capture',[string]$AdbPath='',[string]$Serial='',
    [string]$TypeFilter='全部',[string]$Category='总榜',[string]$ReplayDir='',[switch]$Resume)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$project=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $project 'ps-list-pipeline\scripts\device.ps1')
if($ReplayDir){$frames=@(Get-ChildItem -LiteralPath $ReplayDir -Filter '*.xml' -File|Sort-Object Name);if(-not $frames.Count){throw '回放目录没有 XML/PNG 证据'}}
else{
    $adb=Find-ProductAdb $AdbPath;$devices=@(Get-ProductDevices $adb)
    if(-not $Serial){if($devices.Count -ne 1){throw '需要一台已授权设备，或用 -Serial 指定'};$Serial=$devices[0]}
    if($Serial -notin $devices -or $Serial -notmatch '^[A-Za-z0-9_.:-]+$'){throw '设备未授权或编号无效'}
}
$serial=$Serial
$OutDir=[IO.Path]::GetFullPath($OutDir)
if((Test-Path -LiteralPath (Join-Path $OutDir 'ranking.json')) -and -not $Resume){throw '输出已存在，请换新任务目录或显式 -Resume'}
$null=New-Item -ItemType Directory -Path $OutDir -Force
$images=Join-Path $OutDir 'posters'
$null=New-Item -ItemType Directory -Path $images -Force
$records=@{}
$contextFile=Join-Path $OutDir 'context.json'
if($Resume){
    $context=Get-Content -LiteralPath $contextFile -Raw -Encoding UTF8|ConvertFrom-Json
    if($context.typeFilter -ne $TypeFilter -or $context.category -ne $Category -or $context.board -ne '推荐榜'){throw '续采范围与检查点不一致'}
    if(([DateTimeOffset]::Parse($context.startedAt)).LocalDateTime.Date -ne (Get-Date).Date){throw '检查点来自其他日期，请新建任务目录重新采集，不能混合不同日期榜单'}
    $oldRows=Get-Content -LiteralPath (Join-Path $OutDir 'ranking.json') -Raw -Encoding UTF8|ConvertFrom-Json
    foreach($row in $oldRows){if([int]$row.rank -le $Limit){$records[[int]$row.rank]=$row}}
}else{
    [pscustomobject]@{board='推荐榜';typeFilter=$TypeFilter;category=$Category;startedAt=(Get-Date -Format o);scope='当前账号可见；页面排序含观看、互动与个人兴趣'}|ConvertTo-Json|Set-Content -LiteralPath $contextFile -Encoding UTF8
}
function Bounds($node){
    $m=[regex]::Match($node.GetAttribute('bounds'),'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]')
    if(-not $m.Success){return $null}
    [pscustomobject]@{x=[int]$m.Groups[1].Value;y=[int]$m.Groups[2].Value;r=[int]$m.Groups[3].Value;b=[int]$m.Groups[4].Value}
}
function Shot([string]$path){
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$adb;$psi.Arguments='-s '+$serial+' exec-out screencap -p';$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $p=[Diagnostics.Process]::Start($psi);$err=$p.StandardError.ReadToEndAsync()
    try{$fs=[IO.File]::Create($path);try{$p.StandardOutput.BaseStream.CopyTo($fs)}finally{$fs.Dispose()};$p.WaitForExit();if($p.ExitCode -ne 0){throw $err.Result}}finally{$p.Dispose()}
}
function Save-State {
    $path=Join-Path $OutDir 'ranking.json';$tmp=$path+'.tmp'
    @($records.Values | Sort-Object rank) | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
    if(Test-Path -LiteralPath $path){[IO.File]::Replace($tmp,$path,$path+'.bak');Remove-Item -LiteralPath ($path+'.bak')}else{[IO.File]::Move($tmp,$path)}
}
$stale=0
try{
for($screen=1;$screen -le $MaxScreens;$screen++){
    if($ReplayDir){
        if($screen -gt $frames.Count){break}
        $xml=[IO.File]::ReadAllText($frames[$screen-1].FullName)
        $sourceImage=[IO.Path]::ChangeExtension($frames[$screen-1].FullName,'.png')
    }else{
    $xml=Get-ProductUiXml $adb $serial '' '/sdcard/_hongguo_rank.xml'
    }
    [xml]$doc=$xml.Substring($xml.IndexOf('<hierarchy'))
    if(-not $doc.SelectSingleNode('//node[@text="推荐榜"]')){throw '已经离开推荐榜，停止避免混入其他页面'}
    $prefix=Join-Path $OutDir ('screen_{0:D3}_{1}' -f $screen,[guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($prefix+'.xml',$xml)
    if($ReplayDir){Copy-Item -LiteralPath $sourceImage -Destination ($prefix+'.png')}else{Shot ($prefix+'.png')}
    $image=[Drawing.Image]::FromFile($prefix+'.png')
    $added=0;$observed=@()
    try{
        if($image.Width -ge $image.Height){throw '当前为横屏，请将手机保持竖屏并重新核查榜单'}
        if($screen -eq 1 -and -not $Resume -and -not $doc.SelectSingleNode('//node[@text="1"]')){throw '未看到榜首，请先确认筛选并返回排名第1名再开始'}
        foreach($anchor in $doc.SelectNodes('//node[@text!=""]')){
            $t=$anchor.GetAttribute('text')
            if($t -notmatch '^\d{1,3}$'){continue}
            $rank=[int]$t
            if($rank -lt 1 -or $rank -gt $Limit){continue}
            $card=$anchor.ParentNode.ParentNode
            $texts=@($card.SelectNodes('./node[@text!=""]') | ForEach-Object {$_.GetAttribute('text')})
            $recIndex=-1
            for($i=0;$i -lt $texts.Count;$i++){if($texts[$i] -match '^[\d.]+[万亿+]*推荐$'){$recIndex=$i;break}}
            if($recIndex -lt 1){continue}
            $observed+=$rank
            $title=$texts[0]
            $meta=@();if($recIndex -gt 1){$meta=@($texts[1..($recIndex-1)])}
            $row=[ordered]@{rank=$rank;title=$title;type='';category='';people='';recommend=$texts[$recIndex];heat='';likes='';rating='';tag='';description='';poster='';source_screen=$screen;captured_at=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')}
            if($meta.Count -ge 1){$row.type=$meta[0]}
            if($meta.Count -ge 2){$row.category=$meta[1]}
            if($meta.Count -ge 3){$row.people=$meta[2..($meta.Count-1)] -join '、'}
            $fieldTexts=@($card.SelectNodes('.//node[@text!=""]') | ForEach-Object {$_.GetAttribute('text')})
            $fieldStart=[Array]::IndexOf($fieldTexts,$texts[$recIndex])+1
            foreach($value in $fieldTexts[$fieldStart..($fieldTexts.Count-1)]){
                if($value -match '^[\d.]+[万亿+]*热度$'){$row.heat=$value}
                elseif($value -match '^[\d.]+[万亿+]*次点赞$'){$row.likes=$value}
                elseif($value -match '^评分([\d.]+)$'){$row.rating=$Matches[1]}
                elseif($value -eq '新剧'){$row.tag=$value}
                elseif($value.Length -gt 1 -and $value -notmatch '^[“”]$' -and -not $row.description){$row.description=$value}
            }
            if($records.ContainsKey($rank)){
                $old=$records[$rank]
                if($old.title -ne $title){throw "排名 $rank 的剧名在采集中变化，停止以免混合榜单"}
                foreach($key in @('type','category','people','recommend','heat','likes','rating','tag','description','poster')){if(-not $row[$key] -and $old.$key){$row[$key]=$old.$key}}
            }else{$added++}
            $cover=Bounds $anchor.ParentNode
            $viewport=Bounds $card.ParentNode
            if($cover -and $viewport){
                $w=$cover.r-$cover.x;$h=$cover.b-$cover.y
                if($w -gt 50 -and $h -ge 1.30*$w -and $h -le 1.65*$w -and $cover.y -ge $viewport.y -and $cover.b -le [Math]::Min($image.Height,$viewport.b)){
                    $path=Join-Path $images ('{0:D2}.png' -f $rank)
                    $rect=New-Object Drawing.Rectangle($cover.x,$cover.y,$w,$h)
                    $bitmap=New-Object Drawing.Bitmap($w,$h);$g=[Drawing.Graphics]::FromImage($bitmap)
                    try{$g.DrawImage($image,(New-Object Drawing.Rectangle(0,0,$w,$h)),$rect,[Drawing.GraphicsUnit]::Pixel);$bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png);$row.poster=$path}finally{$g.Dispose();$bitmap.Dispose()}
                }
            }
            $records[$rank]=[pscustomobject]$row
        }
        $width=$image.Width;$height=$image.Height
    }finally{$image.Dispose()}
    Save-State
    $withImage=@($records.Values | Where-Object {$_.poster}).Count
    $complete=@($records.Values | Where-Object {$_.poster -and $_.heat -and $_.likes -and $_.description}).Count
    Write-Output "第 $screen 屏：可见排名 $($observed -join ',')；新增 $added，累计 $($records.Count)/$Limit；封面 $withImage；完整信息 $complete"
    if($records.Count -ge $Limit -and $withImage -ge $Limit){break}
    $stale=if($added -gt 0){0}else{$stale+1}
    if($stale -ge 5){Write-Output '连续多屏无新增，停止并保留实际结果';break}
    $x=[int]($width*0.70);$from=[int]($height*0.87);$to=[int]($height*0.42)
    if(-not $ReplayDir){$null=Invoke-ProductAdb $adb @('-s',$serial,'shell',"input swipe $x $from $x $to 550");Start-Sleep -Milliseconds 1100}
}
}finally{if($records.Count){Save-State}}
Write-Output ('结果：'+(Join-Path $OutDir 'ranking.json'))

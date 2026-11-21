# Shared offline-testable parsing and crop rules. No Python dependency.
$script:ProductLayoutOverrides=@{}
function Get-ListConfig([string]$App) {
    $config=@{
        xhs = @{ name='小红书'; headerY=600; left=@(52,593); right=@(679,1220); gap=4; minH=0; minLen=8; maxLen=80 }
        dewu = @{ name='得物'; headerY=560; left=@(51,585); right=@(687,1221); gap=64; minH=55; minLen=10; maxLen=130 }
        dy = @{ name='抖音'; headerY=560; left=@(43,594); right=@(671,1222); gap=8; minH=0; minLen=8; maxLen=130 }
    }[$App]
    if ($script:ProductLayoutOverrides.ContainsKey($App)) {
        foreach($key in $script:ProductLayoutOverrides[$App].Keys) { $config[$key]=$script:ProductLayoutOverrides[$App][$key] }
    }
    return $config
}
function Set-ProductLayoutProfile($Profile,[string]$App,[int]$Width,[int]$Height) {
    if (-not $Profile.layout -or $Profile.schemaVersion -ne 1 -or $Profile.app -ne $App -or $Profile.screenWidth -ne $Width -or $Profile.screenHeight -ne $Height) {
        throw '布局配置的平台或屏幕尺寸不匹配，请为当前手机重新检查配置'
    }
    $overrides=@{}
    foreach($property in $Profile.layout.PSObject.Properties) {
        $key=$property.Name; $value=$property.Value
        if ($key -in @('left','right')) {
            if (@($value).Count -ne 2 -or $value[0] -lt 0 -or $value[1] -gt 1272 -or $value[1] -le $value[0]) { throw '图片列边界配置无效' }
            $overrides[$key]=@([int]$value[0],[int]$value[1])
        } elseif ($key -in @('headerY','gap','minH','minLen','maxLen')) {
            $parsed=0
            if (-not [int]::TryParse([string]$value,[ref]$parsed) -or $parsed -lt 0 -or $parsed -gt 2000) { throw '布局参数必须为 0 到 2000 的整数' }
            $overrides[$key]=$parsed
        } else { throw "不支持的布局配置项：$key" }
    }
    $script:ProductLayoutOverrides=@{}; $script:ProductLayoutOverrides[$App]=$overrides
}
function Test-Quote([string]$Text) {
    return $Text.Length -lt 80 -and ($Text -match '^[“"「]|[”"」]$')
}
function ConvertTo-ReferenceNodes([object[]]$Nodes, [int]$Width) {
    if ($Width -lt 1) { throw '无效的屏幕宽度' }
    $scale=1272.0/$Width
    foreach ($n in $Nodes) {
        $copy=$n.PSObject.Copy()
        foreach ($key in @('x1','y1','x2','y2','w','h','cx')) { $copy.$key=[int][Math]::Round($n.$key*$scale) }
        $copy
    }
}
function ConvertTo-DeviceBox($Box, [int]$Width, [int]$Height) {
    $scale=$Width/1272.0
    $x=[int][Math]::Floor($Box.x*$scale); $y=[int][Math]::Floor($Box.y*$scale)
    $right=[Math]::Min($Width,[int][Math]::Ceiling(($Box.x+$Box.w)*$scale))
    $bottom=[Math]::Min($Height,[int][Math]::Ceiling(($Box.y+$Box.h)*$scale))
    if ($x -lt 0 -or $y -lt 0 -or $right -le $x -or $bottom -le $y) { throw '裁图区域越界，请检查 App 布局' }
    [pscustomobject]@{x=$x;y=$y;w=$right-$x;h=$bottom-$y}
}
function Test-Shop([string]$Text) {
    return $Text.Length -le 22 -and $Text -match '店$' -and $Text -notmatch '销量|已售|[¥￥]|\d+\s*年老店|好评率'
}
function Read-ListNodes([string]$XmlText) {
    $start=$XmlText.IndexOf('<hierarchy')
    if ($start -lt 0) { throw '没有有效的界面 XML，停止以保留已有数据' }
    $doc=New-Object System.Xml.XmlDocument
    $doc.XmlResolver=$null
    $doc.LoadXml($XmlText.Substring($start))
    foreach ($el in $doc.SelectNodes('//node')) {
        $t=$el.GetAttribute('text')
        if (-not $t) { $t=$el.GetAttribute('content-desc') }
        $t=($t -replace '[\u200b-\u200d]', '' -replace '[\r\n]', ' ').Trim()
        $b=[regex]::Match($el.GetAttribute('bounds'), '^\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]$')
        $isPhoto=$el.GetAttribute('resource-id') -match '/search_image$'
        if ((-not $t -and -not $isPhoto) -or -not $b.Success) { continue }
        $x1=[int]$b.Groups[1].Value; $y1=[int]$b.Groups[2].Value
        $x2=[int]$b.Groups[3].Value; $y2=[int]$b.Groups[4].Value
        [pscustomobject]@{t=$t; x1=$x1; y1=$y1; x2=$x2; y2=$y2; w=$x2-$x1; h=$y2-$y1; cx=($x1+$x2)/2; isPhoto=$isPhoto}
    }
}
function Test-ListTitle($Node, [string]$App, $Config) {
    $t=$Node.t
    if ($Node.y1 -lt $Config.headerY -or $Node.w -lt 280 -or $Node.h -lt $Config.minH -or
        $t.Length -lt $Config.minLen -or $t.Length -gt $Config.maxLen) { return $false }
    if ($t -match '[¥￥]|已售|人付款|人加购|好评率|退货包运费|^包邮|直播中|^\d+$') { return $false }
    if ($App -eq 'xhs') {
        if ((Test-Quote $t) -or (Test-Shop $t)) { return $false }
        if ($t -match 'TOP\s*\d|近期店铺|本周热销|销量榜|回购榜|好评榜|立减|满\s*\d+\s*减|券后|入会价|关注后|今日发|人购买|回头客|新客|销量\s*[\d.]|\d+\s*年老店|[\d.]+\s*分|周销|月销|小时.*(购买|发货)|^上新\d') { return $false }
    } elseif ($App -eq 'dewu') {
        if ($t -match '关注|榜|降价') { return $false }
    } elseif ($t -match '人看过|回头客|好评|粉丝|官方正品|直播') { return $false }
    return $true
}
function Get-ListCards([object[]]$Nodes, [string]$App) {
    $cfg=Get-ListConfig $App
    $titles=@($Nodes | Where-Object { Test-ListTitle $_ $App $cfg } | Sort-Object y1,x1)
    $seen=@{}
    foreach ($c in $titles) {
        if ($seen.ContainsKey($c.t)) { continue }
        $seen[$c.t]=$true
        $left=$c.cx -lt 636
        $next=$titles | Where-Object { ($_.cx -lt 636) -eq $left -and $_.y1 -gt $c.y1 } | Select-Object -First 1
        $end=$c.y1+450
        if ($next) { $end=[Math]::Min($end,$next.y1) }
        $below=@($Nodes | Where-Object { ($_.cx -lt 636) -eq $left -and $_.y1 -gt $c.y1 -and $_.y1 -lt $end } | Sort-Object y1)
        $price=''; $sold=''; $shop=''; $sales=''; $old=''; $rate=''
        foreach ($n in $below) {
            $priceText=$n.t
            # Dewu exposes large price digits as spaced text (e.g. ¥ 4 8).
            if ($App -eq 'dewu' -and $priceText -match '^[¥￥]\s*[\d.\s]+$') { $priceText=$priceText -replace '\s','' }
            if (-not $price -and $priceText -match '[¥￥]\s*(\d+(?:\.\d+)?)') { $price='¥'+$Matches[1] }
            if (-not $sold -and $n.t -match '已售\s*([\d.]+[万+]*)|([\d.]+[万+]*)\s*人付款') {
                $sold=if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
            }
            if (-not $shop -and (Test-Shop $n.t)) { $shop=$n.t }
            if ($n.t -match '销量\s*([\d.]+[万+]*)') { $sales=$Matches[1] }
            if ($n.t -match '(\d+)\s*年老店') { $old=$Matches[1]+'年' }
            if ($n.t -match '好评率\s*([\d.]+)\s*%') { $rate=$Matches[1]+'%' }
        }
        if ($App -eq 'xhs' -and -not $price -and -not $shop) { continue }
        $quoteY=0
        if ($App -eq 'xhs') {
            $q=$Nodes | Where-Object {
                ($_.cx -lt 636) -eq $left -and $_.y2 -le $c.y1 -and ($c.y1-$_.y2) -le 130 -and (Test-Quote $_.t)
            } | Sort-Object y1 | Select-Object -First 1
            if ($q) { $quoteY=$q.y1 }
        }
        $photo=$null
        if ($App -eq 'dewu') {
            $photo=$Nodes | Where-Object { $_.isPhoto -and ($_.cx -lt 636) -eq $left -and $_.y1 -lt $c.y1 -and $_.y2 -ge $c.y1 } | Sort-Object y1 -Descending | Select-Object -First 1
        }
        [pscustomobject]@{t=$c.t; y1=$c.y1; cx=$c.cx; quoteY=$quoteY; photo=$photo; price=$price; sold=$sold; shop=$shop; sales=$sales; old=$old; goodrate=$rate}
    }
}
function Get-ListImageBox($Card, [string]$App, [int]$Width=1272, [int]$Height=2772) {
    if ($Width -ne 1272 -or $Height -lt 800) { throw '请先将坐标按屏幕宽度归一化；仅支持竖屏商品列表' }
    $cfg=Get-ListConfig $App
    $col=if ($Card.cx -lt 636) { $cfg.left } else { $cfg.right }
    $w=$col[1]-$col[0]
    $bottom=$Card.y1-$cfg.gap
    if ($Card.quoteY) { $bottom=[Math]::Min($bottom,$Card.quoteY-6) }
    $top=$bottom-$w
    if ($App -eq 'dewu' -and $Card.photo) {
        $p=$Card.photo
        if ($p.h -lt 0.9*$p.w) { return $null }
        $top=$p.y1
        $col=@($p.x1,$p.x2)
        $w=$p.w
    }
    if ($top -lt $cfg.headerY -or $bottom -gt $Height) { return $null }
    if ($bottom-$top -lt 0.7*$w) { return $null }
    return [pscustomobject]@{x=$col[0]; y=$top; w=$w; h=$bottom-$top; bottom=$bottom}
}
function Save-ListCheckpoint([object[]]$Rows, [string]$Csv) {
    $tmp=$Csv+'.tmp'
    if ($Rows.Count) { $Rows | Export-Csv -LiteralPath $tmp -NoTypeInformation -Encoding UTF8 }
    else { '"序号","应用","标题","价格","已售","店铺","好评率","店铺销量","几年老店","首图","图片说明"' | Set-Content -LiteralPath $tmp -Encoding UTF8 }
    if (Test-Path -LiteralPath $Csv) {
        [IO.File]::Replace($tmp,$Csv,$Csv+'.bak')
        Remove-Item -LiteralPath ($Csv+'.bak') -Force
    }
    else { [IO.File]::Move($tmp,$Csv) }
}

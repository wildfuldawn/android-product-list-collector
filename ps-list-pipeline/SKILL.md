---
name: ps-list-pipeline
description: 使用 Windows PowerShell 5.1、.NET 与 ADB，采集得物、小红书、抖音商品搜索列表并导出带图 Excel。无需 Python、Office、OCR 服务或抓包。
---

# 手机商品列表采集

只读取商品搜索结果，不进入详情，不处理登录凭据，不绕过平台验证。目标 App 需已登录，手机已授权 ADB、亮屏并解锁。当前坐标针对 1272×2772 屏幕。

## 日常使用

双击根目录 `启动采集.cmd`，选择平台、关键词、目标数量。中文关键词请先在手机手动搜索并进入商品结果页，然后在程序的关键词提示处直接回车。

也可在 scripts 目录执行：

```powershell
.\run_all.ps1 -App xhs -Keyword socks -Limit 50
.\run_all.ps1 -App dewu -Keyword socks -Limit 10
.\run_all.ps1 -App dy -Keyword socks -Limit 10
# 手机已搜好：
.\run_all.ps1 -App xhs -Keyword current -Limit 10 -NoNav
```

`-App` 可选 xhs/dewu/dy。`-AdbPath` 或 `ADB_PATH` 可指定 adb.exe，否则从 PATH 查找。双击入口可使用根目录 tools/adb.exe。连接时只保留一台已授权设备。

正常出表后仅保留一个带图 `.xlsx`，图片已嵌入。目标不足时文件名含“部分”。失败时保留临时进度，能出表则同时保存部分 Excel。不要在出表成功前删除检查点。

## 解析与边界

- `list_core.ps1` 用 XML 解析器解码文本，过滤评价和促销标签，分列关联价格、销量与店铺。
- 小红书评价行以其上边界减 6 像素作为裁图下边界，支持普通引号及中文引号。TOP、近期店铺、本周热销、销量榜等不作为标题。
- 得物自动导航会打开搜索输入区，并核对结果页顶部关键词。分隔数字 `¥ 4 8` 合并成 48，不取随后展示的划线价。优先按搜索图片节点确定图片上边界。
- 缺少列表字段时留空。抖音自绘价格可能不可读，本版本不包含 OCR 补充工具。
- 按标题去重，同名不同商品可能合并。图片不完整时跳过，不承诺所有列表商品都能收齐。达到目标立即停止，连续四屏实际无新增则停止。
- 屏幕裁图可能含悬浮购物车、返回顶部等遮挡；不伪造隐藏像素。换手机或 App 布局变化时需重新校准。

## 检查点与核查

每接受一条记录，以完整临时文件原子替换 CSV 检查点。异常或中断时，之前已保存的记录仍可读取。裁图使用独立文件名，重复运行不会覆盖旧图片。

分步采集会保留 CSV 和图片：

```powershell
.\ps_collect.ps1 -App xhs -Limit 50 -Csv progress.csv -ImageDir images
# 重新运行并补足累计 50 条，手机需停在相应商品页：
.\ps_collect.ps1 -App xhs -Limit 50 -Csv progress.csv -ImageDir images -Resume
.\make_xlsx.ps1 -Csv progress.csv -ImageColumn 首图 -Out result.xlsx -FreezeHeader
```

`run_all.ps1 -KeepData` 成功后也保留核查数据。`ps_collect.ps1 -KeepScreen` 保留每屏 PNG/XML；`-ReplayDir` 可离线回放同名 PNG/XML 文件。`-MaxScroll` 限制屏数，默认 100。原始图片、设备地址、账号数据和采集结果不要上传 GitHub。

## 验证

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\tests\test_list.ps1
```

回归覆盖促销标签、ASCII 引号/XML 实体、评价裁剪边界、分列字段、得物分隔数字与图片边界、目标数量、续采和异常检查点。2026-11-20 实机验证小红书 6 条（3 屏）、得物 4 条；抖音本轮未做实机重测。

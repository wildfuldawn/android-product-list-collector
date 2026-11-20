# 手机商品列表采集（PowerShell 版）

通过 ADB 读取安卓手机上得物、小红书、抖音的商品搜索列表，保存商品信息与首图，导出带图 Excel。只需 Windows 自带的 PowerShell/.NET 和 ADB，**无需安装 Python 或 Office**。

## 环境

- Windows 10/11，使用系统自带的 PowerShell 5.1。
- Android Platform Tools：将 adb 加入 PATH，或通过 `ADB_PATH` 环境变量指定 adb.exe 的完整路径。
- 手机已开启 USB 或无线调试，并由用户确认连接；目标 App 已登录，手机保持亮屏、解锁。

先执行 `adb devices`，确认手机状态为 `device`。

## 开始采集

双击根目录的 `启动采集.cmd`，选择平台、输入搜索词和数量。手机已手动进入商品搜索结果时，搜索词直接回车即可使用当前页面。中文搜索词请在手机上输入。

在项目根目录打开 PowerShell：

```powershell
cd ps-list-pipeline/scripts

# 得物：采集 50 条
.\run_all.ps1 -App dewu -Keyword Nike -Limit 50

# 小红书：采集 50 条
.\run_all.ps1 -App xhs -Keyword adidas -Limit 50

# 抖音：采集 50 条
.\run_all.ps1 -App dy -Keyword nike -Limit 50
```

`-Limit` 指定目标条数，程序滑动列表继续采集。商品不足或页面解析失败时，实际条数可能小于目标。

中文关键词请先在手机上手动搜索并进入商品结果页，再加 `-NoNav`，例如：

```powershell
.\run_all.ps1 -App dewu -Keyword x -Limit 50 -NoNav
```

此时 `-Keyword` 只是必填占位参数，程序使用手机当前页面，不重新搜索。

## 输出

双击入口的结果在 `ps-list-pipeline/结果/`；命令行默认在运行目录的 `out/`。成功后只保留一个带图 `.xlsx`，图片已嵌入文件，不依赖外部目录。不需要安装 Excel 来生成文件。中途出错会保留临时检查点，已有记录可续采；不足目标时文件名带“部分”。

## 字段与适用范围

采集商品标题、列表上可读取的价格、已售和首图。**抖音部分价格属于自绘文字，无障碍树无法读取，此版本会留空。** 不提供 OCR 补充工具。

当前坐标针对 1272×2772 屏幕，换手机或 App 布局变化时需校准。2026-11-20 使用 Windows PowerShell 5.1 实机验证了小红书 6 条（3 屏）和得物 4 条；抖音本轮仅做解析回归检查，未实机重测。

本轮修复：小红书评价行从其上边界排除，支持普通与中文引号；过滤 TOP、近期店铺、本周热销等促销标签；得物修正搜索入口、分隔价格数字（`¥ 4 8` → `¥48`）和图片边界。按标题去重，达到目标立即停止，每条记录保存一次检查点；相同标题的不同商品可能合并，不能据此保证完整覆盖。屏幕上的悬浮按钮可能遮挡裁图，不会伪造被遮挡像素。

离线回归（不连接手机）：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ps-list-pipeline/tests/test_list.ps1
```

更多参数和解析原理见 [快速开始](ps-list-pipeline/README.md) 与 [使用文档](ps-list-pipeline/SKILL.md)。设备连接信息、截图、采集结果不应上传。

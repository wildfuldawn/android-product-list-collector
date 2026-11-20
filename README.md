# 手机商品列表采集（PowerShell 版）

通过 ADB 读取安卓手机上得物、小红书、抖音的商品搜索列表，保存商品信息与首图，导出带图 Excel。只需 Windows 自带的 PowerShell/.NET 和 ADB，**无需安装 Python 或 Office**。

## 环境

- Windows 10/11，使用系统自带的 PowerShell 5.1。
- Android Platform Tools：将 adb 加入 PATH，或通过 `ADB_PATH` 环境变量指定 adb.exe 的完整路径。
- 手机已开启 USB 或无线调试，并由用户确认连接；目标 App 已登录，手机保持亮屏、解锁。

先执行 `adb devices`，确认手机状态为 `device`。

## 开始采集

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

默认输出在运行目录的 `out/`：带首图的 `.xlsx`、原始 `.csv` 和 `imgs/<App>/` 图片目录。不需要安装 Excel 来生成文件。

## 字段与适用范围

采集商品标题、列表上可读取的价格、已售和首图。**抖音部分价格属于自绘文字，无障碍树无法读取，此版本会留空。** 不提供 OCR 补充工具。

当前坐标针对原设备屏幕，换手机或 App 布局变化时需校准。本次完成 PowerShell 语法检查，未重新进行手机实时采集验证。

更多参数和解析原理见 [快速开始](ps-list-pipeline/README.md) 与 [使用文档](ps-list-pipeline/SKILL.md)。设备连接信息、截图、采集结果不应上传。

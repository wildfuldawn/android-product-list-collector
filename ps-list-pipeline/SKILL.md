---
name: ps-list-pipeline
description: 不装 Python、不装 Office，只用 Windows 自带的 PowerShell + .NET，通过 adb 从安卓手机采集得物/小红书/抖音的商品搜索结果，把标题、价格、已售和商品首图导出成带图 Excel（xlsx）。适合直接把整个文件夹交给 AI 助手或同事，双击/一条命令就能跑。
whenToUse: 需要在**没装 Python**的 Windows 机器上按关键词批量抓这三个平台的商品列表并生成带图表格时；或者要把采集能力打包分享给别人（对方只有 Windows + adb 也能用）。
user-invocable: true
metadata:
  tags: [powershell, adb, ui-automation, excel, zero-python, dewu, xiaohongshu, douyin]
  requires: Windows 10/11（自带 PowerShell 5.1 与 .NET）；adb（platform-tools）；手机开 USB/无线调试；对应 App 已登录
---

# 纯 PowerShell 商品采集（零 Python / 零 Office）

三个平台一套脚本：**得物、小红书、抖音**。产出带首图的 Excel。
所有能力来自 Windows 自带组件，不需要 `pip install`、不需要装 Excel。

## 一、为什么能不用 Python

| 需要什么 | 用什么（全部系统自带） |
|---|---|
| 读界面结构 | `adb shell uiautomator dump` + PowerShell 正则解析 XML |
| 截图 | `adb exec-out screencap -p`（.NET 进程管道取二进制，避免被 PS 破坏） |
| 裁首图 / 转 JPEG | `System.Drawing`（GDI+，`.ps1` 里直接调） |
| 生成带图 Excel | `System.IO.Compression.ZipArchive` 手写 OOXML（xlsx = zip + XML） |
| CSV 读写 | `Export-Csv` / `Import-Csv` |

## 二、前置检查（30 秒）

```powershell
# 1) adb 可用
adb version

# 2) 手机连上（IP 与端口在手机「无线调试」页面）
adb connect <手机IP>:<端口>
adb devices          # 必须能看到 xxx device

# 3) 手机别锁屏 + 保持常亮
adb shell input keyevent KEYCODE_WAKEUP
adb shell svc power stayon true
```

> `adb` 不在 PATH 时，脚本会依次找：`-AdbPath` 参数 → 环境变量 `ADB_PATH` →
> `D:\Codex\pachong\...\adb.exe` → PATH。换机器只需设 `ADB_PATH`。

## 三、一条命令跑完

```powershell
cd scripts

.\run_all.ps1 -App dewu -Keyword Nike   -Limit 20
.\run_all.ps1 -App xhs  -Keyword adidas -Limit 20
.\run_all.ps1 -App dy   -Keyword ai     -Limit 20
```

产物：

```
out\<App>_<时间>.xlsx      带首图的表格
out\<App>_<时间>.csv       原始数据（序号/应用/标题/价格/已售/首图）
out\imgs\<App>\001.jpg …   首图（534×534 ~ 541×541，JPEG q88）
```

### 分步执行（更可控）

```powershell
.\ps_nav.ps1     -App dewu -Keyword Nike        # 1) 导航到「商品」结果页
.\ps_collect.ps1 -App dewu -Limit 20 -Csv d.csv -ImageDir imgs\dewu   # 2) 采集
.\make_xlsx.ps1  -Csv d.csv -ImageColumn 首图 -Out d.xlsx -ImageWidth 160 -FreezeHeader  # 3) 出表
```

### 跳过导航（推荐给自动化/助手用）

导航靠点坐标，受 App 版本和弹窗影响。**更稳的做法**是先人工（或助手）把 App 停在
「搜索结果 → 商品」页，然后：

```powershell
.\ps_collect.ps1 -App dewu -Limit 20 -Csv d.csv -ImageDir imgs\dewu
# 或
.\run_all.ps1 -App dewu -Keyword x -Limit 20 -NoNav
```

## 四、参数

| 脚本 | 参数 | 说明 |
|---|---|---|
| `run_all.ps1` | `-App` `-Keyword` `-Limit` `-OutDir` `-NoNav` `-NoExcel` | 一键流程 |
| `ps_nav.ps1` | `-App` `-Keyword` `-AdbPath` | 关键词只能 ASCII |
| `ps_collect.ps1` | `-App` `-Limit` `-Csv` `-ImageDir` `-AdbPath` `-KeepScreen` | 采当前页 |
| `make_xlsx.ps1` | `-Csv` `-Rows` `-ImageFolder` `-ImageColumn` `-Out` `-ImageWidth` `-ImageHeight` `-Widths` `-FreezeHeader` `-SheetName` | 出表；也可直接把一个图片文件夹做成表 |

## 五、各平台差异（解析规则已内置）

| 平台 | 标题在哪 | 图片边界 | 价格 |
|---|---|---|---|
| 得物 `dewu` | `text`，多行块高 ≥55px（标签行只有 47px，靠高度区分） | 标题 y − 64px 起，高度=列宽 | `¥ 1 2 9` 数字间带空格，需合并 |
| 小红书 `xhs` | `text`，需排除评价引号 `“…”`、店铺名、促销语 | 标题 y − 8px，且要让开评价浮层 | `券后¥269.已售2527` 取数字 |
| 抖音 `dy` | **`content-desc`**（不是 text） | 标题 y − 8px | 树里没有价格，只能留空或另做 OCR |

列边界（1272 宽屏幕）：得物 `51–585 / 687–1221`，小红书 `52–593 / 679–1220`，抖音 `43–594 / 671–1222`。

## 六、耗时

| 数量 | 耗时 | 说明 |
|---|---|---|
| 3 条 | 15~25 秒 | 含 dump + 截图 + 裁图 |
| 20 条 | 2~3 分钟 | 每屏 2~6 条，需滚动 |
| 100 条 | 8~12 分钟 | 比 Python 版慢约 20% |

## 七、会踩的坑

| 现象 | 原因 | 解决 |
|---|---|---|
| `C:\...ps1` 报「Missing '=' operator」 | `.ps1` 存成了无 BOM 的 UTF-8，PS 5.1 按 GBK 读中文 | 用记事本/VS Code 另存为 **UTF-8 with BOM**（本 skill 里的脚本已带 BOM） |
| `NativeCommandError`：adb 的 stderr 变终止错误 | 脚本开了 `$ErrorActionPreference='Stop'` | 用 `2>&1` 捕获，并把偏好设为 `Continue` |
| 截图变成乱码/0 字节 | 用 `>` 重定向二进制 | 必须走 .NET 进程管道读取 stdout 流 |
| 解析 0 个节点 | App 不在前台（被切走/进了直播间） | 重新导航；`ps_collect` 会报「没解析到商品卡」 |
| 抖音抓到的不是搜索词的结果 | 输入框没聚焦，`input text` 打到了空处 | 先定位 `EditText` 类节点再输入；中文关键词请手动搜 |
| 抖音默认单列 | 排序条右侧有「单列/双列」切换 | `ps_nav.ps1` 会自动点一次「单列」切到双列 |
| 图片上下被切 | 首图高度不等于列宽 | 调 `imageGap`（脚本顶部 `$cfg`）；或改用「多裁」策略 |
| xlsx 打开提示修复 | 手写 OOXML 结构错 | 校验 zip 内 6 个必需部件：`[Content_Types].xml`、`_rels/.rels`、`xl/workbook.xml`、`xl/_rels/workbook.xml.rels`、`xl/worksheets/sheet1.xml`、`xl/styles.xml` |

## 八、验收标准

- [ ] `adb devices` 有 device
- [ ] `ps_collect` 输出的 CSV 行数 = `-Limit`，`首图` 列指向存在的 jpg
- [ ] 抽 1~2 张图打开看，是商品主图（不是搜索栏、不是相邻卡）
- [ ] xlsx 行数 = CSV 行数，图片在「首图」列对齐
- [ ] Excel 打开无「修复」提示

## 九、文件

```
scripts/
├── run_all.ps1      一键：导航 → 采集 → 出表
├── ps_nav.ps1       导航到「商品」结果页（dewu / xhs / dy）
├── ps_collect.ps1   采集当前页：dump → 解析 → 截图 → 裁图 → CSV
└── make_xlsx.ps1    CSV → 带图 xlsx（也可直接吃一个图片文件夹）
```

## 十、给 AI 助手（WorkBuddy 等）的执行提示

把这个文件夹整体交给助手，并按以下顺序让它执行：

1. 读本 `SKILL.md`，确认 `adb devices` 有设备
2. **优先用 `-NoNav`**：先让助手 `adb shell am start` 打开 App 并把关键词搜好、
   切到「商品」页，再跑 `ps_collect.ps1`（避免导航点坐标不稳）
3. 若必须自动导航，用 `run_all.ps1`，并在失败时回退到第 2 步的人工/半自动路径
4. 中文关键词：`adb shell input text` 只能 ASCII。要中文，装 ADBKeyboard 后
   `adb shell am broadcast -a ADB_INPUT_B64 --es msg <base64>`，或直接手输

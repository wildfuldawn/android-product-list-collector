---
name: dy-list-pipeline
description: 用 PC 通过 adb 驱动安卓上的抖音，按关键词采集「商城 → 搜索 → 商品」结果列表：标题/价格/已售/促销语/店铺/店铺标签/展示图，导出带图 xlsx。不进入商品详情页、不抓包、不改 App、不用浏览器。
whenToUse: 用户要按关键词批量看抖音商城商品（选品/比价/竞品调研），字段只要列表页能看到的；或明确说"抖音不用详情页""只要搜索页信息"时。需要 SKU/详情/评论时另想办法（抖音详情页同理可做，本 skill 未覆盖）。
user-invocable: true
metadata:
  tags: [douyin, adb, ui-automation, ocr, list-scraping, excel, no-detail-page]
  requires: 手机开 USB/无线调试；抖音已登录；Windows 10/11（用系统自带 OCR）；Python 3.10+ 且装了 openpyxl、Pillow
---

# 抖音商城搜索结果采集（不进详情页）

只做一件事：**把关键词的抖音商城商品搜索结果翻完，导出带展示图的表格。**

不用抓包、不注入、不改包，两步数据来源：

```
adb uiautomator dump   → 标题、已售xx件、回头客xx、十万粉丝、好评率
整屏截图 + Windows OCR  → 价格 ¥xx、促销语、店铺名
整屏截图裁图            → 每条一张展示图
```

## 一、为什么必须用 OCR

抖音的商品卡把关键信息画在**自绘视图**里，无障碍树和 View 树都读不到：

| 字段 | uiautomator dump | Frida 遍历 View 树 | 截图 OCR |
|---|---|---|---|
| 标题 | ✅（在 content-desc） | ✅ | ✅ |
| 已售 / 回头客 / 粉丝 | ✅（在 content-desc） | ✅ | ✅ |
| **价格 ¥xx** | ❌ | ❌（TextView.getText 为空） | ✅ |
| **促销语** | ❌ | ❌ | ✅ |
| **店铺名** | ❌ | ❌ | ✅ |

所以标题走 dump、价格走 OCR，两条路合并成一张卡。

## 二、前置条件

```powershell
adb connect <手机IP>:5555
adb devices                        # 必须是 device
adb shell input keyevent KEYCODE_WAKEUP
adb shell svc power stayon true
```

抖音已登录。**关键词只能 ASCII**（`adb shell input text` 不支持中文）：
- 英文/数字（`ai`、`phone`）：脚本自己搜
- 中文：先在手机上手动搜好并点「商品」页签，再跑 `--no-nav`

**OCR 依赖 Windows 自带识别引擎**，需要系统里有 `zh-Hans-CN` 语言包：

```powershell
# 检查可用 OCR 语言
powershell -NoProfile -Command "[Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime] | Out-Null; ([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages) | % { $_.LanguageTag }"
```

输出里要能看到 `zh-Hans-CN`。没有就去「设置 → 时间和语言 → 语言 → 添加语言 → 中文(简体)」装一下。

## 三、用法

```powershell
cd scripts

# 0) 先探一下当前屏幕能不能正确解析（强烈建议每次换关键词先跑）
python dy_collect.py --probe

# 1) 采 100 条
python dy_collect.py --keyword ai --limit 100 --out dy_ai.json

# 2) 出表
python dy_build_xlsx.py --json dy_ai.json --out 抖音_AI_100.xlsx

# 3) 继续再采 100 条（从当前位置往下翻，不重复）
python dy_collect.py --no-nav --seen dy_ai.json --start-index 101 `
                     --limit 100 --out dy_ai_2.json --max-scroll 70

# 4) 合并两批
python -c "import json;a=json.load(open('dy_ai.json',encoding='utf-8'));b=json.load(open('dy_ai_2.json',encoding='utf-8'));m=a+b;[r.update(序号=i) for i,r in enumerate(m,1)];json.dump(m,open('dy_all.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)"

# 5) 出合并表
python dy_build_xlsx.py --json dy_all.json --out 抖音_AI_200.xlsx
```

### 参数

| 参数 | 作用 |
|---|---|
| `--keyword` | 搜索关键词（ASCII） |
| `--limit` | 采多少条，默认 100 |
| `--out` | 结果 json |
| `--imgdir` | 图片目录，默认 `images/dy` |
| `--no-nav` | 不重新导航，从当前滚动位置继续 |
| `--seen` | 已有 json，按其标题去重 |
| `--start-index` | 序号起始值（继续采集传 101） |
| `--max-scroll` | 最多翻多少屏，默认 60 |
| `--probe` | 只解析当前屏幕并裁几张样图，不出数据 |

## 四、产出字段与实测覆盖

| 列 | 覆盖（200 条样本） | 来源 |
|---|---|---|
| 序号 | 200/200 | — |
| 商品标题 | 200/200 | dump |
| 价格 | 159/200 | OCR |
| 已售 | 162/200 | dump |
| 促销语 | 180/200 | OCR |
| 店铺 | 94/200 | OCR |
| 店铺标签 | 59/200 | dump（回头客/粉丝/好评率/官方正品） |
| 展示图 | 200/200 | 截图裁图 |

**价格、店铺覆盖率偏低的原因**（不是漏抓）：
1. 卡片贴屏幕上下沿被截断，OCR 只读到半行
2. 带「直播中」角标的卡片，角标压在价格区上
3. 部分卡片本来就不显示店铺名（只有"回头客xx"标签）

## 五、耗时（实测，一加 15 / 1272×2772）

| 场景 | 耗时 | 备注 |
|---|---|---|
| 前 100 条 | **约 4.5 分钟** | 32 屏，每屏 3~5 条 |
| 再 100 条 | **约 4 分钟** | 双列每屏产出比小红书高 |
| 单屏成本 | 约 8 秒 | 截图 1s + OCR 2~3s + dump 2.3s + 滑动等待 2s |

## 六、卡片结构（解析依据）

双列网格，每张卡的纵向布局（以标题 y 为基准）：

```
展示图
品牌 + 标题        y_title              ← dump 的 content-desc
促销语             y_title + 75         ← OCR（如"降温惊喜 明星单品 好评8千+"）
价格 + 已售        y_title + 145        ← 价格 OCR，已售 dump
店铺 + 标签        y_title + 240        ← 店铺 OCR，标签 dump
```

列边界固定：左列 `43–594`，右列 `671–1222`（1272 宽屏幕）。
**OCR 字段必须同时按列限 x 范围**，否则左右两张卡的价格会串（这是本项目实际踩的坑）。

## 七、会踩的坑

| 现象 | 原因 | 解决 |
|---|---|---|
| 解析出 0 张卡 | 抖音标题在 `content-desc` 里，不是 `text` | 读节点时 `text or content-desc` |
| 左右卡价格串位 | OCR 行只按 y 匹配 | `find_field` 同时校验 x 落在本列 |
| 价格读不到 | 价格是自绘视图，TextView 为空 | 走 OCR；查 `zh-Hans-CN` 语言包 |
| `AsTask() 不存在` | PowerShell 5.1 没有 WinRT async 适配器 | `ocr.ps1` 里用 `WindowsRuntimeSystemExtensions.AsTask` 反射调用 |
| PowerShell 报「反引号」语法错 | `IAsyncOperation\`1` 里的反引号被当转义 | 用 `'IAsyncOperation' + [char]96 + '1'` 拼名字 |
| `.ps1` 中文注释乱码、引号报错 | 存成无 BOM UTF-8，PS 5.1 按 ANSI 读 | 存 **UTF-8 with BOM** |
| 促销语抓不到 | 促销文案没有固定关键词（如"降温惊喜明星单品"） | 改成"本列里除价格/已售/店名外的第一行" |
| OCR 汉字之间带空格 | 引擎按字分词 | `clean()` 正则去掉汉字间空格 |
| 中文关键词搜不出来 | `adb input text` 只支持 ASCII | 手机手动搜，再 `--no-nav` |

## 八、验收标准

- [ ] `--probe` 能解析出当前屏幕的卡片，价格与卡片左右位置对应正确
- [ ] json 条数 = `--limit`，每条 `图片` 都指向存在的文件
- [ ] 图片是商品图（不是搜索栏、不是相邻卡片）
- [ ] 两次采集标题无重复（`--seen` 去重）
- [ ] xlsx 行数 = 条数，图片按行对齐、长图不被压扁

## 九、文件

```
scripts/
├── dy_collect.py     采集器：导航 + 截图 + OCR + dump + 裁图 + 去重
├── dy_parse.py       解析器：双列切卡、按列限定 OCR 字段、清理 OCR 空格
├── dy_build_xlsx.py  出表：8 列 + 图片按比例自适应行高
├── ocr.ps1           Windows 自带 OCR 封装（WinRT，可用 -Lang zh-Hans-CN）
└── phone_specs.py    adb 封装（dump_root / nodes / txt / dsc / activity）
```

`ocr.ps1` 是通用的，任何需要本地中文 OCR 的项目都能直接调：

```powershell
powershell -File ocr.ps1 -ImagePath shot.png -Lang zh-Hans-CN -Json out.json
# 输出每行：{"text":"...","x":123,"y":456,"w":78,"h":32}
```

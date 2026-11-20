---
name: xhs-list-pipeline
description: 只解析小红书「搜索 → 商品」结果列表页，批量提取商品标题/价格/已售/店铺/好评率/店铺销量/几年老店/展示图，导出带图 xlsx。不进入商品详情页、不抓包、不改 App、不用浏览器，全程 adb + 无障碍树 + 整屏截图裁图。
whenToUse: 用户要按关键词批量看小红书商品列表（选品/比价/竞品调研），字段只要列表页能看到的那些，不需要每个 SKU 的价格；或者明确说"不进详情页"、"不要抓包"、"就要列表信息"时。要 SKU 级价格/商品链接/详情页截图时改用 xhs-goods-pipeline。
user-invocable: true
metadata:
  tags: [xiaohongshu, adb, ui-automation, list-scraping, excel, no-detail-page]
  requires: 手机开 USB/无线调试；小红书已登录；Python 3.10+ 且装了 openpyxl、Pillow
---

# 小红书商品列表采集（不进详情页）

只做一件事：**把关键词的商品搜索结果列表翻完，导出带展示图的表格。**

不进入商品详情、不点开任何卡片、不抓包、不注入 Frida、不用浏览器 —— 全程只有三步：
`uiautomator dump` 拿无障碍树 → 整屏 `screencap` → 按卡片坐标裁图。

## 一、产出字段

| 列 | 说明 | 实测覆盖 |
|---|---|---|
| 序号 | 连续编号 | 100% |
| 商品标题 | | 100% |
| 价格 | 券后价 / 入会价 / 关注后价，统一取数字 | ~95% |
| 已售 | `已售212` | ~95% |
| 店铺 | `XX旗舰店` / `XX的店` | ~90% |
| 好评率 | `好评率99%` | ~13% |
| 店铺销量 | `销量2万+` | ~18% |
| 几年老店 | `3年老店` | ~11% |
| 展示图 | 从整屏截图按卡片裁出，尺寸随卡片（541×541 ~ 541×907） | 100% |

> 后三列覆盖率低**不是漏抓**：列表页本身只给部分店铺显示这些标签，个人小店的卡片上就没有。

## 二、前置条件

```powershell
adb connect <手机IP>:5555          # 无线调试；USB 直连可跳
adb devices                        # 必须是 device
adb shell input keyevent KEYCODE_WAKEUP
adb shell svc power stayon true    # 屏幕常亮，避免息屏导致点击失败
```

小红书已登录。**关键词只能输 ASCII**（`adb shell input text` 不支持中文）：
- 英文/数字关键词（`ai`、`nike`、`adidas`）：脚本自己会搜
- 中文关键词：先在手机上手动搜好并点「商品」页签，再用 `--no-nav`

## 三、用法

```powershell
cd scripts

# 1) 首次采集 100 条（脚本自己进搜索页）
python collect_list.py --keyword ai --limit 100 --out list_ai.json

# 2) 出表（图片按实际比例自适应行高）
python build_list_xlsx.py --json list_ai.json --out 小红书_AI_100.xlsx

# 3) 已经有 100 条，从当前位置继续再采 100 条（不重复）
python collect_list.py --no-nav --seen list_ai.json --start-index 101 `
                       --limit 100 --out list_ai_2.json --max-scroll 60

# 4) 合并两批（序号重排）
python -c "import json;a=json.load(open('list_ai.json',encoding='utf-8'));b=json.load(open('list_ai_2.json',encoding='utf-8'));m=a+b;[r.update(序号=i) for i,r in enumerate(m,1)];json.dump(m,open('list_all.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)"

# 5) 出合并表
python build_list_xlsx.py --json list_all.json --out 小红书_AI_200.xlsx
```

### 参数

| 参数 | 作用 |
|---|---|
| `--keyword` | 搜索关键词（ASCII） |
| `--limit` | 要采多少条，默认 100 |
| `--out` | 结果 json |
| `--imgdir` | 图片目录，默认 `images/list` |
| `--no-nav` | 不重新进搜索页，从当前滚动位置继续 |
| `--seen` | 已有结果 json，按其标题去重（继续采集用） |
| `--start-index` | 序号起始值（继续采集时传 101） |
| `--max-scroll` | 最多翻多少屏，默认 60 |

## 四、耗时（实测，一加 15 / 1272×2772）

| 场景 | 耗时 | 备注 |
|---|---|---|
| 前 100 条 | **5.4 分钟** | 37 屏，约 2.7 条/屏 |
| 再 100 条（继续下翻） | **约 11 分钟** | 深翻时每屏只剩 1~2 条新的 |
| 单屏成本 | 8.7 秒 | dump 2.26s + 截图 0.93s + 滑动等待 2.2s + 解析裁图 ~3s |

## 五、三个必须知道的实现细节

### 1. 卡片结构（解析依据）

商品列表是双列网格，每张卡的文字节点从上到下是：

```
展示图（无文字节点）
用户评价        “真的太庆幸选了这家!...”        ← 裁图要排除
标题            adidas·春季新款Oversize经典三条纹...
促销语          限时立减130元 今日发 / 满30减5 100+人加购
价格+已售        券后¥269.已售2527
店铺            耶运动旗舰店   销量4万+ / 6年老店 / 好评率99%
```

解析时按屏幕中线分成左右两列，列内按 y 排序，**遇到标题就开新卡片**。
标题判定必须排除：`¥`、`已售`、`加购`、`立减`、`满X减`、`好评率`、`券后`、`关注后`、`“…”` 评价行、店名。

### 2. 裁图原则：宁可多裁，不要少裁

图片在各卡之间高度不同（方图、长图都有），所以**不强制正方形**：

```
下界 = 标题上方 4px（可能带一点评价文字，可接受）
上界 = 上一张卡文字的下沿（评价行属于本卡内部，不能当分隔）
若这样算出来比正方形还矮 → 退回正方形（标题y - 列宽）
若仍被顶部搜索区挡住 / 高度不足 0.75 列宽 → 本屏跳过，等下一屏
```

列宽固定用标准值（左列 52–593，右列 679–1220），**不要用标题文字的宽度**——
窄标题只有 392px 宽，会把图左右切掉。

### 3. 会踩的坑

| 现象 | 原因 | 解决 |
|---|---|---|
| 第一张卡的图裁成了顶部搜索栏 | 卡片贴着屏幕上沿，`标题y - 图高` 落进搜索区 | 上界限制在 `HEADER_BOTTOM=600` 以下，被挡就跳过等下一屏 |
| 有评价行的卡片全被跳过 | 用评价行位置当裁图上界，高度只剩几像素 | 记录"上一张卡文字下沿"（排除评价行），高度不够退回正方形 |
| `PermissionError: [WinError 32]` 退出 | PIL 打开截图后没关就 `unlink` | 先 `im.close()`，删除包 try |
| 图片左右被切 | 用标题文字宽度当列宽 | 用列标准宽度 541 |
| 中文关键词搜不出来 | `adb shell input text` 只支持 ASCII | 手动在手机上搜，再用 `--no-nav` |
| 往下翻不出新卡 | 关键词结果已被采完 | 换关键词，或采「综合」页签（笔记）里的商品 |
| 滑动步长太大导致漏卡 | 一次滑 1500px，贴顶的卡直接被划过 | 步长压到 700px（`swipe 636 2100 636 1400 300`） |

## 六、验收标准

- [ ] json 条数 = `--limit`，每条的 `图片` 字段都指向存在的文件
- [ ] 图片高度都 ≥ 0.75 倍列宽（541×406 以上），没有把搜索栏裁进来
- [ ] 两次采集之间标题无重复（用 `--seen` 去重）
- [ ] xlsx 行数 = 数据条数，图片按行对齐，长图不被压扁

## 七、文件

```
scripts/
├── collect_list.py       采集器：翻页 + dump + 截图 + 裁图 + 去重
├── list_parse.py         解析器：双列切卡、字段正则、评价行/促销语识别
├── build_list_xlsx.py    出表：9 列 + 图片按比例自适应行高
└── phone_specs.py        adb 封装（dump_root / nodes / txt / page_kind / to_goods）
```

`phone_specs.py` 只用到其中一小部分（adb 封装与 dump 解析），是为了和
`xhs-goods-pipeline` 复用同一套底层，两个 skill 互不冲突、可同时存在。

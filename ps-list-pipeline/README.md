# 快速开始（零 Python）

## 1. 检查环境

```powershell
adb version
adb connect <手机IP>:<端口>     # 端口在手机「无线调试」页面
adb devices                     # 要看到 device
```

## 2. 一条命令

```powershell
cd scripts
.\run_all.ps1 -App dewu -Keyword Nike -Limit 20
```

`-App` 可选：`dewu`（得物）/ `xhs`（小红书）/ `dy`（抖音）

## 3. 看结果

```
out\<App>_<时间>.xlsx     ← 带首图的表格，直接双击打开
成功后只保留上述 xlsx，CSV 和图片临时目录自动清理。
```

## 更稳的用法（推荐）

自动导航靠点坐标，App 有小弹窗时可能点偏。稳妥做法：

1. 手动把 App 停在「搜索 → 商品」结果页（关键词自己输）
2. 运行：

```powershell
.\ps_collect.ps1 -App dewu -Limit 20 -Csv d.csv -ImageDir imgs\dewu
.\make_xlsx.ps1 -Csv d.csv -ImageColumn 首图 -Out d.xlsx -ImageWidth 160
```

## 不出手机也能测

```powershell
.\make_xlsx.ps1 -ImageFolder C:\我的图片 -Out 图片清单.xlsx -ImageWidth 120
```

把一整个文件夹的图片做成带缩略图的表格。

## 注意

- `.ps1` 必须是 **UTF-8 with BOM**，否则 PowerShell 5.1 读中文会报语法错（本目录已带）
- 中文关键词不能用 `adb shell input text`，需 ADBKeyboard 或手工输入
- 连续四屏实际无新增时停止；数量不足时文件名带“部分”。达到目标不会额外裁图。
- `ps_collect.ps1` 是分步调试入口，会保留 CSV 和图片。续采时使用相同 `-Csv`、`-ImageDir`，加 `-Resume`，`-Limit` 是累计目标数量，手机需手动停在所需结果页。
- `run_all.ps1 -KeepData` 可在成功后保留核查数据，默认只留 Excel；失败时保留进度，成功出表后才清理。
- 图片已嵌入，移动 Excel 后仍可查看。浮层遮挡仍可能出现在屏幕裁图中。
- `-KeepScreen` 保存每屏 XML/PNG；`-ReplayDir` 可离线回放配对文件，均用于开发核查。
- 详细字段、坑、验收见 `SKILL.md`

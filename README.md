# 手机商品列表采集

通过 ADB 读取安卓手机上的商品搜索列表，整理为带展示图的 Excel。

包含小红书、抖音的 Python pipeline，以及支持得物/小红书/抖音的 PowerShell pipeline。此仓库不包含执行录制或视频教程。

## 得物与纯 PowerShell 入口

只需要 Windows 自带 PowerShell/.NET 和 adb，不需要 Python 或 Office：

```powershell
cd ps-list-pipeline/scripts
.\run_all.ps1 -App dewu -Keyword Nike -Limit 50
```

也支持 `-App xhs` 和 `-App dy`；后者的价格在无障碍树中不可见，需价格时使用下方带 OCR 的抖音 Python 版。中文关键词先在手机上手动搜索，再加 `-NoNav`。使用 `ADB_PATH` 环境变量指定 adb 路径，或将 adb 加入 PATH。

## 环境

- Windows、Python 3.10+、Android Platform Tools（adb 在 PATH 中）。
- 手机已开启 USB 或无线调试，并由用户确认连接；目标 App 已登录。
- `python -m pip install -r requirements.txt`。
- 抖音价格等自绘文字依赖 Windows OCR 及简体中文识别语言。

## 小红书

```powershell
cd xhs-list-pipeline/scripts
python collect_list.py --keyword nike --limit 50 --out xhs_result.json
python build_list_xlsx.py --json xhs_result.json --out xhs_result.xlsx
```

## 抖音

```powershell
cd dy-list-pipeline/scripts
python dy_collect.py --keyword nike --limit 50 --out dy_result.json
python dy_build_xlsx.py --json dy_result.json --out dy_result.xlsx
```

`--limit` 指定目标条数。手机列表按屏幕滑动，脚本按新增商品继续采集，`--max-scroll` 限制最大滑动次数。中文关键词需先在手机上手动搜索并进入商品页，再使用 `--no-nav`。商品不足或字段不显示时不能保证达到目标或字段齐全。

详细参数与解析原理见各目录 `SKILL.md`。这些文件是项目使用文档，其中的历史设备测试与覆盖率是原始记录，本次未重新做手机实测。

当前解析坐标针对原设备屏幕，换手机或 App 布局变化时需校准；本次仅完成源码整理与 Python 语法检查。设备连接信息、截图、采集结果均不应上传。

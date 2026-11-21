# 执行器目录

Agent 入口见 [SKILL.md](SKILL.md)，面向接收者的分享与启动说明见 [项目说明](../README.md)。

- `scripts/inspect_page.ps1`：捕获当前手机的截图、XML、分辨率和归一化节点，不滚动。
- `scripts/ps_collect.ps1`：列表采集，支持 `-Serial`、`-LayoutFile`、`-KeepScreen`、`-Resume`、离线 `-ReplayDir`。
- `scripts/run_all.ps1`：采集并出表，成功后默认仅留 Excel；`-KeepData` 保留核查数据。
- `scripts/make_xlsx.ps1`：把 CSV 和图片嵌入 Excel，无需 Office。
- `scripts/device.ps1`：寻找随包 ADB，列举/选择设备及交互连接。
- `scripts/start.ps1`：用户手动搜索后的桌面入口，默认先试 3 条。
- `tests/test_list.ps1`：字段、裁图、断点、独立 Excel 和模拟屏幕回归。

`.ps1` 文件保持 UTF-8 BOM，以兼容 Windows PowerShell 5.1。采集运行中不要改写解析器；设备证据和适配配置留在本地。

#!/usr/bin/env python3
"""phone_specs.py —— 功能二：手机点进商品详情，取「每个规格的价格」

思路（实测）：
  · 商品详情页 dump 一次 → 标题 / 到手价 / 原价 / 已售 / 发货地 / 评分 / 评价数
  · 点「已选规格」那一行（y≈2205）→ 面板里一次列出所有规格 + 各自价格
    （不用逐个点选，面板本身就是价目表）
  · 关面板、返回列表，再进下一个

每商品 2 次 dump，不依赖浏览器。

用法：
  python phone_specs.py --limit 5 --out specs_phone.json
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

import os
import shutil
ADB = os.environ.get("ADB_PATH") or shutil.which("adb") or "adb"
PKG = "com.xingin.xhs"
ZERO = dict.fromkeys(map(ord, "\u200b\u200c\u200d\ufeff\u2060"), None)
HOME = "com.xingin.xhs/com.xingin.xhs.index.v2.IndexActivityV2"
DETAIL_MARK = "commercial.good"

PROMO = re.compile(r"(加购|立减|满\s*\d|好评率|销量|包邮|退货|运费险|券后|今日发|新品|人购买|限时|限购)")
PRICE_RE = re.compile(r"^¥\s*([\d.]+)$")
DEAL_RE = re.compile(r"到手价\s*¥?\s*([\d.]+)")
SOLD_RE = re.compile(r"已售\s*([\d.]+\s*万?\+?)\s*件?")


def adb(*a, timeout=60):
    import subprocess
    p = subprocess.run([ADB, *a], capture_output=True, timeout=timeout)
    return p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")


def dump_root():
    adb("shell", "uiautomator dump /sdcard/_ui.xml")
    xml = adb("exec-out", "cat /sdcard/_ui.xml")
    try:
        return ET.fromstring(xml[xml.index("<hierarchy"):])
    except Exception:
        return None


def bnd(el):
    m = re.match(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]", el.get("bounds") or "")
    return tuple(map(int, m.groups())) if m else None


def txt(el):
    return (el.get("text") or "").translate(ZERO).strip()


def dsc(el):
    return (el.get("content-desc") or "").translate(ZERO).strip()


def activity():
    out = adb("shell", "dumpsys window | grep -m1 mCurrentFocus")
    m = re.search(r"mCurrentFocus=Window\{[^}]*?([A-Za-z0-9_.]+)/([A-Za-z0-9_.$]+)", out)
    return f"{m.group(1)}/{m.group(2)}" if m else ""


def nodes(root):
    for el in root.iter("node"):
        b = bnd(el)
        if b:
            yield el, b


def page_kind(root) -> str:
    if root is None:
        return "unknown"
    texts = [t for t in (txt(e) for e in root.iter("node")) if t]
    tab = sum(1 for t in ("全部", "用户", "商品", "图片", "视频") if t in texts)
    np_ = sum(1 for t in texts if "¥" in t)
    if tab >= 3 and np_ >= 2:
        return "goods"
    if any(t == "历史记录" for t in texts):
        return "search"
    if any("说点什么" in t for t in texts):
        return "note"
    if "commercial.good" in activity():
        return "detail"
    return "other"


def cards(root) -> list[dict]:
    out, parent = [], {c: p for p in root.iter() for c in p}
    for el in root.iter("node"):
        if "¥" not in txt(el):
            continue
        pb = bnd(el)
        if not pb:
            continue
        node, box = el, None
        while node in parent:
            node = parent[node]
            b = bnd(node)
            if not b:
                continue
            w, h = b[2] - b[0], b[3] - b[1]
            if 380 <= w <= 700 and 450 <= h <= 1600 and b[1] >= 430:
                box = b
                break
        if not box:
            continue
        gap_best, title = None, ""
        for e2 in root.iter("node"):
            t, b2 = txt(e2), bnd(e2)
            if not t or not b2 or len(t) < 6 or "¥" in t or PROMO.search(t):
                continue
            gap = pb[1] - b2[3]
            if gap < 0 or gap > 320 or abs(b2[0] - pb[0]) > 120:
                continue
            if gap_best is None or gap < gap_best:
                gap_best, title = gap, t
        out.append({"x": (box[0] + box[2]) // 2,
                    "y": max(box[1] + int((box[3] - box[1]) * 0.35), 520),
                    "title": title})
    out.sort(key=lambda c: (round(c["y"] / 500), c["x"]))
    return out


def to_goods(keyword="纸巾") -> bool:
    for _ in range(4):
        if page_kind(dump_root()) == "goods":
            return True
        act = activity()
        if act == HOME:
            break
        adb("shell", "input keyevent KEYCODE_BACK")
        time.sleep(0.5)
    adb("shell", f"am start -n {PKG}/.index.v2.IndexActivityV2")
    time.sleep(3.0)
    adb("shell", "input tap 1117 218")
    time.sleep(2.0)
    root = dump_root()
    if root is not None:
        for el, b in nodes(root):
            if txt(el) == keyword:
                adb("shell", f"input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}")
                time.sleep(2.4)
                break
    root = dump_root()
    if root is not None and page_kind(root) != "goods":
        for el, b in nodes(root):
            if txt(el) == "商品":
                adb("shell", f"input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}")
                time.sleep(2.2)
                break
    return page_kind(dump_root()) == "goods"


# ---------------------------------------------------------------- 详情页解析
def parse_detail(root) -> dict:
    d = {"标题": "", "到手价": "", "原价": "", "已售": "", "发货地": "",
         "评分": "", "评价数": "", "已选规格": ""}
    long_title = ""
    eval_count = ""
    eval_row_y = score_row_y = None
    for el, b in nodes(root):
        t, ds = txt(el), dsc(el)
        cy = (b[1] + b[3]) // 2

        # 价格
        if not d["原价"]:
            m = PRICE_RE.match(t)
            if m:
                d["原价"] = m.group(1)
        if not d["到手价"]:
            m = DEAL_RE.search(t + " " + ds)
            if m and "到手价" in (t + ds):
                d["到手价"] = m.group(1)

        # 已售
        if not d["已售"]:
            m = SOLD_RE.search(t + " " + ds)
            if m:
                d["已售"] = m.group(1)

        # 已选规格
        if "已选规格" in ds:
            d["已选规格"] = ds.replace("已选规格，", "").strip()

        # 发货地：desc 里 "发货地XX" 最可靠
        if not d["发货地"]:
            m = re.search(r"发货地([\u4e00-\u9fa5]{2,12})", ds)
            if m:
                d["发货地"] = m.group(1)

        # 标题：desc "商品名称，xxx" 或最长的那行
        if "商品名称" in ds:
            d["标题"] = ds.split("，", 1)[-1].strip()
        if 8 <= len(t) <= 120 and "¥" not in t and not PROMO.search(t) and len(t) > len(long_title):
            if 1400 < cy < 1900:
                long_title = t

        # 评分 / 评价数：先记「商品评价」所在行，再取同一行里的数字
        if t == "商品评价":
            eval_row_y = cy
        if t == "评分":
            score_row_y = cy
        if "条好评" in ds and not eval_count:
            m = re.search(r"(\d+\+?)", ds)
            if m:
                eval_count = m.group(1)
    # 第二轮：拿「商品评价」行右侧的数字当评价数，「评分」行右侧当评分
    for el, b in nodes(root):
        t = txt(el)
        cy = (b[1] + b[3]) // 2
        if eval_row_y is not None and abs(cy - eval_row_y) <= 30 and re.fullmatch(r"[\d.]+[万千+]*", t or ""):
            if t not in ("商品评价",) and not d["评价数"]:
                d["评价数"] = t
        if score_row_y is not None and abs(cy - score_row_y) <= 30 and re.fullmatch(r"[\d.]+", t or ""):
            if t != "评分" and not d["评分"]:
                d["评分"] = t
    d["标题"] = d["标题"] or long_title
    d["评价数"] = d["评价数"] or eval_count
    return d


# ---------------------------------------------------------------- 规格面板解析
def parse_sheet(root) -> dict:
    """面板里：规格名 + 同排价格；分组标签是 x 很小、字号小的行。"""
    inline_pairs = []          # 名字+价格写在同一个 TextView 里
    items, labels = [], []
    for el, b in nodes(root):
        t = txt(el)
        if not t or b[1] < 600:
            continue
        cy = (b[1] + b[3]) // 2
        m_inline = re.match(r"^(.{2,40}?)\s*¥\s*([\d.]+)\s*$", t)
        if m_inline and "到手价" not in t:
            inline_pairs.append({"name": m_inline.group(1).strip(),
                                 "price": float(m_inline.group(2))})
            continue
        m = PRICE_RE.match(t)
        if m:
            items.append({"price": float(m.group(1)), "y": cy, "x": b[0], "kind": "price"})
        elif 2 <= len(t) <= 30 and not PROMO.search(t):
            items.append({"name": t, "y": cy, "x": b[0], "x2": b[2], "kind": "name"})
    # 分组标签：x<300 且短，且上方 100px 内没有价格
    labels = [i for i in items if i["kind"] == "name" and i["x"] < 300 and len(i["name"]) <= 8
              and re.fullmatch(r"[\u4e00-\u9fa5]{2,8}", i["name"])]

    # 规格名要排除面板顶部的价格/优惠行
    BAD = ("到手价", "原价", "已省", "限时", "商家券", "限购", "明日发", "预计",
           "加入购物车", "立即购买", "领券购买", "退货包运费", "极速退款", "大图", "件")

    def is_spec_name(nm):
        n = nm["name"].strip()
        if any(k in n for k in BAD):
            return False
        if nm["y"] < 1100:                     # 顶部价格区
            return False
        if len(n) < 3 or re.match(r"^[.\d¥\s]", n):   # ".9" / "¥2.66" 这类残缺
            return False
        if not re.search(r"[\u4e00-\u9fa5]", n):      # 必须含中文
            return False
        return True

    specs, prices = [], list(inline_pairs)
    for p in [i for i in items if i["kind"] == "price"]:
        cand = [i for i in items if i["kind"] == "name" and is_spec_name(i)
                and abs(i["y"] - p["y"]) <= 45 and i["x2"] <= p["x"] - 10]
        if not cand:
            continue
        # 同一行的名字可能被拆成多段，按 x 拼回去；连续重复片段只留一次
        cand.sort(key=lambda i: i["x"])
        parts, prev = [], None
        for i in cand:
            if i["name"] == prev:
                continue
            parts.append(i["name"])
            prev = i["name"]
        name = "".join(parts).strip()
        if len(name) < 3 or not re.search(r"[\u4e00-\u9fa5]", name):
            continue
        prices.append({"name": name, "price": p["price"]})

    # 顶部当前规格到手价
    top = min((i for i in items if i["kind"] == "price"), key=lambda i: i["y"], default=None)
    return {"prices": prices, "top": top["price"] if top else None,
            "labels": [l["name"] for l in labels]}


# ---------------------------------------------------------------- 主流程
def find_sel_row(root):
    """详情页里「已选规格」那一行的可点中心（找不到返回 None）。"""
    best = None
    for el, b in nodes(root):
        t, ds = txt(el), dsc(el)
        if "已选规格" in ds or ds.startswith("已选") or t == "已选":
            cy = (b[1] + b[3]) // 2
            if best is None or b[1] < best[2]:
                best = ((b[0] + b[2]) // 2, cy, b[1])
    return best


def find_inline_chips(root) -> list[dict]:
    """详情页上直接铺开的规格按钮：desc 形如「1包未选中」「2包已选中」。"""
    chips = []
    for el, b in nodes(root):
        ds = dsc(el)
        m = re.match(r"^(.{1,26}?)(未选中|已选中)$", ds)
        if m:
            chips.append({"name": m.group(1).strip(),
                          "selected": m.group(2) == "已选中",
                          "x": (b[0] + b[2]) // 2, "y": (b[1] + b[3]) // 2,
                          "top": b[1]})
    chips.sort(key=lambda c: (c["top"], c["x"]))
    return chips


def read_deal_price(root) -> str:
    """读当前选中规格的到手价。

    权威来源是价格行容器的 desc：
        「商品价格，到手价6.5元原价7.5元已售4.5万+包」
    它随规格切换而更新；页面上零散的 ¥x 节点可能是别的商品/推荐位，不能直接用。
    """
    # 1) 价格行容器 desc
    for el, b in nodes(root):
        ds = dsc(el)
        if ds.startswith("商品价格"):
            m = re.search(r"到手价\s*([\d.]+)\s*元", ds) or re.search(r"到手价\s*([\d.]+)", ds)
            if m:
                return m.group(1)
            m2 = re.search(r"原价\s*([\d.]+)\s*元", ds)
            if m2:
                return m2.group(1)
    # 2) 兜底：文本里带「到手价」的节点
    for el, b in nodes(root):
        t, ds = txt(el), dsc(el)
        if "到手价" in t or "到手价" in ds:
            m = re.search(r"到手价\s*¥?\s*([\d.]+)", t + " " + ds)
            if m:
                return m.group(1)
    return ""


def sheet_open(root) -> bool:
    texts = [txt(e) for e in root.iter("node")] if root is not None else []
    return any(t in ("加入购物车", "立即购买", "领券购买", "确定") for t in texts)


def tap_button(root, names, prefer_bottom: bool = True) -> bool:
    """按文字/desc 找按钮并点它。

    页面上同名字样可能出现多次（标题、优惠位、底部操作栏），
    「立即购买/领券购买」真正可点的是底部操作栏，所以默认取最靠下的匹配。
    """
    hits = []
    for el, b in nodes(root):
        t, ds = txt(el), dsc(el)
        for n in names:
            if t == n or ds == n or (n in t and len(t) <= 8) or (n in ds and len(ds) <= 12):
                hits.append(b)
                break
    if not hits:
        return False
    b = max(hits, key=lambda x: (x[1], x[0])) if prefer_bottom else hits[0]
    adb("shell", f"input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}")
    return True


SHOT_DIR = Path("images/phone")
SHOT_DIR.mkdir(parents=True, exist_ok=True)


SHOT_SMALL = False         # 默认全分辨率：降分辨率会让页面重排，价格/标题被挤出屏幕
SHOT_SETTLE = 2.0          # 截图前等页面渲染完成（否则商品图是占位）


def capture(name: str) -> str:
    """手机截屏 → images/phone/<name>.png

    无线 adb 只有 ~100KB/s，1.1MB 全尺寸图要 11 秒。
    所以截图瞬间临时把分辨率降到 636x1386（≈258KB），截完立刻恢复，
    期间不做任何 dump/点击，坐标不受影响。
    """
    import subprocess
    local = SHOT_DIR / f"{name}.png"
    SHOT_DIR.mkdir(parents=True, exist_ok=True)

    time.sleep(SHOT_SETTLE)          # 等商品主图/价格区渲染完，避免截到占位图

    changed = False
    if SHOT_SMALL:
        out = adb("shell", "wm size")
        if "Override" not in out:
            adb("shell", "wm size 720x1568")
            changed = True
            time.sleep(0.7)

    ok = False
    try:
        if SHOT_SMALL:
            remote = "/sdcard/_shot.png"
            subprocess.run([ADB, "shell", f"screencap -p {remote}"], capture_output=True, timeout=60)
            if local.exists():
                local.unlink()
            subprocess.run([ADB, "pull", remote, str(local)], capture_output=True, timeout=120)
        else:
            r2 = subprocess.run([ADB, "exec-out", "screencap -p"], capture_output=True, timeout=120)
            local.write_bytes(r2.stdout or b"")
        ok = local.exists() and local.stat().st_size > 10000 and local.read_bytes()[:4] == b"\x89PNG"
        if not ok and SHOT_SMALL:
            # 降分辨率失败时退回全尺寸 exec-out
            p2 = subprocess.run([ADB, "exec-out", "screencap -p"], capture_output=True, timeout=120)
            data = p2.stdout or b""
            if data[:4] == b"\x89PNG":
                local.write_bytes(data)
                ok = True
    finally:
        if changed:
            adb("shell", "wm size reset")
            time.sleep(0.7)
    return str(local).replace("\\", "/") if ok else ""


def fresh_dump(times: int = 1):
    """连续 dump 两次取第二次，避开 UI 还没刷新的旧快照。"""
    r = None
    for _ in range(times):
        r = dump_root()
    return r


def find_variants_entry(root):
    """详情页上的「共N款 >」入口（规格选择的正门）。"""
    for el, b in nodes(root):
        t = txt(el)
        if re.fullmatch(r"共\s*\d+\s*款\s*>?", t or ""):
            return ((b[0] + b[2]) // 2, (b[1] + b[3]) // 2)
    return None


def open_sku_panel(detail_root=None) -> tuple[bool, object]:
    """点底部付款/购买按钮 → 弹出规格面板。

    只 dump 一次：tap 后等 1.3s 直接 dump，用这一次的结果既判断"开没开"
    又交给解析用，避免为了验证再 dump 一遍（一次 dump 2.2s，很贵）。
    """
    r = detail_root if detail_root is not None else dump_root()
    if tap_button(r, ["领券购买", "立即购买", "加入购物车", "规格选择"]):
        time.sleep(1.0)
        r2 = dump_root()
        if sheet_open(r2):
            return True, r2
        print("     [面板] 第 1 次点击未打开")
        # 单规格商品本来就没有规格选择，别再试后面的入口（每次尝试要 2.5s）
        if find_sel_row(r) is None:
            return False, None
    # 兜底 1：已选规格行
    r = r2 if 'r2' in dir() else dump_root()
    row = find_sel_row(r)
    if row:
        adb("shell", f"input tap {row[0]} {row[1]}")
        time.sleep(1.3)
        r3 = dump_root()
        if sheet_open(r3):
            return True, r3
    # 兜底 2：共N款 / 规格选择
    ve = find_variants_entry(dump_root())
    if ve:
        adb("shell", f"input tap {ve[0]} {ve[1]}")
        time.sleep(1.3)
        r4 = dump_root()
        if sheet_open(r4):
            return True, r4
    return False, None


def parse_sheet_all(root=None) -> list[dict]:
    """从面板 dump 里读规格价格。传 root 可复用已有 dump，省一次 2.2s。

    · 价目表布局：名字+价格成对，或写在同一个文字节点
    · 只有检测到"底部可能还有内容"才滚动，最多 2 屏
    """
    specs, seen = [], set()
    r = root if root is not None else dump_root()
    if r is None:
        return []

    def merge(pairs) -> int:
        added = 0
        for sp in pairs:
            key = (sp["name"], sp["price"])
            if key in seen:
                continue
            seen.add(key)
            specs.append(sp)
            added += 1
        return added

    added = merge(parse_sheet(r)["prices"])
    if not added:
        return []

    for _ in range(2):
        # 底部还有内容的判断：最靠下的价格节点离屏幕底部 < 250px
        prices_y = [b[3] for el, b in nodes(r)
                    if re.match(r"^¥|.*¥\s*[\d.]+\s*$", txt(el) or "")
                    and b[1] > 1100]
        if not prices_y or max(prices_y) < 2500:
            break
        adb("shell", "input swipe 636 2050 636 1250 400")
        time.sleep(0.9)
        r = dump_root()
        if not sheet_open(r):
            break
        if merge(parse_sheet(r)["prices"]) == 0:
            break
    return specs


def close_panel_and_back() -> None:
    """关面板 → 点页面左上角「返回」按钮回列表（不用系统 BACK，避免退到桌面）。"""
    adb("shell", "input keyevent KEYCODE_BACK")     # 只关面板
    time.sleep(0.9)
    r = dump_root()
    if tap_button(r, ["返回"]):
        time.sleep(1.3)
        return
    # 没有返回按钮时才用系统 BACK
    adb("shell", "input keyevent KEYCODE_BACK")
    time.sleep(1.0)


items_all: list = []


SHARE_XY = (1181, 218)      # 详情页右上角「分享」
COPY_XY = (160, 2523)       # 分享面板「复制链接」


def bubble_center() -> tuple:
    """悬浮球点击坐标：优先读 App 上报的 pos.txt，其次退回 dumpsys。"""
    out = adb("shell", "run-as com.dsh.clipbox cat files/pos.txt").strip()
    m = re.match(r"^(\d+),(\d+)$", out)
    if m:
        return (int(m.group(1)), int(m.group(2)))

    # 兜底：从窗口属性推算（窗口可能被挤到屏幕外，所以只作后备）
    dump = adb("shell", "dumpsys window windows | grep -A14 clipbox")
    m2 = re.search(r"mAttrs=\{\((-?\d+),(-?\d+)\)", dump)
    if not m2:
        return None
    x, y = int(m2.group(1)), int(m2.group(2))
    wh = re.search(r"Requested w=(\d+) h=(\d+)", dump)
    w, h = (int(wh.group(1)), int(wh.group(2))) if wh else (196, 196)
    cx, cy = x + w // 2, y + h // 2
    if cy < 0:                        # 跑出屏幕就放弃，交上层判定失败
        return None
    return (cx, cy)


def read_clip_file() -> tuple[int, str]:
    """读 files/clip.txt，返回 (时间戳ms, 文本)。"""
    out = adb("shell", "run-as com.dsh.clipbox cat files/clip.txt")
    if not out.strip():
        return 0, ""
    parts = out.split("\n", 1)
    try:
        ts = int(parts[0].strip())
    except Exception:
        ts = 0
        parts = [out]
    return ts, (parts[1] if len(parts) > 1 else "")


def _sheet_has(root, word: str) -> bool:
    for el, b in nodes(root):
        if word in (txt(el) + dsc(el)):
            return True
    return False


BROADCAST_READ = ("am broadcast -a com.dsh.clipbox.READ "
                  "-n com.dsh.clipbox/.ReadReceiver")


def grab_link_overlay() -> str:
    """取商品链接：复制链接 → 广播让悬浮窗 App 读剪贴板写文件 → 读文件。

    不需要点悬浮球（坐标不可靠），也不需要跳页面。
      1. 点「分享」→ 面板出现「复制链接」才点
      2. am broadcast 触发 App 的 ReadReceiver：展开 → 读剪贴板 → 写文件 → 收起
      3. 读 files/clip.txt，校验时间戳比这次点击新，防止拿到上一条的旧链接
    """
    adb("shell", "run-as com.dsh.clipbox rm -f files/clip.txt")
    tap_ms = int(time.time() * 1000)

    # 1) 打开分享面板（固定坐标失败则按 dump 找分享节点）
    r = None
    for attempt in range(2):
        if attempt == 0:
            adb("shell", f"input tap {SHARE_XY[0]} {SHARE_XY[1]}")
        else:
            rr = dump_root()
            pt = None
            for el, b in nodes(rr):
                if "分享商品" in (txt(el) + dsc(el)) or txt(el) == "分享":
                    pt = ((b[0] + b[2]) // 2, (b[1] + b[3]) // 2)
                    break
            if not pt:
                return ""
            adb("shell", f"input tap {pt[0]} {pt[1]}")
        time.sleep(1.3)
        r = dump_root()
        if _sheet_has(r, "复制链接"):
            break
    else:
        return ""

    # 2) 点「复制链接」（面板会自动关闭，不要再按 BACK）
    pt = None
    for el, b in nodes(r):
        if "复制链接" in (txt(el) + dsc(el)):
            pt = ((b[0] + b[2]) // 2, (b[1] + b[3]) // 2)
            break
    adb("shell", f"input tap {pt[0] if pt else COPY_XY[0]} {pt[1] if pt else COPY_XY[1]}")
    time.sleep(1.0)

    # 3) 广播让 App 读剪贴板
    for attempt in range(2):
        adb("shell", BROADCAST_READ)
        time.sleep(1.5)
        ts, body = read_clip_file()
        if ts >= tap_ms - 1500:
            m = re.search(r"(https?://xhslink\.com/[A-Za-z0-9/_\-]+)", body)
            if m:
                return m.group(1)
        time.sleep(0.8)
    return ""


def grab_link_from_detail() -> str:
    """在详情页取商品短链（固定坐标，实测最稳）。

    分享(1181,218) → 面板里找「复制链接」→ BACK 关面板 →
    搜索商品(779,218) → 输入框(547,232) → 粘贴 → dump 读链接 → 清空并退回详情。
    约 +5 秒；失败返回空串，不影响后面的流程。
    """
    # 1) 打开分享面板
    adb("shell", "input tap 1181 218")
    time.sleep(1.3)
    r = dump_root()
    pt = None
    for el, b in nodes(r):
        if "复制链接" in (txt(el) + dsc(el)):
            pt = ((b[0] + b[2]) // 2, (b[1] + b[3]) // 2)
            break
    if not pt:
        adb("shell", "input keyevent KEYCODE_BACK")     # 关掉可能已打开的面板
        time.sleep(0.6)
        return ""

    # 2) 复制链接 → 关面板回详情
    adb("shell", f"input tap {pt[0]} {pt[1]}")
    time.sleep(1.0)
    adb("shell", "input keyevent KEYCODE_BACK")
    time.sleep(0.9)

    # 3) 搜索商品 → 输入框粘贴
    adb("shell", "input tap 779 218")
    time.sleep(1.6)
    adb("shell", "input tap 547 232")
    time.sleep(0.4)
    adb("shell", "input keyevent 279")                  # PASTE
    time.sleep(0.9)
    r = dump_root()
    blob = " ".join(txt(e) for e in r.iter("node"))
    m = re.search(r"(https?://xhslink\.com/[A-Za-z0-9/_\-]+)", blob)

    # 4) 清空输入框，退回详情页
    adb("shell", "input keyevent KEYCODE_MOVE_END")
    for _ in range(24):
        adb("shell", "input keyevent 67")
    for _ in range(2):
        adb("shell", "input keyevent KEYCODE_BACK")
        time.sleep(0.7)
    return m.group(1) if m else ""


def collect_one(c, kw="纸巾", close_after: bool = False, with_link: bool = False) -> dict:
    adb("shell", f"input tap {c['x']} {c['y']}")
    time.sleep(2.0)
    act = activity()
    if "commercial.good" not in act:
        return {"error": f"未进详情({act.split('/')[-1][:24]})"}

    root = dump_root()
    info = parse_detail(root)                       # dump ①
    info["list_title"] = c["title"]
    info["shot"] = capture(f"{len(items_all) + 1:03d}_{int(time.time()) % 100000}")

    # 单规格商品点「立即购买」会弹出下单确认框，挡住右上角分享按钮，
    # 导致后面取链接全部失败。所以先看有没有规格入口，没有再决定要不要点。
    has_spec_entry = (find_sel_row(root) is not None) or bool(find_inline_chips(root))
    if has_spec_entry:
        opened, panel_root = open_sku_panel(root)
    else:
        opened, panel_root = False, None
        print("    无规格入口，跳过面板（避免弹下单框）")
    info["panel"] = opened
    if opened:
        info["specs"] = parse_sheet_all(panel_root)   # 复用同一次 dump
        print(f"    面板已开，规格 {len(info['specs'])} 个")
    else:
        info["specs"] = []
        print("    面板没打开")

    # 用悬浮窗取链接：不跳页、不丢列表位置，列表模式也能用
    if with_link and not info.get("link"):
        # 只有面板真的开着才按 BACK 关它；
        # 面板没开还按 BACK 会把详情页关掉，之后就退到列表/主页（踩过）。
        if opened:
            adb("shell", "input keyevent KEYCODE_BACK")
            time.sleep(0.8)
        info["link"] = grab_link_overlay()

    # 链接模式：下一条 am start 直接覆盖，不用关面板
    # 列表模式：必须退回列表，否则下一张卡片点不到
    if close_after:
        # 只有面板真的开着才按 BACK 关它；
        # 面板没开时按 BACK 会把详情页关掉，后面就会掉到主页。
        if opened:
            adb("shell", "input keyevent KEYCODE_BACK")
            time.sleep(0.8)
        # 回列表：点详情页左上角的返回按钮（固定位置），这样保留列表滚动位置；
        # 不要用 am start 回搜索结果页，那会重建列表、滚动归零。
        for coord in ((91, 218), (60, 220)):
            adb("shell", f"input tap {coord[0]} {coord[1]}")
            time.sleep(1.2)
            if page_kind(dump_root()) == "goods":
                break
        else:
            # 实在不行才用系统 BACK，最后才回首页重进
            adb("shell", "input keyevent KEYCODE_BACK")
            time.sleep(1.0)
            if page_kind(dump_root()) != "goods":
                to_goods(kw)

    if not info.get("specs"):
        price = info.get("到手价") or info.get("原价")
        if price:
            info["specs"] = [{"name": info.get("已选规格") or "默认(单规格)",
                              "price": float(price), "fallback": True}]
        else:
            info["error"] = "没有拿到规格价格"
    items_all.append(info)
    return info


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=5)
    ap.add_argument("--out", default="specs_phone.json")
    ap.add_argument("--keyword", default="纸巾")
    ap.add_argument("--resume", action="store_true",
                    help="接着已有结果继续采（按标题去重）")
    ap.add_argument("--with-link", action="store_true",
                    help="顺带取商品短链，约 +5s/个")
    args = ap.parse_args()

    if not to_goods(args.keyword):
        print("入场失败")
        return 2

    results, pos, guard = [], 0, 0
    seen_titles = set()
    if args.resume and Path(args.out).exists():
        try:
            for r in json.loads(Path(args.out).read_text(encoding="utf-8")):
                t = r.get("标题") or r.get("list_title") or ""
                if t and t not in seen_titles:
                    seen_titles.add(t)
                    results.append(r)
            print(f"续采：已有 {len(results)} 个商品")
        except Exception as e:
            print("续采读取失败:", e)
    while len(results) < args.limit and guard < args.limit * 3:
        guard += 1
        root = dump_root()
        if page_kind(root) != "goods":
            if not to_goods(args.keyword):
                break
            continue
        cs = cards(root)
        if not cs:
            adb("shell", "input swipe 636 2200 636 900 400")
            time.sleep(1.0)
            continue
        per = len(cs)
        for _ in range(pos // per):
            adb("shell", "input swipe 636 2200 636 900 400")
            time.sleep(0.9)
        if pos // per:
            root = dump_root()
            cs = cards(root) if root is not None else cs
            if not cs:
                continue
        c = cs[min(pos % per, len(cs) - 1)]
        pos += 1

        print(f"\n[{len(results) + 1}] {c['title'][:24]}")
        t0 = time.time()
        info = collect_one(c, args.keyword, close_after=True, with_link=args.with_link)
        if args.with_link:
            used = {r.get("link") for r in results if r.get("link")}
            if info.get("link") in used:
                # 剪贴板没更新 → 重取一次
                again = grab_link_overlay()
                if again and again not in used:
                    info["link"] = again
                else:
                    info["link"] = ""
                    print("      链接重复且重取失败，置空")
        dt = time.time() - t0
        if info.get("error") and not info.get("specs"):
            print(f"    ✗ {info['error']}")
            continue
        _t = info.get("标题") or info.get("list_title") or ""
        if _t in seen_titles:
            print("      重复商品，跳过")
        else:
            seen_titles.add(_t)
            results.append(info)
        print(f"    ✓ {dt:.1f}s  标题 {info['标题'][:22]}")
        print(f"      到手价 {info['到手价']} / 原价 {info['原价']}  已售 {info['已售']}  "
              f"发货地 {info['发货地']}  评分 {info['评分']} 评价 {info['评价数']}")
        for sp in info["specs"][:8]:
            print(f"        {sp['name'][:24]:<26s} ¥{sp['price']}")
        if len(info["specs"]) > 8:
            print(f"        …共 {len(info['specs'])} 个规格")
        Path(args.out).write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding="utf-8")

    total = sum(len(r.get("specs") or []) for r in results)
    print(f"\n{len(results)} 个商品 / {total} 个规格 -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

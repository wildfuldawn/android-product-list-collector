"""dy_collect.py —— 抖音商城搜索结果采集（不进详情页）

数据来源：
  · adb uiautomator dump → 标题 / 已售 / 回头客 / 粉丝
  · 整屏截图 + Windows OCR → 价格 / 促销语 / 店铺名（抖音自绘，树里没有）
  · 整屏截图裁图 → 每条一张展示图

用法：
    python dy_collect.py --keyword ai --limit 100 --out dy_ai.json
    python dy_collect.py --probe                 # 只看当前屏幕解析结果
    python dy_collect.py --no-nav --seen dy_ai.json --start-index 101 --limit 100
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('ps', str(HERE / 'phone_specs.py'))
ps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ps)

spec2 = importlib.util.spec_from_file_location('dp', str(HERE / 'dy_parse.py'))
dp = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(dp)

ADB = ps.ADB
PKG = 'com.ss.android.ugc.aweme'
OCR_PS1 = HERE / 'ocr.ps1'

COL_LEFT = (43, 594)
COL_RIGHT = (671, 1222)
HEADER_BOTTOM = 600
SCREEN_H = 2772


# ---------------- 基础能力 ----------------
def shot(path: Path) -> bool:
    try:
        p = subprocess.run([ADB, 'exec-out', 'screencap -p'], capture_output=True, timeout=120)
        data = p.stdout or b''
        if data[:4] != b'\x89PNG':
            return False
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return True
    except Exception as e:
        print('  截图失败:', e)
        return False


def ocr(image: Path) -> list[dict]:
    """调 Windows 自带 OCR"""
    out = image.with_suffix('.ocr.json')
    try:
        subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                        '-File', str(OCR_PS1), '-ImagePath', str(image), '-Json', str(out)],
                       capture_output=True, timeout=180)
        if not out.exists():
            return []
        lines = []
        for ln in out.read_text(encoding='utf-8-sig').splitlines():
            ln = ln.strip()
            if not ln:
                continue
            try:
                lines.append(json.loads(ln))
            except json.JSONDecodeError:
                continue
        return lines
    except Exception as e:
        print('  OCR 失败:', e)
        return []


def view_nodes() -> list[tuple]:
    r = ps.dump_root()
    if r is None:
        return []
    out = []
    for el, b in ps.nodes(r):
        t = ps.txt(el) or ''
        d = ps.dsc(el) or ''
        v = t if t else d
        if v:
            out.append((b[0], b[1], b[2], b[3], v))
    return out


def col_box(card):
    cx = (card['x1'] + card['x2']) // 2
    return COL_LEFT if cx < 636 else COL_RIGHT


def image_box(card, prev_bottom):
    x1, x2 = col_box(card)
    w = x2 - x1
    bottom = card['y_title'] - 8
    top = max(HEADER_BOTTOM, prev_bottom + 6) if prev_bottom else max(HEADER_BOTTOM, bottom - w)
    if bottom - top < int(w * 0.7):
        top = bottom - w
    if top < HEADER_BOTTOM or bottom > SCREEN_H:
        return None
    if bottom - top < int(w * 0.7):
        return None
    return (x1, top, x2, bottom)


# ---------------- 导航 ----------------
def items():
    r = ps.dump_root()
    if r is None:
        return []
    out = []
    for el, b in ps.nodes(r):
        t, d = ps.txt(el), ps.dsc(el)
        if t or d:
            out.append((b[1], b[0], b[2], b[3], t, d))
    out.sort(key=lambda x: (x[0], x[1]))
    return out


def tap_text(name, by_desc=False, max_y=400):
    for y1, x1, x2, y2, t, d in items():
        if max_y and y1 > max_y:
            continue
        if (d == name if by_desc else t == name):
            ps.adb('shell', f'input tap {(x1 + x2) // 2} {(y1 + y2) // 2}')
            return True
    return False


def all_texts():
    """text + content-desc 合并（抖音把很多信息放在 desc 里）"""
    out = []
    for y1, x1, x2, y2, t, d in items():
        out.append((t or '') + ' ' + (d or ''))
    return ' | '.join(out)


def ensure_goods_page(keyword: str) -> bool:
    """确保停在「商城 → 搜索关键词 → 商品 页签 → 双列」"""
    blob = all_texts()
    act = ps.activity()
    if 'SearchRes' in act or 'SearchResult' in act:
        tabs = {t for _, _, _, _, t, d in items() if t in ('综合', '商品', '视频', '用户', '店铺', '直播')}
        if '商品' in tabs and ('已售' in blob):
            print('已在商品结果页')
            return True
        if '商品' in tabs:
            if tap_text('商品', max_y=420):
                time.sleep(3.5)
                print('已点商品页签')
                return True

    # 1) 进商城
    if not tap_text('商城', by_desc=True, max_y=260):
        print('找不到商城入口，请手动进入抖音商城')
        return False
    time.sleep(3.0)

    # 2) 点搜索框
    searched = False
    for y1, x1, x2, y2, t, d in items():
        if '搜索' in (d or '') and y1 < 400:
            ps.adb('shell', f'input tap {(x1 + x2) // 2} {(y1 + y2) // 2}')
            searched = True
            break
    if not searched:
        print('找不到搜索框')
        return False
    time.sleep(2.0)

    # 3) 输入关键词
    ps.adb('shell', 'input tap 547 300')
    time.sleep(0.6)
    ps.adb('shell', 'input keyevent KEYCODE_MOVE_END')
    for _ in range(15):
        ps.adb('shell', 'input keyevent 67')
    ps.adb('shell', f'input text "{keyword}"')
    time.sleep(0.8)
    ps.adb('shell', 'input keyevent 66')
    time.sleep(4.0)

    # 4) 商品页签
    if not tap_text('商品', max_y=420):
        print('找不到商品页签')
        return False
    time.sleep(3.5)

    # 5) 双列（卡片多，翻页快）
    for y1, x1, x2, y2, t, d in items():
        if '单列' in (d or '') and '按钮' in (d or ''):
            ps.adb('shell', f'input tap {(x1 + x2) // 2} {(y1 + y2) // 2}')
            time.sleep(2.5)
            break
    return True


# ---------------- 主流程 ----------------
def collect_screen(shot_path: Path):
    if not shot(shot_path):
        return [], None
    lines = ocr(shot_path)
    nodes = view_nodes()
    cards = dp.parse_cards(nodes, lines)
    return cards, Image.open(shot_path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--keyword', default='ai')
    ap.add_argument('--limit', type=int, default=100)
    ap.add_argument('--out', default='dy_ai.json')
    ap.add_argument('--imgdir', default='images/dy')
    ap.add_argument('--max-scroll', type=int, default=60)
    ap.add_argument('--no-nav', action='store_true')
    ap.add_argument('--seen', default='')
    ap.add_argument('--start-index', type=int, default=1)
    ap.add_argument('--probe', action='store_true', help='只解析当前屏幕，看看效果')
    args = ap.parse_args()

    imgdir = Path(args.imgdir)
    imgdir.mkdir(parents=True, exist_ok=True)

    if not args.no_nav:
        print(f'进入抖音商城搜索「{args.keyword}」…')
        if not ensure_goods_page(args.keyword):
            return 2
    else:
        print('跳过导航')

    if args.probe:
        cards, im = collect_screen(imgdir / '_probe.png')
        print(f'解析出 {len(cards)} 张卡：')
        for i, c in enumerate(cards, 1):
            print(f"{i}. {c['title'][:30]}")
            print(f"   ¥{c['price'] or '-'}  已售{c['sold'] or '-'}  促销={c['promo'][:20]!r}  "
                  f"店铺={c['shop'][:16]!r}  标签={c['tags'][:20]!r}  y={c['y_title']}")
            if im is not None:
                box = image_box(c, 0)
                if box:
                    im.crop(box).save(imgdir / f'_probe_{i}.png')
                    print(f'   裁图 -> _probe_{i}.png {box}')
        return 0

    results: list[dict] = []
    seen = set()
    if args.seen:
        try:
            for o in json.loads(Path(args.seen).read_text(encoding='utf-8')):
                if o.get('title'):
                    seen.add(o['title'])
            print(f'已加载 {len(seen)} 条历史标题')
        except Exception as e:
            print('读取 --seen 失败:', e)

    no_new = 0
    prev_bottom = 0
    for screen in range(1, args.max_scroll + 1):
        shot_path = imgdir / '_screen.png'
        cards, im = collect_screen(shot_path)
        fresh = [c for c in cards if c['title'] not in seen]
        added = 0
        for c in fresh:
            box = image_box(c, 0 if c['y_title'] > 1200 else 0)
            if box is None:
                continue
            idx = args.start_index + len(results)
            img_path = ''
            if im is not None:
                try:
                    ip = imgdir / f'{idx:03d}.png'
                    im.crop(box).save(ip)
                    img_path = str(ip).replace('\\', '/')
                except Exception as e:
                    print('  裁图失败:', e)
            c.update({'序号': idx, '图片': img_path, 'screen': screen})
            results.append(c)
            seen.add(c['title'])
            added += 1
        if im is not None:
            try:
                im.close()
            except Exception:
                pass
        try:
            shot_path.unlink()
        except Exception:
            pass

        no_new = 0 if added else no_new + 1
        print(f'第{screen}屏：新增 {added}，累计 {len(results)}')
        if len(results) >= args.limit:
            break
        if no_new >= 5:
            print('连续多屏无新增，停止')
            break
        ps.adb('shell', 'input swipe 636 2200 636 1300 320')
        time.sleep(2.0)

    results = results[:args.limit]
    Path(args.out).write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding='utf-8')
    print(f'\n完成：{len(results)} 条（带图 {sum(1 for r in results if r["图片"])} 张）-> {args.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

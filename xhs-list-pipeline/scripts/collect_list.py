"""collect_list.py —— 只解析搜索列表页，采 100 条（不进详情、不抓包）

用法：
    python collect_list.py --keyword adidas --limit 100 --out list100.json
    python collect_list.py --keyword nike --limit 50

产出：
    list100.json            每条：标题/价格/已售/店铺/店铺销量/几年老店/评分/图片路径
    images/list/<序号>.png   每条的展示图（从整屏截图裁出来的）
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import time
from pathlib import Path

from PIL import Image

# ---- 载入解析器与手机控制模块 ----
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('ps', str(HERE / 'phone_specs.py'))
ps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ps)

spec2 = importlib.util.spec_from_file_location('lp', str(HERE / 'list_parse.py'))
lp = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(lp)

ADB = ps.ADB

# 列表页两列的标准横向范围（实测：左 52-593，右 679-1220）
COL_LEFT = (52, 593)
COL_RIGHT = (679, 1220)
HEADER_BOTTOM = 600        # 顶部搜索栏/页签的底边，图片区域不能进到这里
SCREEN_H = 2772


def column_box(card, col_bounds):
    """按卡片所在列返回 (x1, x2) —— 用列标准宽度，而不是标题文字的宽度"""
    cx = (card['x1'] + card['x2']) // 2
    return COL_LEFT if cx < 636 else COL_RIGHT


def image_box(card, col_bounds):
    """算卡片展示图的裁剪框。

    原则：**宁可多裁，不要少裁**。
    · 上界优先取"上一张卡文字的下沿"（评价行属于本卡内部，不能当分隔）
    · 若这样算出来的高度比正方形还矮，就退回正方形（y_title - 列宽）
    · 结果仍被顶部搜索区挡住 → 返回 None，等下一屏
    """
    x1, x2 = column_box(card, col_bounds)
    w = x2 - x1
    bottom = card['y_title'] - 4

    top = 0
    nq = card.get('prev_nq_y2') or 0
    if nq and nq < bottom - 40:
        top = nq + 4
    # 高度不够（或没有可用的分隔）→ 用正方形
    if not top or bottom - top < w:
        top = bottom - w
    # 太高则收敛，避免框进上一张卡的图
    if bottom - top > int(w * 2.2):
        top = bottom - int(w * 2.2)
    if top < HEADER_BOTTOM:          # 被顶部搜索区挡住 → 下一屏再裁
        return None
    if bottom > SCREEN_H:
        return None
    return (x1, top, x2, bottom)


def fast_shot(path: Path) -> bool:
    """用 exec-out 直接拿 PNG（比 screencap + pull 快）"""
    try:
        p = subprocess.run([ADB, 'exec-out', 'screencap -p'], capture_output=True, timeout=90)
        data = p.stdout or b''
        if data[:4] != b'\x89PNG':
            return False
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return True
    except Exception as e:
        print('  截图失败:', e)
        return False


def text_nodes():
    r = ps.dump_root()
    if r is None:
        return []
    out = []
    for el, b in ps.nodes(r):
        t = ps.txt(el)
        if t:
            out.append((b[0], b[1], b[2], b[3], t))
    return out


def clean_price(v: str) -> str:
    v = (v or '').strip().rstrip('.')
    return v


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--keyword', default='adidas')
    ap.add_argument('--limit', type=int, default=100)
    ap.add_argument('--out', default='list100.json')
    ap.add_argument('--imgdir', default='images/list')
    ap.add_argument('--max-scroll', type=int, default=60)
    ap.add_argument('--no-nav', action='store_true', help='不重新进入搜索页，从当前滚动位置继续')
    ap.add_argument('--seen', default='', help='已有结果的 json，按其标题去重（继续采集）')
    ap.add_argument('--start-index', type=int, default=1, help='序号起始值')
    args = ap.parse_args()

    imgdir = Path(args.imgdir)
    imgdir.mkdir(parents=True, exist_ok=True)

    if args.no_nav:
        print('跳过导航，从当前页面继续…')
        if ps.page_kind(ps.dump_root()) != 'goods':
            print('当前不在商品列表页，先手动进入或用不带 --no-nav 的方式跑')
            return 2
    else:
        print(f'进入「{args.keyword}」商品搜索页…')
        if not ps.to_goods(args.keyword):
            print('入场失败：确认手机停在首页或搜索页')
            return 2
    # 确保在「商品」页签
    r = ps.dump_root()
    for el, b in ps.nodes(r):
        if ps.txt(el) == '商品':
            ps.adb('shell', f'input tap {(b[0] + b[2]) // 2} {(b[1] + b[3]) // 2}')
            time.sleep(3.5)
            break

    results: list[dict] = []
    seen: set[str] = set()
    if args.seen:
        try:
            old = json.loads(Path(args.seen).read_text(encoding='utf-8'))
            for o in old:
                if o.get('title'):
                    seen.add(o['title'])
            print(f'已加载 {len(seen)} 条历史标题用于去重')
        except Exception as e:
            print('读取 --seen 失败:', e)
    no_new = 0

    for screen in range(1, args.max_scroll + 1):
        nodes = text_nodes()
        cards = lp.parse_page(nodes)
        fresh = [c for c in cards if c['title'] not in seen]

        if fresh:
            shot = imgdir / f'_screen_{screen}.png'
            has_shot = fast_shot(shot)
            im = Image.open(shot) if has_shot else None

            skipped = 0
            for c in fresh:
                box = image_box(c, None) if im is not None else None
                if im is not None and box is None:
                    skipped += 1        # 图被挡住，留给下一屏再收
                    continue
                idx = args.start_index + len(results)
                c['price'] = clean_price(c['price'])
                img_path = ''
                if im is not None and box is not None:
                    try:
                        crop = im.crop(box)
                        ip = imgdir / f'{idx:03d}.png'
                        crop.save(ip)
                        img_path = str(ip).replace('\\', '/')
                    except Exception as e:
                        print('  裁图失败:', e)
                c['图片'] = img_path
                c['序号'] = idx
                results.append(c)
                seen.add(c['title'])
            if skipped:
                print(f'      （{skipped} 张图被顶部遮挡，留到下一屏）')
            try:
                if im is not None:
                    im.close()
            except Exception:
                pass
            try:
                if shot.exists():
                    shot.unlink()
            except Exception:
                pass
            print(f'第{screen}屏：新增 {len(fresh)}，累计 {len(results)}')
            no_new = 0
        else:
            no_new += 1
            print(f'第{screen}屏：无新增（连续 {no_new} 次）')

        if len(results) >= args.limit:
            break
        if no_new >= 4:
            print('连续多屏无新增，停止')
            break

        ps.adb('shell', 'input swipe 636 2100 636 1400 300')
        time.sleep(2.2)

    results = results[:args.limit]
    Path(args.out).write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding='utf-8')
    with_img = sum(1 for r in results if r.get('图片'))
    print(f'\n完成：{len(results)} 条（带图 {with_img} 张）-> {args.out}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

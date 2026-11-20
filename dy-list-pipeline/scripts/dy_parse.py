"""dy_parse.py —— 解析抖音商城搜索结果（双列卡片）

数据来源有两路，因为抖音把关键信息拆开藏了：
  · uiautomator dump  → 标题、已售xx件、回头客xx、十万粉丝（这些进了无障碍树）
  · 截图 OCR          → 价格 ¥xx、促销语、店铺名（这些是自绘视图，树里没有）

卡片纵向布局（以标题 y 为基准，实测偏移）：
    展示图
    品牌+标题          y_title
    促销语             y_title + 75
    价格 + 已售        y_title + 145
    店铺 + 回头客       y_title + 240
"""
from __future__ import annotations

import re

PRICE = re.compile(r'[¥￥]\s*([\d]+(?:\.[\d]+)?)')
SOLD = re.compile(r'已售\s*([\d.]+(?:万|\+)*)\s*件?')
SHOP_TAIL = ('旗舰店', '专卖店', '专营店', '店')
PROMO_HINT = ('减', '券', '价', '包邮', '补贴', '折', '同价', '秒杀', '特价')


def clean(s: str) -> str:
    """OCR 结果里汉字之间会有空格，去掉；同时清理零宽字符"""
    s = (s or '').replace('\u200b', '')
    s = re.sub(r'(?<=[\u4e00-\u9fff])\s+(?=[\u4e00-\u9fff])', '', s)
    return s.strip()


def is_shop(text: str) -> bool:
    t = clean(text).rstrip('>〉 ')
    if len(t) < 3 or len(t) > 24:
        return False
    if '已售' in t or '¥' in t:
        return False
    return t.endswith(SHOP_TAIL)


def find_field(ocr_lines, x_from, x_to, y_from, y_to, pred):
    """在指定列的 y 区间里找第一个满足 pred 的 OCR 行（必须同时按 x 限列，否则左右卡会串）"""
    for ln in ocr_lines:
        cx = ln['x'] + ln['w'] / 2
        if not (x_from - 30 <= cx <= x_to + 30):
            continue
        if y_from <= ln['y'] <= y_to and pred(clean(ln['text'])):
            return ln
    return None


def parse_cards(view_nodes, ocr_lines, screen_w=1272):
    """
    view_nodes: [(x1,y1,x2,y2,text)]  来自 uiautomator
    ocr_lines:  [{'text','x','y','w','h'}]  来自截图 OCR
    返回卡片列表（按 y 排序，左右列合并）
    """
    # 1) 找出所有"标题"节点：位于卡片区（y > 900），宽度 > 300，非数字非已售
    titles = []
    for x1, y1, x2, y2, t in view_nodes:
        t = clean(t)
        if not t or len(t) < 8:
            continue
        if y1 < 900:
            continue
        if (x2 - x1) < 300:
            continue
        if SOLD.search(t) or PRICE.search(t):
            continue
        titles.append({'title': t, 'y': y1, 'x1': x1, 'x2': x2})

    # 2) 去重（同一标题可能出现多次），按 y 排序
    uniq, seen = [], set()
    for c in sorted(titles, key=lambda c: (c['y'], c['x1'])):
        if c['title'] in seen:
            continue
        seen.add(c['title'])
        uniq.append(c)

    # 3) 每张卡补齐 OCR 字段
    cards = []
    for i, c in enumerate(uniq):
        yt = c['y']
        bottom = uniq[i + 1]['y'] if i + 1 < len(uniq) else yt + 320
        band_lo, band_hi = yt - 40, bottom + 10

        cx1, cx2 = c['x1'], c['x2']
        price_ln = find_field(ocr_lines, cx1, cx2, yt + 40, yt + 260,
                              lambda t: bool(PRICE.search(t)))
        promo_ln = find_field(
            ocr_lines, cx1, cx2, yt + 20, yt + 160,
            lambda t: (not PRICE.search(t)) and (not SOLD.search(t))
            and (not is_shop(t)) and len(t) >= 4)
        shop_ln = find_field(ocr_lines, cx1, cx2, yt + 100, yt + 430, is_shop)

        sold = ''
        for x1, y1, x2, y2, t in view_nodes:
            if abs(y1 - (yt + 145)) < 120 and '已售' in clean(t) and \
                    (x1 + x2) // 2 // 636 == (c['x1'] + c['x2']) // 2 // 636:
                m = SOLD.search(clean(t))
                if m:
                    sold = m.group(1)
                    break

        tags = []
        for x1, y1, x2, y2, t in view_nodes:
            tc = clean(t)
            if yt + 130 <= y1 <= yt + 300 and any(k in tc for k in ('回头客', '粉丝', '好评率', '好评', '官方正品', '旗舰')):
                if (x1 + x2) // 2 // 636 == (c['x1'] + c['x2']) // 2 // 636:
                    tags.append(tc)

        m = PRICE.search(clean(price_ln['text'])) if price_ln else None
        cards.append({
            'title': c['title'],
            'price': m.group(1) if m else '',
            'sold': sold,
            'promo': clean(promo_ln['text']) if promo_ln else '',
            'shop': (clean(shop_ln['text']).rstrip('>〉 ')
                     .rstrip('·．. ') if shop_ln else ''),
            'tags': ' '.join(tags[:2]),
            'y_title': yt,
            'x1': c['x1'],
            'x2': c['x2'],
            'band': (band_lo, band_hi),
        })
    return cards

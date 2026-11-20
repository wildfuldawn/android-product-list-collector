"""list_parse.py —— 解析小红书「商品搜索列表页」的卡片（不点进详情）

每张卡片在无障碍树里是这些节点（按 y 排列）：
    展示图（无文字节点）
    用户评价        “真的太庆幸选了这家!...”     ← 裁图要排除
    标题            adidas·春季新款Oversize经典三条纹...
    促销语          限时立减130元 今日发
    价格+已售        券后¥269.已售2527
    店铺            耶运动旗舰店   销量4万+ / 6年老店 / 好评率99%
"""
from __future__ import annotations

import re

PRICE_SOLD = re.compile(r'¥\s*([\d.]+)[^\d]*已售\s*([\d.]+(?:万|\+)*)')
SALES = re.compile(r'销量\s*([\d.]+(?:万|\+)*)')
OLD = re.compile(r'(\d+)\s*年老店')
RATING = re.compile(r'([\d.]+)\s*分')
GOODRATE = re.compile(r'好评率\s*([\d.]+)\s*%')
PROMO = re.compile(
    r'立减|满\s*\d+\s*减|券后|入会价|关注后|退货包运费|今日发|'
    r'人加购|人购买|回头客|好评率|新客|'
    r'^包邮|^\d+人|周销|月销|小时.*(购买|发货)|^\d+\s*元|^\d+$')
TABS = {'综合', '销量', '店铺', '直播', '全部', '用户', '商品', '图片', '视频',
        '问一问', '大家都在搜', '搜索', '返回', '最新', '实时', '价格升序', '价格降序'}
SHOP_TAIL = ('旗舰店', '专营店', '专卖店', '店')


def is_quote(t: str) -> bool:
    return bool(t) and len(t) < 60 and ('“' in t or '”' in t)


def is_shop(t: str) -> bool:
    if not t or len(t) > 22:
        return False
    if '销量' in t or '已售' in t or '¥' in t:
        return False
    return t.endswith(SHOP_TAIL)


def is_title(t: str) -> bool:
    if not t or len(t) < 8 or len(t) > 80:
        return False
    if t in TABS:
        return False
    if PRICE_SOLD.search(t) or SALES.search(t) or OLD.search(t) or RATING.search(t):
        return False
    if is_shop(t) or is_quote(t):
        return False
    if PROMO.search(t):
        return False
    if ('¥' in t) or ('已售' in t) or ('好评率' in t) or ('加购' in t):
        return False
    return True


def split_columns(nodes):
    left = [n for n in nodes if (n[0] + n[2]) // 2 < 636]
    right = [n for n in nodes if (n[0] + n[2]) // 2 >= 636]
    return left, right


def parse_column(nodes):
    """一列里按 y 排序；遇到标题开新卡片。

    额外记录 quote_y：紧邻标题上方那行用户评价的上边界，裁图时用它当下界。
    """
    nodes = sorted(nodes, key=lambda n: n[1])
    cards = []
    cur = None
    prev = None            # 上一个文本节点 (text, y1, y2)
    for x1, y1, x2, y2, t in nodes:
        t = (t or '').strip()
        if not t:
            continue
        if is_title(t):
            qy = 0
            if prev and is_quote(prev[0]) and (y1 - 130) <= prev[2] <= y1:
                qy = prev[1]
            prev_y2 = prev[2] if prev else 0
            # 裁图上界要用"上一张卡的文字下沿"，评价行在卡片内部，不能当分隔
            prev_nq = 0
            if prev and not is_quote(prev[0]):
                prev_nq = prev[2]
            cur = {'title': t, 'y_title': y1, 'x1': x1, 'x2': x2, 'quote_y': qy,
                   'prev_y2': prev_y2, 'prev_nq_y2': prev_nq,
                   'price': '', 'sold': '', 'shop': '', 'sales': '', 'old': '',
                   'rating': '', 'goodrate': ''}
            cards.append(cur)
            prev = (t, y1, y2)
            continue
        prev = (t, y1, y2)
        if cur is None or is_quote(t):
            continue
        m = PRICE_SOLD.search(t)
        if m:
            cur['price'] = m.group(1)
            cur['sold'] = m.group(2)
            continue
        m = SALES.search(t)
        if m:
            cur['sales'] = m.group(1)
            continue
        m = OLD.search(t)
        if m:
            cur['old'] = m.group(1) + '年'
            continue
        m = GOODRATE.search(t)
        if m:
            cur['goodrate'] = m.group(1) + '%'
            continue
        m = RATING.search(t)
        if m:
            cur['rating'] = m.group(1)
            continue
        if is_shop(t) and not cur['shop']:
            cur['shop'] = t
    return cards


def parse_page(root_nodes):
    left, right = split_columns(root_nodes)
    cards = parse_column(left) + parse_column(right)
    cards.sort(key=lambda c: (c['y_title'], c['x1']))
    return [c for c in cards if c['price'] or c['shop']]

"""dy_build_xlsx.py —— 抖音商城搜索列表结果出表（带展示图）"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

from openpyxl import Workbook
from openpyxl.drawing.image import Image as XLImage
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from PIL import Image as PILImage

HEADERS = ['序号', '商品标题', '价格', '已售', '促销语', '店铺', '店铺标签', '展示图']
WIDTHS = [6, 44, 10, 10, 26, 24, 18, 24]
IMG_W = 150
MAX_H = 260
MIN_ROW_H = 80


def _resolve(p: str, base: Path):
    if not p:
        return None
    q = Path(p)
    for cand in (q, base / q, Path.cwd() / q):
        try:
            if cand.exists():
                return cand
        except OSError:
            continue
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--json', default='dy_ai.json')
    ap.add_argument('--out', default='抖音_AI_商品列表100.xlsx')
    args = ap.parse_args()

    json_path = Path(args.json)
    base = json_path.resolve().parent
    rows = json.loads(json_path.read_text(encoding='utf-8'))
    if not rows:
        print('没有数据')
        return 2

    wb = Workbook()
    ws = wb.active
    ws.title = '抖音商品'
    ws.append(HEADERS)
    for c in range(1, len(HEADERS) + 1):
        cell = ws.cell(row=1, column=c)
        cell.font = Font(bold=True, color='FFFFFF')
        cell.fill = PatternFill('solid', fgColor='161823')
        cell.alignment = Alignment(horizontal='center', vertical='center')
    for i, w in enumerate(WIDTHS, 1):
        ws.column_dimensions[get_column_letter(i)].width = w

    tmp = Path(tempfile.mkdtemp(prefix='dy_thumbs_'))
    img_col = get_column_letter(HEADERS.index('展示图') + 1)
    placed = 0

    for n, r in enumerate(rows, 1):
        rr = n + 1
        ws.cell(row=rr, column=1, value=n)
        ws.cell(row=rr, column=2, value=r.get('title', ''))
        ws.cell(row=rr, column=3, value=f"¥{r['price']}" if r.get('price') else '')
        ws.cell(row=rr, column=4, value=r.get('sold', ''))
        ws.cell(row=rr, column=5, value=r.get('promo', ''))
        ws.cell(row=rr, column=6, value=r.get('shop', ''))
        ws.cell(row=rr, column=7, value=r.get('tags', ''))

        row_h = MIN_ROW_H
        img_path = _resolve(r.get('图片') or '', base)
        if img_path is not None:
            try:
                im = PILImage.open(img_path)
                ratio = im.height / max(1, im.width)
                disp_h = min(int(IMG_W * ratio), MAX_H)
                im.thumbnail((IMG_W * 2, disp_h * 2))
                th = tmp / f'{n:03d}.png'
                im.convert('RGB').save(th)
                im.close()
                xl = XLImage(str(th))
                xl.width = IMG_W
                xl.height = disp_h
                ws.add_image(xl, f'{img_col}{rr}')
                row_h = max(disp_h * 0.75, MIN_ROW_H)
                placed += 1
            except Exception as e:
                print('图片嵌入失败', n, e)
        ws.row_dimensions[rr].height = row_h

    ws.freeze_panes = 'C2'
    wb.save(args.out)
    print(f'{len(rows)} 行 / 嵌入图 {placed} 张 -> {args.out}')
    return 0


if __name__ == '__main__':
    sys.exit(main())

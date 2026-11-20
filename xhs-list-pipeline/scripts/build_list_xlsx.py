"""build_list_xlsx.py —— 把列表页采集结果出成 xlsx（带展示图）"""
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

HEADERS = ['序号', '商品标题', '价格', '已售', '店铺', '好评率', '店铺销量', '几年老店', '展示图']
WIDTHS = [6, 46, 10, 10, 22, 9, 11, 10, 24]
ROW_H = 118
IMG_W = 150


def _resolve_img(p: str, base: Path) -> Path | None:
    """json 里存的多半是相对路径，要相对 json 所在目录解析。"""
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
    ap.add_argument('--json', default='list_ai.json')
    ap.add_argument('--out', default='小红书_AI_商品列表100.xlsx')
    args = ap.parse_args()

    json_path = Path(args.json)
    base = json_path.resolve().parent
    rows = json.loads(json_path.read_text(encoding='utf-8'))
    if not rows:
        print('没有数据')
        return 2

    wb = Workbook()
    ws = wb.active
    ws.title = '商品列表'
    ws.append(HEADERS)
    for c in range(1, len(HEADERS) + 1):
        cell = ws.cell(row=1, column=c)
        cell.font = Font(bold=True, color='FFFFFF')
        cell.fill = PatternFill('solid', fgColor='C00000')
        cell.alignment = Alignment(horizontal='center', vertical='center')
    for i, w in enumerate(WIDTHS, 1):
        ws.column_dimensions[get_column_letter(i)].width = w

    tmp = Path(tempfile.mkdtemp(prefix='xhs_thumbs_'))
    img_col = get_column_letter(HEADERS.index('展示图') + 1)
    placed = 0

    for n, r in enumerate(rows, 1):
        rr = n + 1
        ws.cell(row=rr, column=1, value=n)
        ws.cell(row=rr, column=2, value=r.get('title', ''))
        ws.cell(row=rr, column=3, value=f"¥{r['price']}" if r.get('price') else '')
        ws.cell(row=rr, column=4, value=r.get('sold', ''))
        ws.cell(row=rr, column=5, value=r.get('shop', ''))
        ws.cell(row=rr, column=6, value=r.get('goodrate', ''))
        ws.cell(row=rr, column=7, value=r.get('sales', ''))
        ws.cell(row=rr, column=8, value=r.get('old', ''))
        p = r.get('图片') or ''
        row_h = ROW_H
        img_path = _resolve_img(p, base)
        if img_path is not None:
            try:
                im = PILImage.open(img_path)
                ratio = im.height / max(1, im.width)
                disp_h = min(int(IMG_W * ratio), 260)      # 显示高度上限 260px
                im.thumbnail((IMG_W * 2, disp_h * 2))
                th = tmp / f'{n:03d}.png'
                im.convert('RGB').save(th)
                im.close()
                xl = XLImage(str(th))
                xl.width = IMG_W
                xl.height = disp_h
                ws.add_image(xl, f'{img_col}{rr}')
                row_h = max(disp_h * 0.75, 80)             # 行高按图高换算
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

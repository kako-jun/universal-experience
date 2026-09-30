#!/usr/bin/env python3
"""サンプル画像集（#78/#99）用のビットマップフォント（BMFont 形式）を生成する。

使い方（リポのルートで）:

    uv run --with pillow==12.3.0 python3 tools/generate_font_atlases.py

何をするか:
  1. OFL ライセンスのフォント（Noto Sans / Noto Sans JP）を、版（コミット）を
     固定した公式配布元から取得する。SHA-256 が合わなければ中断する。
     取得したフォント本体はリポに入れない（作業ディレクトリは実行後に削除）。
  2. サンプル画像に実際に使う文字だけを、固定サイズでラスタライズし、
     BMFont テキスト形式（.fnt）+ 白地 RGBA のアトラス PNG として
     ``tools/fonts/`` へ書き出す。
  3. ``tools/generate_samples.dart`` が ``package:image`` の ``BitmapFont.fromFnt``
     でそれを読み、文字を描く。``package:image`` 同梱の Arial ビットマップは使わない。

出力は Pillow / FreeType の版に依存するため、Pillow は上の版に固定している。
同じ入力・同じ版なら同じバイト列になる（グリフ順・パッキングは決定的）。

生成物（``tools/fonts/*.fnt`` / ``*.png``）は Noto Sans / Noto Sans JP の派生物として
SIL OFL 1.1 の下にある。著作権表示とライセンス全文は ``tools/fonts/OFL-*.txt`` と
``tools/fonts/README.md`` にある。
"""

from __future__ import annotations

import hashlib
import shutil
import sys
import tempfile
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUT_DIR = Path(__file__).resolve().parent / "fonts"

# 配布元（コミット固定）。
_NOTO_SANS_COMMIT = "025970232f4f8ff349310d9785431e87d20ed27c"  # notofonts.github.io
_NOTO_CJK_COMMIT = "f8d157532fbfaeda587e826d4cd5b21a49186f7c"  # noto-cjk

# (配布ファイル名, URL, SHA-256)
_SOURCES = {
    "NotoSans-Regular.ttf": (
        "https://raw.githubusercontent.com/notofonts/notofonts.github.io/"
        f"{_NOTO_SANS_COMMIT}/fonts/NotoSans/full/ttf/NotoSans-Regular.ttf",
        "f5f552c8c5edb61fe6efb824baf4d4de47b1a8689ab4925ff43f7bd6a4ebece5",
    ),
    "NotoSans-Bold.ttf": (
        "https://raw.githubusercontent.com/notofonts/notofonts.github.io/"
        f"{_NOTO_SANS_COMMIT}/fonts/NotoSans/full/ttf/NotoSans-Bold.ttf",
        "3a08a47daa00cade516425c15c57615aef2fd418ec9811a7b9f465088f92cc05",
    ),
    "NotoSansJP-Regular.otf": (
        "https://raw.githubusercontent.com/notofonts/noto-cjk/"
        f"{_NOTO_CJK_COMMIT}/Sans/SubsetOTF/JP/NotoSansJP-Regular.otf",
        "dff723ba59d57d136764a04b9b2d03205544f7cd785a711442d6d2d085ac5073",
    ),
    "NotoSansJP-Bold.otf": (
        "https://raw.githubusercontent.com/notofonts/noto-cjk/"
        f"{_NOTO_CJK_COMMIT}/Sans/SubsetOTF/JP/NotoSansJP-Bold.otf",
        "1b0edfb500b73a4fa8a4fcaae1bbbd403994e08e73e3e0da37e70d3853f42c5f",
    ),
}

# ── 収録する文字 ─────────────────────────────────────────────────────
# サンプル画像で実際に描く文字だけ。generate_samples.dart は、ここに無い
# 文字を描こうとすると例外で止まる（黙って欠落させない）。
_ASCII = "".join(chr(c) for c in range(0x20, 0x7F))
_HIRAGANA = "".join(chr(c) for c in range(0x3041, 0x3097))
_KATAKANA = "".join(chr(c) for c in range(0x30A1, 0x30FB)) + "ー"
_JP_PUNCT = "、。・「」（）～：　"
# 案内板（出口・駅・営業中・のりば案内）に使う漢字。
_KANJI = "出入口駅営業中案内番線行方面央川沿北旧市街港場前東丘緑地公園普通環状足元注意乗改札時刻表"
_JP_CHARS = _ASCII + _HIRAGANA + _KATAKANA + _JP_PUNCT + _KANJI
# 見出し（48px）と大きな案内表示（96px）は使う文字だけに絞り、アトラスを小さく保つ。
_JP_HEADING_CHARS = _ASCII + "のりば案内出入口駅営業中"
_JP_SIGN_CHARS = "出入口駅営業中"

# 出力名 → (フォントファイル, サイズ px, 収録文字)
_FONTS = {
    "noto_sans_regular_18": ("NotoSans-Regular.ttf", 18, _ASCII),
    "noto_sans_regular_24": ("NotoSans-Regular.ttf", 24, _ASCII),
    "noto_sans_bold_48": ("NotoSans-Bold.ttf", 48, _ASCII),
    "noto_sans_jp_regular_24": ("NotoSansJP-Regular.otf", 24, _JP_CHARS),
    "noto_sans_jp_bold_48": ("NotoSansJP-Bold.otf", 48, _JP_HEADING_CHARS),
    "noto_sans_jp_bold_96": ("NotoSansJP-Bold.otf", 96, _JP_SIGN_CHARS),
}

# 以前の Arial ビットマップ（package:image）と行の上端が揃うよう、ベースラインを
# 「サイズ × 0.93」の位置に置く（Noto Sans の実 ascent は約 1.07 倍で、そのままだと
# 文字が数 px 下がり、既存サンプルのレイアウトがずれる）。
_ASCENT_EM = 0.93
_LINE_GAP_EM = 0.25
_ATLAS_WIDTH = 1024


def _fetch(workdir: Path) -> None:
    for name, (url, sha) in _SOURCES.items():
        dest = workdir / name
        print(f"fetch {name}")
        with urllib.request.urlopen(url) as res:  # noqa: S310 (固定 URL)
            data = res.read()
        digest = hashlib.sha256(data).hexdigest()
        if digest != sha:
            sys.exit(f"SHA-256 mismatch for {name}: {digest} != {sha}")
        dest.write_bytes(data)


def _render_font(name: str, font_path: Path, size: int, chars: str) -> None:
    font = ImageFont.truetype(
        str(font_path), size, layout_engine=ImageFont.Layout.BASIC
    )
    ascent = round(size * _ASCENT_EM)
    line_height = ascent + round(size * _LINE_GAP_EM)

    glyphs = []  # (code, bitmap(L) | None, xoffset, yoffset, xadvance)
    for ch in dict.fromkeys(chars):  # 重複除去（順序維持）
        advance = round(font.getlength(ch))
        left, top, right, bottom = font.getbbox(ch, anchor="ls")
        w, h = right - left, bottom - top
        if w <= 0 or h <= 0:
            glyphs.append((ord(ch), None, 0, 0, advance))
            continue
        canvas = Image.new("L", (w, h), 0)
        ImageDraw.Draw(canvas).text((-left, -top), ch, font=font, fill=255, anchor="ls")
        glyphs.append((ord(ch), canvas, left, ascent + top, advance))

    # 高さ降順・コード昇順のシェルフ詰め（決定的）。
    order = sorted(
        (g for g in glyphs if g[1] is not None),
        key=lambda g: (-g[1].height, g[0]),
    )
    placements = {}
    x = y = shelf_h = 0
    for code, bmp, *_ in order:
        if x + bmp.width + 1 > _ATLAS_WIDTH:
            x, y, shelf_h = 0, y + shelf_h + 1, 0
        placements[code] = (x, y)
        x += bmp.width + 1
        shelf_h = max(shelf_h, bmp.height)
    atlas_h = y + shelf_h + 1

    atlas = Image.new("RGBA", (_ATLAS_WIDTH, atlas_h), (255, 255, 255, 0))
    for code, bmp, *_ in order:
        px, py = placements[code]
        white = Image.new("RGBA", bmp.size, (255, 255, 255, 255))
        white.putalpha(bmp)
        atlas.paste(white, (px, py))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT_DIR / f"{name}.png", optimize=True)

    bold = 1 if "Bold" in font_path.name else 0
    lines = [
        f'info face="{font_path.stem}" size={size} bold={bold} italic=0 charset="" '
        "unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1",
        f"common lineHeight={line_height} base={ascent} scaleW={_ATLAS_WIDTH} "
        f"scaleH={atlas_h} pages=1 packed=0",
        f'page id=0 file="{name}.png"',
        f"chars count={len(glyphs)}",
    ]
    for code, bmp, xoff, yoff, adv in sorted(glyphs, key=lambda g: g[0]):
        px, py = placements.get(code, (0, 0))
        w, h = (bmp.width, bmp.height) if bmp is not None else (0, 0)
        lines.append(
            f"char id={code} x={px} y={py} width={w} height={h} "
            f"xoffset={xoff} yoffset={yoff} xadvance={adv} page=0 chnl=15"
        )
    (OUT_DIR / f"{name}.fnt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {name}.fnt / .png ({len(glyphs)} glyphs, atlas 1024x{atlas_h})")


def main() -> None:
    workdir = Path(tempfile.mkdtemp(prefix="ue-fonts-"))
    try:
        _fetch(workdir)
        for name, (file, size, chars) in _FONTS.items():
            _render_font(name, workdir / file, size, chars)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()

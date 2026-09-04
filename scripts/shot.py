#!/usr/bin/env python3
"""Render a preview image of a h4x0r workspace, without opening a window.

Builds the layout in a detached tmux session at an exact character size, reads
every pane back as ANSI text, and draws the result with PIL. Deterministic,
exactly the dimensions you ask for, and nothing on your desktop can wander into
the frame.

    scripts/shot.py --layout grid --palette phosphor --out preview.png
"""
import argparse, os, re, shutil, subprocess, sys, tempfile, time

from PIL import Image, ImageDraw, ImageFont

SESSION = "h4x0rshot"
DEFAULT_FG = (200, 200, 200)
DEFAULT_BG = (10, 12, 10)

FONT_CANDIDATES = ["BitstromWera Nerd Font", "Noto Sans Mono CJK TC",
                   "Noto Sans CJK TC", "DejaVu Sans Mono"]


def sh(*args, **kw):
    return subprocess.run(args, capture_output=True, text=True, **kw).stdout


def font_file(name):
    return sh("fc-match", "-f", "%{file}", name).strip()


class FontSet:
    """Primary font plus fallbacks, with per-glyph coverage detection.

    PIL happily draws .notdef boxes for missing glyphs, so coverage is probed by
    comparing a glyph's bitmap against the same font's notdef bitmap.
    """

    def __init__(self, size):
        self.fonts = []
        for name in FONT_CANDIDATES:
            path = font_file(name)
            if path and os.path.exists(path):
                try:
                    self.fonts.append(ImageFont.truetype(path, size))
                except OSError:
                    pass
        if not self.fonts:
            raise SystemExit("shot.py: no usable fonts found")
        self.notdef = [self._bitmap(f, "\U000f8fed") for f in self.fonts]
        self.blank = [self._bitmap(f, " ") for f in self.fonts]
        self.cache = {}

    @staticmethod
    def _bitmap(font, ch):
        img = Image.new("L", (64, 64), 0)
        ImageDraw.Draw(img).text((8, 4), ch, font=font, fill=255)
        return img.tobytes()

    def pick(self, ch):
        hit = self.cache.get(ch)
        if hit is not None:
            return hit
        chosen = self.fonts[0]
        for i, f in enumerate(self.fonts):
            bm = self._bitmap(f, ch)
            if bm != self.notdef[i] and bm != self.blank[i]:
                chosen = f
                break
        self.cache[ch] = chosen
        return chosen


CUBE = [0, 95, 135, 175, 215, 255]
BASIC = [(0, 0, 0), (205, 49, 49), (13, 188, 121), (229, 229, 16),
         (36, 114, 200), (188, 63, 188), (17, 168, 205), (229, 229, 229),
         (102, 102, 102), (241, 76, 76), (35, 209, 139), (245, 245, 67),
         (59, 142, 234), (214, 112, 214), (41, 184, 219), (255, 255, 255)]


def xterm256(n):
    if n < 16:
        return BASIC[n]
    if n < 232:
        n -= 16
        return (CUBE[n // 36 % 6], CUBE[n // 6 % 6], CUBE[n % 6])
    v = 8 + (n - 232) * 10
    return (v, v, v)


SGR = re.compile(r"\x1b\[([0-9;]*)m")
OTHER_CSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[()][A-B0-9]")


def parse_line(line, cols):
    """-> list of (char, fg, bg) of length cols."""
    cells, fg, bg, i = [], DEFAULT_FG, DEFAULT_BG, 0
    line = OTHER_CSI.sub(lambda m: m.group(0) if m.group(0).endswith("m") else "", line)
    while i < len(line) and len(cells) < cols:
        m = SGR.match(line, i)
        if m:
            parts = [int(x) if x else 0 for x in (m.group(1) or "0").split(";")]
            j = 0
            while j < len(parts):
                p = parts[j]
                if p == 0:
                    fg, bg = DEFAULT_FG, DEFAULT_BG
                elif p == 39:
                    fg = DEFAULT_FG
                elif p == 49:
                    bg = DEFAULT_BG
                elif 30 <= p <= 37:
                    fg = BASIC[p - 30]
                elif 90 <= p <= 97:
                    fg = BASIC[p - 90 + 8]
                elif 40 <= p <= 47:
                    bg = BASIC[p - 40]
                elif 100 <= p <= 107:
                    bg = BASIC[p - 100 + 8]
                elif p in (38, 48) and j + 1 < len(parts):
                    mode = parts[j + 1]
                    if mode == 5 and j + 2 < len(parts):
                        col = xterm256(parts[j + 2]); j += 2
                    elif mode == 2 and j + 4 < len(parts):
                        col = tuple(parts[j + 2:j + 5]); j += 4
                    else:
                        j += 1; col = None
                    if col:
                        if p == 38: fg = col
                        else: bg = col
                j += 1
            i = m.end()
            continue
        cells.append((line[i], fg, bg))
        i += 1
    while len(cells) < cols:
        cells.append((" ", DEFAULT_FG, DEFAULT_BG))
    return cells


PALETTES = {
    "phosphor":  "ffffff 87ff87 00d75f 00af5f 00875f 005f00 ffaf00 ff2a2a",
    "amber":     "fff2d0 ffd479 ffb000 d98f00 a86b00 4a2f00 fff200 ff5c1a",
    "ice":       "ffffff b3f6ff 4fd6ff 27a9d9 1b7ba6 0a3a4a ffd166 ff5c7a",
    "crimson":   "ffd7de ff6b8a e01040 b00c33 7a0a24 3d0512 ffb000 ff2a2a",
    "synthwave": "fdf6ff ff8ae2 f92aad c01d8a 7a1a63 2b0a3d 36f9f6 ff5555",
    "mono":      "ffffff e0e0e0 b8b8b8 8a8a8a 5c5c5c 2e2e2e ffffff ff5555",
}

BTOP_THEME = """# generated by scripts/shot.py so btop matches the h4x0r palette
theme[main_bg]="#0a0c0a"
theme[main_fg]="#{MAIN}"
theme[title]="#{HEAD}"
theme[hi_fg]="#{BRIGHT}"
theme[selected_bg]="#{DEEP}"
theme[selected_fg]="#{HEAD}"
theme[inactive_fg]="#{DIM}"
theme[graph_text]="#{MID}"
theme[proc_misc]="#{BRIGHT}"
theme[cpu_box]="#{DIM}"
theme[mem_box]="#{DIM}"
theme[net_box]="#{DIM}"
theme[proc_box]="#{DIM}"
theme[div_line]="#{DEEP}"
theme[temp_start]="#{MID}"
theme[temp_mid]="#{BRIGHT}"
theme[temp_end]="#{ALERT}"
theme[cpu_start]="#{MID}"
theme[cpu_mid]="#{BRIGHT}"
theme[cpu_end]="#{ALERT}"
theme[free_start]="#{DEEP}"
theme[free_end]="#{MAIN}"
theme[cached_start]="#{DIM}"
theme[cached_end]="#{BRIGHT}"
theme[available_start]="#{DIM}"
theme[available_end]="#{MAIN}"
theme[used_start]="#{MAIN}"
theme[used_end]="#{ALERT}"
theme[download_start]="#{DIM}"
theme[download_end]="#{BRIGHT}"
theme[upload_start]="#{DIM}"
theme[upload_end]="#{ALERT}"
theme[process_start]="#{MID}"
theme[process_end]="#{HEAD}"
"""

ROLES = ["HEAD", "BRIGHT", "MAIN", "MID", "DIM", "DEEP", "ALERT", "WARN"]


def btop_config(palette, tmp):
    """A throwaway XDG config so btop draws in the same palette as everything else."""
    hexes = PALETTES.get(palette)
    if not hexes:
        return None
    colors = dict(zip(ROLES, hexes.split()))
    d = os.path.join(tmp, "btop")
    os.makedirs(os.path.join(d, "themes"), exist_ok=True)
    body = BTOP_THEME
    for k, v in colors.items():
        body = body.replace("{%s}" % k, v)
    with open(os.path.join(d, "themes", "h4x0r.theme"), "w") as fh:
        fh.write(body)
    with open(os.path.join(d, "btop.conf"), "w") as fh:
        fh.write('color_theme = "h4x0r"\ntheme_background = True\nvim_keys = False\n'
                 'update_ms = 1000\nproc_gradient = True\n')
    return tmp


def build(layout, palette, cols, rows, settle, music, tmp):
    env = dict(os.environ, H4X0R_TMUX_COLS=str(cols), H4X0R_TMUX_ROWS=str(rows),
               H4X0R_TMUX_SESSION=SESSION)
    xdg = btop_config(palette, tmp)
    if xdg:
        env["H4X0R_EXTRA_ENV"] = "XDG_CONFIG_HOME=%s" % xdg
    cmd = [os.path.expanduser("~/.local/bin/h4x0r"), "--mux", "tmux",
           "--layout", layout, "--palette", palette,
           "--no-focus", "--rebuild"]
    if not music:
        cmd.append("--no-music")
    subprocess.run(cmd, env=env, capture_output=True, text=True)
    time.sleep(settle)


def panes():
    out = sh("tmux", "list-panes", "-t", SESSION, "-F",
             "#{pane_id}\t#{pane_left}\t#{pane_top}\t#{pane_width}\t#{pane_height}\t#{pane_title}")
    for line in out.strip().splitlines():
        pid, left, top, w, h, title = line.split("\t")
        yield pid, int(left), int(top), int(w), int(h), title


IPV4 = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")


USER = os.environ.get("USER") or "user"


def scrub(text):
    """Mask addresses and the local username out of a screenshot.

    Replacements are the same length as what they replace, so the row stays
    aligned with the cell grid it came from.
    """
    text = IPV4.sub(lambda m: ".".join("x" * len(p) for p in m.group(0).split(".")), text)
    text = text.replace(USER, "x" * len(USER))
    # btop and ps truncate long names ("johnsideserf" -> "john+"); mask those too
    for n in range(len(USER) - 1, 3, -1):
        text = text.replace(USER[:n] + "+", "x" * n + "+")
    return text


def redact_grid(grid):
    for row in grid:
        before = "".join(c for c, _, _ in row)
        after = scrub(before)
        if after == before:
            continue
        if len(after) != len(before):        # should not happen; skip rather than misalign
            continue
        for x, ch in enumerate(after):
            if ch != row[x][0]:
                row[x] = (ch, row[x][1], row[x][2])


def compose(cols, rows, border_rgb, title_rgb):
    grid = [[(" ", DEFAULT_FG, DEFAULT_BG) for _ in range(cols)] for _ in range(rows)]

    def put(x, y, ch, fg, bg=DEFAULT_BG):
        if 0 <= x < cols and 0 <= y < rows:
            grid[y][x] = (ch, fg, bg)

    for pid, left, top, w, h, title in panes():
        text = subprocess.run(["tmux", "capture-pane", "-p", "-e", "-t", pid],
                              capture_output=True, text=True).stdout.splitlines()
        for y in range(h):
            line = text[y] if y < len(text) else ""
            for x, cell in enumerate(parse_line(line, w)):
                put(left + x, top + y, *cell)
        # borders, drawn the way tmux presents them with pane-border-status top
        if top > 0:
            for x in range(left - 1, left + w + 1):
                put(x, top - 1, "─", border_rgb)
            label = " %s " % title.strip()
            start = left + max(0, (w - len(label)) // 2)
            for i, ch in enumerate(label):
                put(start + i, top - 1, ch, title_rgb)
        if left > 0:
            for y in range(top, top + h):
                put(left - 1, y, "│", border_rgb)
    return grid


def render(grid, cols, rows, size, out, width):
    fonts = FontSet(size)
    probe = Image.new("RGB", (10, 10))
    d0 = ImageDraw.Draw(probe)
    cw = max(1, round(d0.textlength("M", font=fonts.fonts[0])))
    asc, desc = fonts.fonts[0].getmetrics()
    ch = asc + desc
    img = Image.new("RGB", (cols * cw, rows * ch), DEFAULT_BG)
    d = ImageDraw.Draw(img)
    for y, row in enumerate(grid):
        for x, (c, fg, bg) in enumerate(row):
            if bg != DEFAULT_BG:
                d.rectangle([x * cw, y * ch, (x + 1) * cw - 1, (y + 1) * ch - 1], fill=bg)
            if c and c != " ":
                d.text((x * cw, y * ch), c, font=fonts.pick(c), fill=fg)
    if width and img.width != width:
        img = img.resize((width, round(img.height * width / img.width)), Image.LANCZOS)
    img.save(out)
    return img.size


def border_colors(palette):
    hexes = PALETTES.get(palette)
    if not hexes:
        return (0, 70, 40), (0, 190, 110)
    c = dict(zip(ROLES, hexes.split()))
    rgb = lambda h: tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    return rgb(c["DEEP"]), rgb(c["MAIN"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--layout", default="grid")
    ap.add_argument("--palette", default="phosphor")
    ap.add_argument("--cols", type=int, default=300)
    ap.add_argument("--rows", type=int, default=89)
    ap.add_argument("--settle", type=float, default=8)
    ap.add_argument("--size", type=int, default=16, help="font pixel size before downscale")
    ap.add_argument("--width", type=int, default=1920, help="final image width (0 = native)")
    ap.add_argument("--music", action="store_true")
    ap.add_argument("--out", default="preview.png")
    ap.add_argument("--no-redact", action="store_true",
                    help="leave IPv4 addresses visible (they are masked by default)")
    a = ap.parse_args()

    tmp = tempfile.mkdtemp(prefix="h4x0r-shot-")
    build(a.layout, a.palette, a.cols, a.rows, a.settle, a.music, tmp)
    try:
        border, title = border_colors(a.palette)
        grid = compose(a.cols, a.rows, border, title)
        if not a.no_redact:
            redact_grid(grid)
            leaked = [y for y, row in enumerate(grid)
                      if USER in "".join(c for c, _, _ in row)
                      or IPV4.search("".join(c for c, _, _ in row))]
            if leaked:
                print("WARNING: rows still showing user/IP: %s" % leaked[:8], file=sys.stderr)
        size = render(grid, a.cols, a.rows, a.size, a.out, a.width)
    finally:
        subprocess.run(["tmux", "kill-session", "-t", SESSION], capture_output=True)
        shutil.rmtree(tmp, ignore_errors=True)
    print("%s  %dx%d" % (a.out, *size))


main()

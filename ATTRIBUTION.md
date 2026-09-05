# Attribution

Everything in this repository is original work by the author under the
[MIT licence](LICENSE), with two exceptions worth naming.

## icon.png

The skull is a rasterised font glyph: `U+F068C`, rendered from a
[Nerd Font](https://github.com/ryanoasis/nerd-fonts). Nerd Fonts packages icon
sets from several projects; this codepoint sits in its Material Design Icons
range, and those icons come from
[Pictogrammers' Material Design Icons](https://pictogrammers.com/library/mdi/),
distributed under the Apache Licence 2.0. The glyph was rendered to a bitmap and
composited onto a background drawn by `scripts/shot.py`'s sibling code; no icon
artwork was modified.

The pane programs and the popout render Nerd Font glyphs at runtime, the same
way any terminal application does. Only `icon.png` redistributes one as an
image.

## The screenshots

`preview.webp` and everything in `docs/` are renders of the author's own
machine, produced by `scripts/shot.py`. They necessarily show the interfaces of
the programs h4x0r puts in panes — `btop`, `journalctl`, `ss`, `watch` — as any
screenshot of a terminal would.

Addresses, usernames, process ids and the socket table's process column are
masked in those images; see the Screenshots section of the [README](README.md)
for exactly what is and is not scrubbed.

## Everything else

The pane programs in `bin/h4x0r` (matrix rain, radar sweep, banner, hex dump,
intrusion log, socket table), the widget in `Panel.qml`, the renderer in
`scripts/shot.py`, and the CLI itself are original.

The invented hostnames in the intrusion log — `gibson.ellingson`,
`cyberdyne-t800`, `wopr.norad` and the rest — are nods to the films the whole
thing is imitating. They are strings in a list, not references to anything real.

# Changelog

Notable changes, newest first. The marketplace publishes a specific commit, so
each release here corresponds to a tag you can point a listing update at.

## [1.0.0]

First release: a bar widget and popout that build a twelve-pane hacker-movie
workspace in herdr, tmux or zellij and tear it down again.

### Added
- zellij backend. zellij has no ratio-taking split and will not start panes in
  a detached session, so the arrangement is written out as a KDL layout and the
  session starts attached in a terminal. `--no-focus` does not apply there, and
  `auto` picks `cinema` rather than `grid` because pane sizes are fixed before
  the window exists to be measured.
- `--print-palette`, which prints the resolved `H4X0R_*` colours and exits.
  `scripts/shot.py` uses it instead of keeping its own copy of the table.
- `--extract`, which writes the pane programs out without building anything.
- Four layouts: `auto` (fits the window), `grid` (12 panes), `cinema` (5),
  `minimal` (3).
- Seven palettes: the current Omarchy theme by default, plus phosphor, amber,
  ice, crimson, synthwave and mono, applied to the pane programs as well as
  the popout.
- `note` output is suppressed when the output is meant to be parsed
  (`--print-palette`, `--status --json`).
- Staged reveal: panes fill in one at a time, each typing a bring-up line.
- `scripts/shot.py`, which renders a preview without opening a window by
  reading the panes back as ANSI text and drawing the image itself.

### Fixed
- `btop` gives way to `top` in panes too narrow for it, instead of drawing a
  "terminal size too small" box.
- tmux pane titles are re-applied after the programs start, because the shell
  prompt's title escape overwrites anything set beforehand.
- tmux sessions carry an ownership marker, so `--close` cannot kill a session
  of the same name that h4x0r did not create.

### Security
- Screenshots mask addresses, usernames, pids and the socket table's process
  column by default. The generated panes are left alone so the fiction still
  reads as fiction.

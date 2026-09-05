#!/usr/bin/env bash
# Put h4x0r on PATH and lay down the pane programs.
#
#   ./install.sh              link the CLI and extract the pane scripts
#   ./install.sh --no-menu    skip the Omarchy menu rows
#   ./install.sh --keybind    also bind SUPER + SHIFT + H
#
# Installing the plugin itself is `omarchy plugin add`; this script only sets up
# the command line side, which the bar widget drives.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CLI="$HERE/bin/h4x0r"

for dep in python3 bash; do
  command -v "$dep" >/dev/null || { echo "install.sh: missing dependency: $dep" >&2; exit 1; }
done
command -v herdr >/dev/null || command -v tmux >/dev/null || {
  echo "install.sh: needs herdr or tmux to have somewhere to build the panes" >&2; exit 1; }

menu=1; keybind=0
for a in "$@"; do
  case "$a" in
    --no-menu) menu=0 ;;
    --keybind) keybind=1 ;;
    *) echo "install.sh: unknown option: $a" >&2; exit 1 ;;
  esac
done

mkdir -p "$HOME/.local/bin"
ln -sf "$CLI" "$HOME/.local/bin/h4x0r"
echo "==> linked ~/.local/bin/h4x0r"

"$CLI" --extract

MENU="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
if [ "$menu" = 1 ] && [ -f "$MENU" ] && ! grep -q '"trigger.h4x0r"' "$MENU"; then
  python3 - "$MENU" "$HOME/.local/bin/h4x0r" <<'PYEOF'
import sys, pathlib
menu, cli = pathlib.Path(sys.argv[1]), sys.argv[2]
s = menu.read_text().rstrip()
head, sep, tail = s.rpartition("}")
if sep != "}" or tail.strip():
    sys.exit(0)
head = head.rstrip()
if not head.endswith(",") and head.rstrip().endswith(("}", '"')):
    head += ","
rows = (
    '\n\n  // h4x0r - 90s hacker-movie workspace\n'
    '  "trigger.h4x0r": {"icon":"","label":"Hack the planet",'
    '"description":"90s hacker-movie workspace in herdr or tmux","action":"%s"},\n'
    '  "trigger.h4x0r-stop": {"icon":"","label":"Stop hacking",'
    '"description":"Close the hacker workspace","action":"%s --close",'
    '"when":"%s --list"}\n' % (cli, cli, cli)
)
menu.write_text(head + rows + "}\n")
PYEOF
  echo "==> added Omarchy menu rows (Trigger -> Hack the planet)"
fi

BINDINGS="$HOME/.config/hypr/bindings.lua"
if [ "$keybind" = 1 ] && [ -f "$BINDINGS" ] && ! grep -q 'h4x0r' "$BINDINGS"; then
  # never shadow a shortcut the user already has
  taken=$(omarchy menu keybindings --print 2>/dev/null | grep -iE '^SUPER SHIFT \+ H\b' || true)
  if [ -n "$taken" ]; then
    echo "==> SUPER + SHIFT + H is already bound to:${taken#*→}"
    echo "    skipping the keybind; bind h4x0r to something else in $BINDINGS"
    keybind=0
  fi
fi

if [ "$keybind" = 1 ] && [ -f "$BINDINGS" ] && ! grep -q 'h4x0r' "$BINDINGS"; then
  {
    echo
    echo "-- h4x0r: 90s hacker-movie workspace"
    echo "o.bind(\"SUPER + SHIFT + H\", \"Hack the planet\", \"$HOME/.local/bin/h4x0r\")"
  } >> "$BINDINGS"
  hyprctl reload >/dev/null 2>&1 || true
  echo "==> bound SUPER + SHIFT + H"
fi

echo
"$CLI" --status || true
echo
echo "Done. Run 'h4x0r' or add the bar widget:"
echo "  omarchy bar put io.github.johnsideserf.h4x0r --section right"

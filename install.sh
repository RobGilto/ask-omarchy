#!/usr/bin/env bash

# Puts the CLI this widget drives on your PATH. Omarchy's plugin installer
# never runs anything from a plugin — by design — so this is a manual step.
#
#   ./install.sh            symlink bin/omarchy-ask into ~/.local/bin
#   ./install.sh --copy     copy it instead, if you would rather not link

set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bin/omarchy-ask"
dest="${XDG_BIN_HOME:-$HOME/.local/bin}/omarchy-ask"

mkdir -p "$(dirname "$dest")"

if [ "${1:-}" = "--copy" ]; then
  cp "$src" "$dest"
else
  ln -sfn "$src" "$dest"
fi
chmod +x "$dest"

echo "installed: $dest"
command -v claude >/dev/null || echo "warning: the 'claude' CLI is not on PATH — the widget needs it to answer anything"
echo "next: omarchy-ask docs --refresh   (optional, caches the manual for concept questions)"

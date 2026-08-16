#!/usr/bin/env bash

set -euo pipefail

plugin_id="${USER:-$(id -un)}.lock"
plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"

[[ -d $plugin_dir ]] || {
  printf 'The cloned lock plugin is not installed: %s\n' "$plugin_dir" >&2
  exit 1
}

omarchy plugin remove "$plugin_id" --yes
omarchy restart shell

printf "Restored Omarchy's built-in lock plugin and original DPMS behavior.\n"

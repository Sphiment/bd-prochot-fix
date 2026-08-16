#!/usr/bin/env bash

set -euo pipefail

for command in omarchy brightnessctl flock hyprctl jq rg; do
  command -v "$command" >/dev/null || {
    printf 'Required command is missing: %s\n' "$command" >&2
    exit 1
  }
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_id="${USER:-$(id -un)}.lock"
plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"
service="$plugin_dir/Service.qml"
manifest="$plugin_dir/manifest.json"
backup="$plugin_dir/Service.qml.before-hybrid-display-power"
helper="$plugin_dir/hybrid-display-power"

if [[ ! -d $plugin_dir ]]; then
  omarchy plugin clone omarchy.lock
fi

[[ -f $service && -f $manifest ]] || {
  printf 'The cloned lock plugin is incomplete: %s\n' "$plugin_dir" >&2
  exit 1
}

jq -e '.omarchy.clonedFrom == "omarchy.lock"' "$manifest" >/dev/null || {
  printf '%s is not a clone of omarchy.lock; refusing to overwrite it.\n' "$plugin_id" >&2
  exit 1
}

if ! rg -q 'hybridDisplayPower' "$service"; then
  rg -q 'readonly property string currentBackgroundLink:' "$service"
  rg -Fq 'command: ["bash", "-c", "omarchy-system-wake"]' "$service"
  rg -Fq 'command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]' "$service"

  cp -- "$service" "$backup"
  sed -i \
    '/readonly property string currentBackgroundLink:/a\  readonly property string hybridDisplayPower: home + "/.config/omarchy/plugins/" + userName + ".lock/hybrid-display-power"' \
    "$service"
  sed -i \
    's|command: \["bash", "-c", "omarchy-system-wake"\]|command: [root.hybridDisplayPower, "wake"]|' \
    "$service"
  sed -i \
    's|command: \["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"\]|command: [root.hybridDisplayPower, "blank"]|' \
    "$service"
fi

install -Dm0755 "$script_dir/hybrid-display-power" "$helper"
omarchy-shell shell rescanPlugins >/dev/null
omarchy restart shell

printf 'Installed hybrid-display sleep workaround in %s\n' "$plugin_dir"
printf 'The Intel panel now blanks via backlight while external outputs use DPMS.\n'

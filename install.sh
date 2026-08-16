#!/usr/bin/env bash

set -euo pipefail

if (( EUID != 0 )); then
  printf 'Run this installer as root: sudo ./install.sh\n' >&2
  exit 1
fi

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if ! grep -q 'vendor_id[[:space:]]*: GenuineIntel' /proc/cpuinfo; then
  printf 'This utility supports Intel CPUs only.\n' >&2
  exit 1
fi

command -v cc > /dev/null || {
  printf 'A C compiler is required (for example, the base-devel package).\n' >&2
  exit 1
}

modprobe msr
make -C "$source_dir"

install -Dm0755 "$source_dir/build/bd-prochot-fix" /usr/local/sbin/bd-prochot-fix
install -Dm0644 "$source_dir/systemd/bd-prochot-fix.service" \
  /etc/systemd/system/bd-prochot-fix.service
install -Dm0755 "$source_dir/systemd/bd-prochot-fix-sleep" \
  /usr/lib/systemd/system-sleep/bd-prochot-fix

systemctl daemon-reload
systemctl enable --now bd-prochot-fix.service

printf '\nInstalled successfully. Current status:\n'
/usr/local/sbin/bd-prochot-fix status
systemctl --no-pager --full status bd-prochot-fix.service

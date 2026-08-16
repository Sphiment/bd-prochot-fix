#!/usr/bin/env bash

set -euo pipefail

if (( EUID != 0 )); then
  printf 'Run this uninstaller as root: sudo ./uninstall.sh\n' >&2
  exit 1
fi

systemctl disable --now bd-prochot-fix.service 2>/dev/null || true

if [[ -x /usr/local/sbin/bd-prochot-fix ]]; then
  /usr/local/sbin/bd-prochot-fix enable || true
fi

rm -f -- \
  /usr/lib/systemd/system-sleep/bd-prochot-fix \
  /etc/systemd/system/bd-prochot-fix.service \
  /usr/local/sbin/bd-prochot-fix

systemctl daemon-reload
printf 'Removed bd-prochot-fix and restored BD PROCHOT.\n'

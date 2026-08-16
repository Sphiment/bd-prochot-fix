# bd-prochot-fix

A small, reversible Linux workaround for Intel CPUs stuck at their minimum
frequency because of a false or latched **BD PROCHOT** signal.

This project clears only bit 0 (bidirectional PROCHOT enable) in
`MSR_POWER_CTL` (`0x1fc`). It includes a status tool, a systemd boot service,
and a post-resume hook for firmware that restores the bit after suspend.

## Important safety warning

BD PROCHOT lets components outside the CPU—such as the voltage regulator,
charger circuitry, battery, or GPU—request CPU throttling. Disabling it can
hide a real electrical or thermal problem.

Use this workaround only after checking temperatures, cooling, the battery,
and the correct manufacturer-rated charger. The CPU's internal thermal
protection remains enabled, but external components may not have equivalent
protection once BD PROCHOT is ignored. You assume the risk of using this tool.

## Symptoms this may fix

- The CPU remains at its minimum multiplier under sustained load.
- Temperatures are well below the thermal limit.
- CPU temperature sensors remain well below the thermal limit while the clamp
  is active.
- Performance profiles, governors, turbo settings, and charger replacement do
  not resolve the limit.
- `status` reports `thermal=inactive` while
  `prochot_or_forcepr=active`.

Do not use this tool for ordinary temperature-based throttling.

## Requirements

- Linux on an Intel x86-64 CPU
- Root access
- The Linux `msr` module
- A C compiler, GNU Make, and systemd for persistent installation

On Arch Linux, the compiler and Make are provided by `base-devel`.

## Diagnose first

```bash
make
sudo modprobe msr
sudo ./build/bd-prochot-fix status
```

Useful fields:

- `bd_prochot=enabled`: the CPU accepts external PROCHOT assertions.
- `thermal=active`: the CPU itself is at its thermal limit. Do **not** bypass
  this; fix cooling instead.
- `prochot_or_forcepr=active` with `thermal=inactive`: consistent with the
  false external clamp this project targets.

The PROCHOT status or its Linux event counter may remain active because the
external signal is still physically asserted. Disabling BD PROCHOT stops the
CPU from obeying that external signal; it does not necessarily clear the
signal itself.

## Temporary, reboot-reversible test

Clear the BD PROCHOT enable bit:

```bash
sudo ./build/bd-prochot-fix disable
./verify.sh --load
```

Watch temperatures throughout the test. Restore the original behavior at any
time:

```bash
sudo ./build/bd-prochot-fix enable
```

A reboot also normally restores the firmware default unless the persistent
service has been installed.

## Persistent installation

Only install the persistent workaround after the temporary test recovers CPU
performance without unsafe temperatures:

```bash
sudo ./install.sh
```

The installer adds:

- `/usr/local/sbin/bd-prochot-fix`
- `/etc/systemd/system/bd-prochot-fix.service`
- `/usr/lib/systemd/system-sleep/bd-prochot-fix`

The service disables false BD PROCHOT at boot. The sleep hook reapplies the
workaround after resume.

Check it with:

```bash
systemctl status bd-prochot-fix.service
sudo /usr/local/sbin/bd-prochot-fix status
```

## Uninstall and restore

```bash
sudo ./uninstall.sh
```

The uninstaller stops and disables the service, restores BD PROCHOT, removes
the installed files, and reloads systemd.

## Verified hardware

The initial implementation was verified on an HP Pavilion Power 15-cb0xx
with an Intel Core i7-7700HQ. Its false 800 MHz clamp cleared immediately;
the CPU resumed normal turbo behavior while remaining below its thermal limit.

Other Intel models may use different firmware behavior. Inspect the status and
test temporarily before installing.

The same machine also needed an NVIDIA-primary Hyprland configuration to make
an external 144 Hz monitor render smoothly. The complete machine-specific
diagnosis, recovery procedure, verification commands, and rollback steps are
documented in [HP Pavilion Power 15 recovery notes](docs/HP-PAVILION-POWER-15-RECOVERY.md).

## License

[MIT](LICENSE)

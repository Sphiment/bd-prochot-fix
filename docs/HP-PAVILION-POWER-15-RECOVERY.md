# HP Pavilion Power 15 Linux recovery notes

This is the known-good recovery guide for the machine on which this project
was created. It records both performance problems found during diagnosis:

1. A false BD PROCHOT signal clamped the CPU to approximately 800 MHz.
2. Hyprland used the Intel GPU as its primary renderer, making the external
   NVIDIA-connected 144 Hz monitor feel choppy because frames crossed GPUs.

The procedures below were verified on 2026-08-16.

## Tested machine

- Laptop: HP Pavilion Power 15-cb0xx
- CPU: Intel Core i7-7700HQ
- Integrated GPU: Intel HD Graphics 630 at PCI `0000:00:02.0`
- Discrete GPU: NVIDIA GeForce GTX 1050 Mobile at PCI `0000:01:00.0`
- Desktop: Omarchy 4.0.0 with Hyprland 0.56.2 and UWSM
- Internal panel: `eDP-1`, physically connected to the Intel GPU
- External display: `HDMI-A-1`, physically connected to the NVIDIA GPU
- External mode: 2560x1440 at 144 Hz

## Known-good final state

- BD PROCHOT is disabled by a boot service and reapplied after suspend.
- CPU performance is no longer stuck at 800 MHz.
- An all-core load reached approximately 3.4 GHz. The i7-7700HQ's higher
  single-core turbo ceiling is not expected on every core simultaneously.
- Hyprland uses NVIDIA as the primary DRM renderer while retaining Intel for
  the internal panel.
- Both displays work, and the external 144 Hz monitor is smooth.
- Omarchy's lock screen uses the hybrid-display sleep workaround described
  below, preventing the Intel panel from wedging after display sleep.

## Problem 1: false CPU throttling

### Symptoms and conclusion

The CPU remained close to its 800 MHz minimum even under load. Changing
chargers, governors, performance profiles, and ordinary power settings did not
fix it. Temperatures were below the CPU thermal limit. MSR inspection showed a
PROCHOT condition without the CPU's own thermal status being active, which was
consistent with a false or latched external BD PROCHOT request.

BD PROCHOT is a real safety feature: the charger, battery, voltage regulator,
GPU, or another component can use it to request CPU throttling. Only use this
workaround when cooling, temperatures, battery condition, and the correct
charger have been checked. The repository's main README contains the full
safety warning.

### Restore the CPU fix from this repository

```bash
git clone https://github.com/Sphiment/bd-prochot-fix.git
cd bd-prochot-fix
make
sudo modprobe msr
sudo ./build/bd-prochot-fix status
```

For a temporary, reboot-reversible test:

```bash
sudo ./build/bd-prochot-fix disable
./verify.sh --load
```

Watch temperatures while the load test runs. If performance recovers without
unsafe temperatures, install the persistent boot and resume hooks:

```bash
sudo ./install.sh
```

Verify the installed repository version:

```bash
systemctl status bd-prochot-fix.service
sudo /usr/local/sbin/bd-prochot-fix status
```

Restore the original safety behavior and remove the persistent workaround:

```bash
sudo ./uninstall.sh
```

### Original installation name on this machine

The first working installation predates the standardized repository names. It
may appear as `cpu-bd-prochot.service` with
`/usr/local/sbin/cpu-bd-prochot`. The repository installer instead uses
`bd-prochot-fix.service` and `/usr/local/sbin/bd-prochot-fix`. On a fresh
recovery, use the repository's installer and verification commands above.

## Problem 2: choppy external monitor on hybrid graphics

### What was actually happening

The external HDMI port is wired directly to the NVIDIA GPU. However, before
the fix, Hyprland selected Intel as its primary renderer. Applications and the
compositor generally rendered on Intel, then copied external-monitor frames to
NVIDIA for HDMI scanout.

The signal was not being sent from NVIDIA back through Intel. The expensive
part was the opposite direction: Intel rendering to NVIDIA scanout.

Making NVIDIA the primary renderer removed that cross-GPU path for the
external monitor. The internal panel still needs Intel because it is
physically wired to Intel. With both panels enabled, no software setting can
make both physical outputs NVIDIA-only unless the laptop has a hardware MUX.

### Confirm the DRM card mapping first

The working mapping on this installation is:

```text
/dev/dri/card1 = NVIDIA GTX 1050, PCI 0000:01:00.0
/dev/dri/card2 = Intel HD 630, PCI 0000:00:02.0
```

Card numbers can change after a driver or system update. Check them before
recreating the configuration:

```bash
udevadm info -q property -n /dev/dri/card1 | grep ID_PATH
udevadm info -q property -n /dev/dri/card2 | grep ID_PATH
```

The expected output contains:

```text
card1: ID_PATH=pci-0000:01:00.0
card2: ID_PATH=pci-0000:00:02.0
```

If the cards are reversed, reverse them in `AQ_DRM_DEVICES` so NVIDIA remains
first and Intel remains second.

### Recreate the working NVIDIA-primary setup

Create the UWSM environment directory and open the Hyprland environment file:

```bash
mkdir -p ~/.config/uwsm
nano ~/.config/uwsm/env-hyprland
```

Add this exact line for the verified card mapping:

```bash
export AQ_DRM_DEVICES="/dev/dri/card1:/dev/dri/card2"
```

In Nano, press `Ctrl+O`, `Enter`, and then `Ctrl+X`. Save all open work and log
out so Hyprland can recreate its renderer:

```bash
omarchy logout
```

The Omarchy power menu is another option: press `Super+Ctrl+P` and choose
**Logout**. Sign back in normally at the login screen. A reboot is not required.

### Verify that NVIDIA is primary

After signing back in, run:

```bash
rg -i 'becomes primary drm|renderer' \
  "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log"
```

The important result is:

```text
gpu /dev/dri/card1 becomes primary drm
```

For this machine, `card1` must map to PCI `0000:01:00.0`, the NVIDIA GTX 1050.

### Roll back the GPU test

From a working desktop:

```bash
mv ~/.config/uwsm/env-hyprland ~/.config/uwsm/env-hyprland.disabled
omarchy logout
```

If the graphical session cannot start, press `Ctrl+Alt+F3`, sign in on the
text console, then run:

```bash
mv ~/.config/uwsm/env-hyprland ~/.config/uwsm/env-hyprland.disabled
reboot
```

This restores Hyprland's automatic GPU selection.

### Optional true NVIDIA-only mode

True NVIDIA-only rendering is possible only while the Intel-connected internal
panel is disabled. In that arrangement, disable `eDP-1` and use:

```bash
export AQ_DRM_DEVICES="/dev/dri/card1"
```

This was not necessary for the successful dual-monitor setup. The known-good
configuration keeps both cards listed, with NVIDIA first.

### Permanent lock-screen sleep workaround

With NVIDIA as Hyprland's primary renderer, Omarchy's normal lock behavior
turned every output off with DPMS. Waking both GPUs could leave `eDP-1` black
even though Hyprland reported it enabled, DPMS-on, and at full brightness. The
log contained errors such as:

```text
Cannot commit when a page-flip is awaiting
EGL_BAD_MATCH: createImageFromDmaBufs failed
```

Logging out and back in recovered the panel. Cycling DPMS or forcing a renderer
reload did not reliably recover an already-wedged panel.

The verified workaround keeps the Intel-connected `eDP-1` logically enabled
while the machine is locked. It saves the panel's brightness and sets its
backlight to zero. External outputs are put into DPMS sleep individually. On
activity, it wakes the external outputs and restores the exact saved internal
brightness. This prevents Aquamarine from tearing down the Intel secondary
renderer while still making both screens dark.

The strategy passed three consecutive blank/wake cycles on the tested machine
without deinitializing the Intel renderer or producing a stuck atomic commit.

Install it from this repository while logged into Omarchy:

```bash
./omarchy/install-hybrid-display-power.sh
```

The installer uses Omarchy's supported plugin clone mechanism. It creates a
user-owned clone of `omarchy.lock`, stores it under
`~/.config/omarchy/plugins/$USER.lock`, installs the display helper there, and
switches the lock plugin's blank/wake commands to that helper. It does not edit
anything under `/usr/share/omarchy`. It restarts the Omarchy shell at the end so
the replaced built-in lock service cannot remain active in the current session.

Uninstall the workaround, remove the cloned plugin, and restore Omarchy's
built-in lock plugin with:

```bash
./omarchy/uninstall-hybrid-display-power.sh
```

After installation, test the full integration manually:

1. Run `omarchy system lock`.
2. Wait at least five seconds for both displays to blank.
3. Move the mouse or press a key.
4. Confirm both displays show the lock screen.
5. Unlock and confirm the original laptop brightness was restored.

## Package power and GPU limits

The Intel CPU cores, Intel GPU, ring/uncore, and other domains share the Intel
package power budget. The limits observed on this machine were:

- Long-term package limit (PL1): 45 W
- Short-term package limit (PL2): 56.25 W
- Intel GPU configured range: 350-1100 MHz

Heavy CPU and Intel GPU activity can therefore compete within the Intel
package budget. The NVIDIA GPU is not part of Intel RAPL package power, though
the CPU and NVIDIA GPU still share the laptop's charger capacity and cooling.

In this case, the dramatic external-monitor smoothness improvement came from
making NVIDIA the primary Hyprland renderer, which confirmed that the display
render/copy path—not an Intel package-power limit—was the main cause of the
choppiness.

NVIDIA-primary mode normally uses more power and produces more heat than
Intel-primary mode. Keep an eye on CPU and GPU temperatures during sustained
combined loads.

## Quick recovery checklist

If the original problems return after an update or reinstall:

1. Check whether the CPU is stuck around 800 MHz under load.
2. Check the BD PROCHOT tool and service status.
3. Reinstall this repository's persistent fix if it is missing.
4. Confirm which DRM card maps to NVIDIA and Intel.
5. Confirm `~/.config/uwsm/env-hyprland` lists NVIDIA first.
6. Log out and back in; changing the renderer is not a live-reload operation.
7. Confirm the Hyprland log says the NVIDIA card became primary DRM.
8. Test temperatures and external-monitor smoothness again.

Hyprland's upstream explanation of the renderer ordering is available in the
[official Multi-GPU documentation](https://wiki.hypr.land/Configuring/Advanced-and-Cool/Multi-GPU/).

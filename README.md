# Intel ME/CSME/GSC Disabler — 

> Soft-disables the Intel Management Engine at the OS level on Debian/Ubuntu systems. After running, the ME will no longer appear in `lspci` and its kernel modules will be permanently blocked.

---

## What This Does

Intel's Management Engine (ME/CSME/GSC) is a coprocessor embedded in Intel chipsets that runs independently of your OS. This script disables it **at the OS/software level** by:

- Removing the ME PCI device from the kernel's device tree via udev
- Blacklisting all ME-related kernel modules
- Installing a `softdep` layer to prevent modules loading as dependencies
- Creating an early-boot systemd service to apply all of the above on every boot
- Rebuilding initramfs to make changes persistent

This is a **soft/OS-level disable** — it does not touch firmware or flash. The ME hardware still exists but cannot communicate with your OS and will not appear in `lspci`.

---

## Compatibility

Designed for **Intel platforms from 2011 to 2026**, covering the following generations:

| Generation | Example CPUs | ME Device IDs |
|---|---|---|
| Sandy Bridge (2011) | 2nd Gen Core | `0x1c3a` |
| Ivy Bridge (2012) | 3rd Gen Core | `0x1e3a` |
| Haswell (2013–2014) | 4th Gen Core | `0x8c3a`, `0x9c3a`, `0x9cba` |
| Skylake / Kaby Lake | 6th–8th Gen Core | `0x9d3a`, `0xa13a` |
| Whiskey / Comet Lake | 8th–10th Gen Core | `0x9de0`, `0xa360`, `0xa0e0` |
| Tiger Lake | 11th Gen Core | `0x43a8`, `0x4b28` |
| Alder Lake | 12th Gen Core | `0x464e`, `0x467e` |
| Raptor Lake | 13th–14th Gen Core | `0x51a8`, `0x51e8`, `0x7e28` |
| Meteor Lake | Core Ultra 100 | `0x7d3a`, `0x7d60`, `0x7e40` |
| Arrow Lake | Core Ultra 200 | `0xa84a`, `0xa84e`, `0xa860` |

Also catches any unknown/future ME variants via PCI class matching (`0x0c8080`, `0x078000`).

**OS:** Debian, Ubuntu, and derivatives. Tested on ThinkPads but works on any Intel system.

---

## Requirements

- Root access
- `systemd`-based init
- `update-initramfs` (standard on Debian/Ubuntu)

---

## Usage

```bash
# Clone or download the script
chmod +x intel-me-disable.SH
sudo ./intel-me-disable.SH
```

Then reboot when prompted (or manually):

```bash
sudo reboot
```

After reboot, verify ME is gone:

```bash
lspci | grep -i "mei\|management engine\|heci"
# Should return nothing
```

---

## What Gets Installed

| File | Purpose |
|---|---|
| `/etc/modprobe.d/disable-intel-me.conf` | Blacklists all ME modules + `softdep` prevention |
| `/etc/udev/rules.d/99-disable-intel-me.rules` | Removes ME PCI device on every boot |
| `/etc/systemd/system/disable-intel-me.service` | Early-boot service to enforce both of the above |

All pre-existing versions of these files are backed up to `/root/me_disable_backup_<timestamp>/` before modification.

---

## How It Works — Step by Step

**[1/7] Detection** — Scans `lspci` for any visible ME interface. Non-fatal if already gone.

**[2/7] Module discovery** — Finds all loaded and available ME-related `.ko` modules on your system, including `mei*`, `intel_vsec`, `intel_csme`, `intel_pmt`, `pmt_*`, `iTCO_*`, and more.

**[3/7] Dependency resolution** — Checks `modinfo` to pull in any modules that the ME stack depends on, so nothing can sneak back in via a dependency load.

**[4/7] Blacklist** — Writes `/etc/modprobe.d/disable-intel-me.conf` with:
- `blacklist` directives for all known ME modules
- `install $mod /bin/false` to hard-block any load attempt
- `softdep $mod pre: blacklist` to prevent loading as a dependency

**[5/7] Udev rule** — Matches ME devices by both specific device ID and PCI class. When the kernel adds the device at boot, udev immediately writes `1` to its `remove` sysfs node, evicting it from the device tree before any driver can bind.

**[6/7] Systemd service** — Runs at early boot (before `sysinit.target`) to reload udev rules and trigger PCI re-enumeration, then unloads any lingering ME modules.

**[7/7] Apply now** — Unloads currently-loaded ME modules, triggers udev, and rebuilds initramfs so the blacklist is baked into the next boot image.

---

## Reverting

To undo everything:

```bash
sudo rm /etc/modprobe.d/disable-intel-me.conf
sudo rm /etc/udev/rules.d/99-disable-intel-me.rules
sudo systemctl disable --now disable-intel-me.service
sudo rm /etc/systemd/system/disable-intel-me.service
sudo update-initramfs -u -k all
sudo reboot
```

Your original files (if any existed) are in `/root/me_disable_backup_<timestamp>/`.

---

## Caveats & Warnings

- This is an **OS-level soft disable only**. 
- Some features that depend on ME (Intel AMT, certain DRM workflows, some thermal management paths on laptops) will stop functioning.
- On a small number of systems, removing the ME PCI device can cause boot delays or benign kernel warnings. These are cosmetic.
- Run at your own risk. A backup of all modified files is always created before changes are applied.

---


---

## License

MIT

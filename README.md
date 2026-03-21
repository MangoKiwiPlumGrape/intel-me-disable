<div align="center">

# intel-me-disable.sh
### OS-level Intel ME/CSME/GSC soft-disable for Debian/Ubuntu

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/MangoKiwiPlumGrape/intel-me-disable)

[![Platforms](https://img.shields.io/badge/platforms-Sandy%20Bridge%20→%20Panther%20Lake-blue?style=flat-square&logo=intel)](https://github.com/MangoKiwiPlumGrape/intel-me-disable)
[![Device IDs](https://img.shields.io/badge/device%20IDs-61%20HECI%20IDs-brightgreen?style=flat-square)](https://github.com/MangoKiwiPlumGrape/intel-me-disable)
[![Years](https://img.shields.io/badge/coverage-2011–2026-informational?style=flat-square)](https://github.com/MangoKiwiPlumGrape/intel-me-disable)
[![OS](https://img.shields.io/badge/OS-Debian%20%2F%20Ubuntu-orange?style=flat-square&logo=ubuntu)](https://github.com/MangoKiwiPlumGrape/intel-me-disable)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)
[![Hardware Tested](https://img.shields.io/badge/hardware-tested%20on%20ThinkPad-success?style=flat-square)](https://github.com/MangoKiwiPlumGrape/intel-me-disable)

> Soft-disables the Intel Management Engine at the OS level on Debian/Ubuntu systems. For other OS see Universal_Distro.sh -
> After running, ME will no longer appear in `lspci` and its kernel modules are permanently blocked.


</div>

---

## What This Does

Intel's Management Engine (ME/CSME/GSC) is a coprocessor embedded in Intel chipsets that runs independently of your OS. This script disables it **at the OS/software level** by:

- Removing the ME PCI device from the kernel's device tree via udev
- Blacklisting all ME-related kernel modules
- Installing a `softdep` layer to prevent modules loading as dependencies
- Creating an early-boot systemd service to apply all of the above on every boot
- Rebuilding initramfs to make changes persistent

This is a **soft/OS-level disable** — it does not touch firmware or flash. The ME hardware still exists but cannot communicate with your OS and will not appear in `lspci`.

For a firmware-level disable (stronger, requires chip programmer or internal flash access), see the companion tools:
- [me_cleaner_thinkpad](https://github.com/MangoKiwiPlumGrape/me_cleaner_thinkpad) — HAP bit via external programmer
- [ifdtool_thinkpad](https://github.com/MangoKiwiPlumGrape/ifdtool_thinkpad) — Check dumps before and after specify with platform command.
---

## Compatibility

**61 HECI device IDs** covering Sandy Bridge (2011) through Panther Lake (2026), sourced from Intel PCH datasheets, Linux kernel `drivers/misc/mei/hw-me-regs.h`, and coreboot `pci_ids.h`.

| Generation | CPUs | ME Version | Key IDs |
|---|---|---|---|
| Sandy Bridge (2011) | 2nd Gen Core | ME 7 | `0x1c3a` |
| Ivy Bridge (2012) | 3rd Gen Core | ME 8 | `0x1e3a` |
| Haswell (2013) | 4th Gen Core | ME 9 | `0x8c3a`, `0x9c3a` |
| Broadwell (2014) | 5th Gen Core | ME 10 | `0x9cba` |
| Skylake / Kaby Lake | 6th–7th Gen Core | ME 11 | `0x9d3a`, `0xa13a`–`0xa13e` |
| Kaby Lake-H (Union Point) | 7th Gen H | ME 11 | `0xa2ba`–`0xa2be` |
| Cannon Point LP | 8th/9th Gen U | ME 12 | `0x9de0`, `0x9de8` |
| Cannon Point H | 8th/9th Gen H | ME 12 | `0xa360` |
| Ice Lake LP | 10th Gen U | ME 13 | `0x34e0`, `0x34e8` |
| Comet Lake U/H/S | 10th Gen | ME 14 | `0x02e0`–`0x02e8`, `0x06e0`–`0x06e8`, `0xa3b0`, `0xa3ba` |
| Tiger Lake LP/H | 11th Gen | ME 15 | `0xa0e0`, `0xa0e8`, `0x43e0`, `0x43e8` |
| Elkhart Lake | Atom x6000 | ME 15 | `0x4b28` |
| Alder Lake S/P/N | 12th Gen | ME 16 | `0x7ae8`, `0x7ae9`, `0x51e0`–`0x51a8`, `0x54e0`, `0x54e8` |
| Raptor Lake S | 13th Gen | ME 16.1 | `0x7a68`, `0x7a69` |
| Meteor Lake P | 14th Gen Core Ultra | ME 18 | `0x7e70`, `0x7e71`, `0x7e74`, `0x7e28` |
| Arrow Lake H/U | 15th Gen Core Ultra 200 | — | `0x7770`–`0x7775`, `0x7758`–`0x775a` |
| Arrow Lake S | 15th Gen Core Ultra 200S | — | `0xae70`, `0xae71` |
| Lunar Lake | 16th Gen Core Ultra | — | `0xa870`, `0xa84a`, `0xa84e`, `0xa860` |
| Panther Lake U | Series 3 | — | `0xe362`–`0xe364` |
| Panther Lake H | Series 3 | — | `0xe462`–`0xe464` |

Also catches any unknown/future ME variants via PCI class matching (`0x0c8080`, `0x078000`).

**OS:** Debian, Ubuntu, and derivatives. Tested on ThinkPads but works on any Intel system.

---

## ID Accuracy

Device IDs were cross-referenced against Intel PCH datasheets and corrected where upstream tools had errors:

| Platform | Removed / Corrected | Reason |
|---|---|---|
| ADL-S | `0x7aea` removed | IDE-R function, not HECI — wrong in many tools |
| RPL-S | `0x7a60` removed | Wrong SKU variant |
| MTL | `0x7e40` removed | CNVi WiFi controller, not MEI |
| MTL | `0x7d3a`, `0x7d60` removed | eSPI/LPC controller, not MEI |
| ADL-S | `0x7ae8`, `0x7ae9` added | Correct HECI1/2 — Doc 648364 |
| RPL-S | `0x7a68`, `0x7a69` added | Correct HECI1/2 — Doc 743835 |
| ARL H/U | `0x7771`, `0x7774`, `0x7775`, `0x7758`–`0x775a` added | Doc 842704 |
| PTL | `0xe362`–`0xe364`, `0xe462`–`0xe464` added | Doc 872188 |

---

## Requirements

- Root access
- `systemd`-based init
- `update-initramfs` (standard on Debian/Ubuntu)

---

## Usage

```bash
chmod +x intel-me-disable.sh
sudo ./intel-me-disable.sh
```

Then reboot:

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

All pre-existing files are backed up to `/root/me_disable_backup_<timestamp>/` before modification.

---

## Modules Blacklisted

`mei`, `mei_me`, `mei_gsc`, `mei_vsc`, `intel_vsec`, `intel_csme`, `intel_pmt`, `pmt_telemetry`, `iTCO_wdt`

Plus any additional ME-related modules dynamically discovered on your system at run time. Each module gets three layers of blocking: `blacklist`, `install $mod /bin/false`, and `softdep pre: blacklist`.

---

## How It Works — Step by Step

**[1/7] Detection** — Scans `lspci` for any visible ME interface. Non-fatal if already gone.

**[2/7] Module discovery** — Finds all loaded and available ME-related `.ko` modules, including `mei*`, `intel_vsec`, `intel_csme`, `intel_pmt`, `pmt_*`, `iTCO_*`, and more.

**[3/7] Dependency resolution** — Checks `modinfo` to pull in any modules the ME stack depends on, so nothing can sneak back via a dependency load.

**[4/7] Blacklist** — Writes `/etc/modprobe.d/disable-intel-me.conf` with three layers of blocking per module.

**[5/7] Udev rule** — Matches ME devices by both specific device ID (61 IDs) and PCI class. When the kernel adds the device at boot, udev immediately removes it before any driver can bind.

**[6/7] Systemd service** — Runs at early boot (before `sysinit.target`) to reload udev rules, trigger PCI re-enumeration, and unload any lingering ME modules.

**[7/7] Apply now** — Unloads currently-loaded ME modules, triggers udev, and rebuilds initramfs so the blacklist is baked into the next boot image.

---

## Reverting

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

## Caveats

- **OS-level soft disable only.** ME hardware still exists on the chip.
- Intel AMT, certain DRM workflows, and some thermal management paths will stop functioning.
- On a small number of systems, removing the ME PCI device can cause boot delays or benign kernel warnings. These are cosmetic.
- Always run with a known-good system state. A full backup of all modified files is created before any changes.

---

## Part of the Intel ME Disable Toolkit

This script is the OS-level component of a three-tool set:

| Tool | Method | Strength |
|---|---|---|
| **intel-me-disable.sh** (this) | OS-level udev + module blacklist | Soft — ME halted by OS, not firmware |
| [me_cleaner_thinkpad](https://github.com/MangoKiwiPlumGrape/me_cleaner_thinkpad) | HAP bit via external programmer | Strong — ME halted in firmware before OS boots |
| [ifdtool_thinkpad](https://github.com/MangoKiwiPlumGrape/ifdtool_thinkpad) | HAP bit via internal flash | Strong — same as above, no chip clip needed |

See [ME_Disable_Comparison.md](https://github.com/MangoKiwiPlumGrape/me_cleaner_thinkpad/blob/main/ME_Disable_Comparison.md) for a detailed breakdown of what each method actually prevents.

---

## License

MIT

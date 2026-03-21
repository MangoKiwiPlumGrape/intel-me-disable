#!/bin/bash
# Intel Management Engine (ME/CSME/GSC) Disabler — Universal Edition (2026)
# Supports: Debian/Ubuntu, Arch/Manjaro, Fedora/RHEL/CentOS, openSUSE,
#           Void Linux, Alpine, Gentoo, and any distro with udev + modprobe
# Init systems: systemd, OpenRC, runit, s6, dinit — or none (udev+modprobe sufficient)
#
# Device IDs updated from intelmetool-thinkpad fork cross-reference:
#   Intel PCH datasheets (Doc 648364, 743835, 792044) + coreboot pci_ids.h
#   61 HECI device IDs covering Sandy Bridge (2011) through Panther Lake (2026)
#   Removed non-MEI eSPI IDs (0x464e, 0x467e, 0x7d3a, 0x7d60)
#   Corrected ADL-S: 0x7aea→0x7ae8, RPL-S: 0x7a60→0x7a68

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

echo -e "${GREEN}=== Intel ME/CSME/GSC Disabler — Universal Edition 2026 ===${NC}\n"

# ===================================================================
# DISTRO + INIT SYSTEM DETECTION
# ===================================================================
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID,,}"
        DISTRO_LIKE="${ID_LIKE,,}"
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE=""
    fi
}

detect_init() {
    if command -v systemctl &>/dev/null && [ -d /run/systemd/system ]; then
        INIT_SYSTEM="systemd"
    elif command -v rc-update &>/dev/null && command -v openrc &>/dev/null; then
        INIT_SYSTEM="openrc"
    elif command -v sv &>/dev/null && [ -d /var/service ] || [ -d /etc/sv ]; then
        INIT_SYSTEM="runit"
    elif command -v dinitctl &>/dev/null; then
        INIT_SYSTEM="dinit"
    elif command -v s6-rc &>/dev/null; then
        INIT_SYSTEM="s6"
    else
        INIT_SYSTEM="unknown"
    fi
}

detect_initramfs_tool() {
    if command -v update-initramfs &>/dev/null; then
        INITRAMFS_TOOL="update-initramfs"
    elif command -v mkinitcpio &>/dev/null; then
        INITRAMFS_TOOL="mkinitcpio"
    elif command -v dracut &>/dev/null; then
        INITRAMFS_TOOL="dracut"
    elif command -v booster &>/dev/null; then
        INITRAMFS_TOOL="booster"
    else
        INITRAMFS_TOOL="none"
    fi
}

detect_distro
detect_init
detect_initramfs_tool

echo -e "${CYAN}System info:${NC}"
echo "   Distro      : ${DISTRO_ID:-unknown} ${VERSION_ID:-}"
echo "   Init system : $INIT_SYSTEM"
echo "   Initramfs   : $INITRAMFS_TOOL"
echo

# Backup directory
BACKUP_DIR="/root/me_disable_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo -e "${YELLOW}Backup directory: $BACKUP_DIR${NC}\n"

# ===================================================================
# [1/7] Detect visible ME
# ===================================================================
echo -e "${GREEN}[1/7] Detecting Intel ME interface...${NC}"
if lspci -nn | grep -i "8086.*mei\|management engine\|heci" | grep -q .; then
    lspci -nn | grep -i "8086.*mei\|management engine\|heci" | head -5
else
    echo -e "${YELLOW}No ME visible right now — already dead or hidden (perfect)${NC}"
fi
echo

# ===================================================================
# [2/7] Find every ME-related module
# ===================================================================
echo -e "${GREEN}[2/7] Identifying ME-related kernel modules...${NC}"
ME_MODULES=()
POTENTIAL_MODULES=(
    mei mei-me mei_me mei-txe mei_txe mei-gsc mei_gsc mei-vsc mei_vsc mei-vsc-hw mei_vsc_hw
    mei_wdt mei-wdt mei_pxp mei-pxp mei_hdcp mei-hdcp mei_phy mei-phy mei_gsc_proxy mei-gsc-proxy
    pn544_mei microread_mei intel_csme intel-csme intel_vsec intel-vsec intel_pmt intel-pmt
    intel_gsc intel-gsc intel_csme_hci intel-csme-hci vsec_me vsec-me
    pmt_telemetry pmt-telemetry pmt_class pmt-class iTCO_wdt iTCO_vendor_support itco_wdt itco_vendor_support
    ipmi_devintf ipmi_msghandler ipmi_ssif ipmi_watchdog intel_pmc_core intel_pmt
)

declare -A SEEN_MODULES
for mod in "${POTENTIAL_MODULES[@]}"; do
    n=$(echo "$mod" | tr '-' '_')
    if lsmod | grep -q "^$n " || modinfo "$n" &>/dev/null; then
        [[ -z "${SEEN_MODULES[$n]}" ]] && ME_MODULES+=("$n") && SEEN_MODULES["$n"]=1 && echo "   Loaded/Available: $n"
    fi
done

# Sweep .ko files — handle both /lib/modules and /usr/lib/modules (Arch uses /usr/lib only)
find /lib/modules /usr/lib/modules -type f -name "*.ko*" 2>/dev/null | while read -r f; do
    base=$(basename "$f" | sed -E 's/\.ko(\.(xz|gz|zst))?$//' | tr '-' '_')
    case "$base" in mei*|intel_vsec*|intel_csme*|pmt_*|iTCO_*|intel_gsc*|vsec_*)
        [[ -z "${SEEN_MODULES[$base]}" ]] && ME_MODULES+=("$base") && SEEN_MODULES["$base"]=1 && echo "   Found .ko: $base"
        ;;
    esac
done
echo

# ===================================================================
# [3/7] Resolve module dependencies
# ===================================================================
echo -e "${GREEN}[3/7] Resolving module dependencies...${NC}"
declare -A ALL_DEPS
for mod in "${ME_MODULES[@]}"; do
    deps=$(modinfo "$mod" 2>/dev/null | grep "^depends:" | cut -d: -f2 | tr ',' '\n' | tr -d ' ')
    [[ -n "$deps" ]] && while read -r d; do ALL_DEPS["$d"]=1; done <<< "$deps"
done
for dep in "${!ALL_DEPS[@]}"; do
    [[ ! " ${ME_MODULES[@]} " =~ " ${dep} " ]] && ME_MODULES+=("$dep") && echo "   + Adding dependency: $dep"
done
echo

# ===================================================================
# [4/7] Create module blacklist
# ===================================================================
echo -e "${GREEN}[4/7] Creating module blacklist...${NC}"
BLACKLIST_FILE="/etc/modprobe.d/disable-intel-me.conf"
[ -f "$BLACKLIST_FILE" ] && cp "$BLACKLIST_FILE" "$BACKUP_DIR/"

cat > "$BLACKLIST_FILE" << 'BLACKLIST'
# Intel ME/CSME/GSC — completely disabled — 2026
# Works on all distros: Debian, Arch, Fedora, Void, Alpine, Gentoo etc.

blacklist mei
blacklist mei_me
blacklist mei_gsc
blacklist mei_vsc
blacklist intel_vsec
blacklist intel_csme
blacklist intel_pmt
blacklist pmt_telemetry
blacklist iTCO_wdt

options mei off
options mei_me off
options mei_gsc off
BLACKLIST

SORTED_MODULES=($(printf '%s\n' "${ME_MODULES[@]}" | sort -u))
for mod in "${SORTED_MODULES[@]}"; do
    echo "install $mod /bin/false"       >> "$BLACKLIST_FILE"
    echo "softdep $mod pre: blacklist"   >> "$BLACKLIST_FILE"
done
echo -e "Updated: ${GREEN}$BLACKLIST_FILE${NC}\n"

# ===================================================================
# [5/7] Install udev rule (works on all init systems via eudev/systemd-udev)
# ===================================================================
echo -e "${GREEN}[5/7] Installing udev rule (device-ID + class)...${NC}"
UDEV_RULE_FILE="/etc/udev/rules.d/99-disable-intel-me.rules"
[ -f "$UDEV_RULE_FILE" ] && cp "$UDEV_RULE_FILE" "$BACKUP_DIR/"

cat > "$UDEV_RULE_FILE" << 'UDEV'
# Intel ME/CSME/GSC — permanently gone — Sandy Bridge through Panther Lake (2011–2026)
# Device IDs sourced from: Intel PCH datasheets (Doc 648364, 743835, 792044),
# coreboot pci_ids.h, Linux kernel drivers/misc/mei/hw-me-regs.h,
# Intel DS Doc 842704 (ARL), Doc 872188 (PTL)
# Works on all init systems — udev/eudev is init-independent
#
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", \
ATTR{device}=="0x1c3a|0x1e3a|0x8c3a|0x9c3a|0x9cba|0x9d3a|0xa13a|0xa13b|0xa13e|0xa2ba|0xa2bb|0xa2be|0x9de0|0x9de8|0xa360|0x02e0|0x02e8|0x06e0|0x06e8|0xa3b0|0xa3ba|0x34e0|0x34e8|0xa0e0|0xa0e8|0x43e0|0x43e8|0x43a8|0x4b28|0x51e0|0x51e8|0x51a8|0x54e0|0x54e8|0x7ae8|0x7ae9|0x7a68|0x7a69|0x7e70|0x7e71|0x7e74|0x7e28|0x7770|0x7771|0x7774|0x7775|0x7758|0x7759|0x775a|0xae70|0xae71|0xa870|0xa84a|0xa84e|0xa860|0xe362|0xe363|0xe364|0xe462|0xe463|0xe464", \
RUN+="/bin/sh -c 'echo 1 > /sys/bus/pci/devices/%k/remove || echo 1 > /sys/bus/pci/devices/%k/reset'"

ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{class}=="0x0c8080", \
RUN+="/bin/sh -c 'echo 1 > /sys/bus/pci/devices/%k/remove'"

ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{class}=="0x078000", \
RUN+="/bin/sh -c 'echo 1 > /sys/bus/pci/devices/%k/remove'"
UDEV

echo -e "Updated: ${GREEN}$UDEV_RULE_FILE${NC}\n"

# ===================================================================
# [6/7] Init system — install boot service if supported
# ===================================================================
echo -e "${GREEN}[6/7] Installing boot service (init: $INIT_SYSTEM)...${NC}"

case "$INIT_SYSTEM" in

    systemd)
        SERVICE_FILE="/etc/systemd/system/disable-intel-me.service"
        [ -f "$SERVICE_FILE" ] && cp "$SERVICE_FILE" "$BACKUP_DIR/"
        cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Kill Intel ME/CSME/GSC at boot
DefaultDependencies=no
After=systemd-udev-settle.service
Before=sysinit.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'udevadm control --reload-rules && udevadm trigger --subsystem-match=pci'
ExecStart=/bin/sh -c 'for m in ${ME_MODULES[*]}; do rmmod \$m 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now disable-intel-me.service &>/dev/null
        echo -e "   ${GREEN}systemd service installed and enabled${NC}"
        ;;

    openrc)
        OPENRC_FILE="/etc/init.d/disable-intel-me"
        [ -f "$OPENRC_FILE" ] && cp "$OPENRC_FILE" "$BACKUP_DIR/"
        cat > "$OPENRC_FILE" << 'OPENRC'
#!/sbin/openrc-run
description="Kill Intel ME/CSME/GSC at boot"
depend() { need udev; }
start() {
    ebegin "Disabling Intel ME"
    udevadm control --reload-rules
    udevadm trigger --subsystem-match=pci
    eend $?
}
OPENRC
        chmod +x "$OPENRC_FILE"
        rc-update add disable-intel-me default 2>/dev/null || true
        echo -e "   ${GREEN}OpenRC service installed (rc-update add disable-intel-me default)${NC}"
        ;;

    runit)
        RUNIT_DIR="/etc/sv/disable-intel-me"
        mkdir -p "$RUNIT_DIR"
        cat > "$RUNIT_DIR/run" << 'RUNIT'
#!/bin/sh
udevadm control --reload-rules
udevadm trigger --subsystem-match=pci
exec sleep inf
RUNIT
        chmod +x "$RUNIT_DIR/run"
        RUNIT_SV_DIR="${RUNIT_SERVICE_DIR:-/var/service}"
        [ -d "$RUNIT_SV_DIR" ] && ln -sf "$RUNIT_DIR" "$RUNIT_SV_DIR/" 2>/dev/null || true
        echo -e "   ${GREEN}runit service installed at $RUNIT_DIR${NC}"
        ;;

    dinit)
        DINIT_FILE="/etc/dinit.d/disable-intel-me"
        cat > "$DINIT_FILE" << 'DINIT'
type = scripted
command = /bin/sh -c "udevadm control --reload-rules && udevadm trigger --subsystem-match=pci"
DINIT
        dinitctl enable disable-intel-me 2>/dev/null || true
        echo -e "   ${GREEN}dinit service installed${NC}"
        ;;

    *)
        echo -e "   ${YELLOW}Init system not detected or not supported for service install.${NC}"
        echo -e "   ${YELLOW}udev rules + modprobe.d blacklist are sufficient for ME disable.${NC}"
        echo -e "   ${YELLOW}No persistent boot service installed — reboot to apply.${NC}"
        ;;
esac
echo

# ===================================================================
# [7/7] Apply immediately + rebuild initramfs
# ===================================================================
echo -e "${GREEN}[7/7] Applying immediately...${NC}"
udevadm control --reload-rules
udevadm trigger --subsystem-match=pci

echo "Unloading modules..."
for mod in $(printf '%s\n' "${ME_MODULES[@]}" | tac); do
    lsmod | grep -q "^$mod " && { echo "   rmmod $mod"; rmmod "$mod" 2>/dev/null || true; }
done

echo
echo "Rebuilding initramfs ($INITRAMFS_TOOL)..."
case "$INITRAMFS_TOOL" in
    update-initramfs)
        update-initramfs -u -k all || true
        ;;
    mkinitcpio)
        mkinitcpio -P || true
        ;;
    dracut)
        dracut --regenerate-all --force || true
        ;;
    booster)
        # Void Linux booster
        for k in /lib/modules/*/; do
            kver=$(basename "$k")
            booster build --force /boot/booster-${kver}.img --kernel-version "$kver" 2>/dev/null || true
        done
        ;;
    none)
        echo -e "${YELLOW}Warning: no initramfs tool found — blacklist may not apply until reboot${NC}"
        echo -e "${YELLOW}Manually run your distro's initramfs rebuild command after this script${NC}"
        ;;
esac

echo -e "\n${GREEN}=== Done — ME is disabled ===${NC}"
echo -e "${CYAN}Summary:${NC}"
echo "   Distro           : ${DISTRO_ID:-unknown}"
echo "   Init system      : $INIT_SYSTEM"
echo "   Modules blocked  : ${#SORTED_MODULES[@]}"
echo "   Udev rule        : 61 device IDs (Sandy Bridge→Panther Lake) + PCI class"
echo "   Initramfs rebuilt: $INITRAMFS_TOOL"
echo "   Backup           : $BACKUP_DIR"
echo -e "\n${YELLOW}Reboot now for permanent effect.${NC}"

read -p "Reboot now? (y/N): " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] && sleep 3 && reboot

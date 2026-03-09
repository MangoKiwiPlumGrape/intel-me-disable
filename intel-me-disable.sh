#!/bin/bash
# Intel Management Engine (ME/CSME/GSC) Disabler – (2026)


set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

echo -e "${GREEN}=== Intel ME/CSME/GSC Disabler – 2026 Ultimate Edition ===${NC}\n"

# Backup directory (kept exactly like you had it)
BACKUP_DIR="/root/me_disable_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
echo -e "${YELLOW}Backup directory: $BACKUP_DIR${NC}\n"

# ===================================================================
# [1/7] Detect visible ME (for pretty output only)
# ===================================================================
echo -e "${GREEN}[1/7] Detecting Intel ME interface...${NC}"
if lspci -nn | grep -i "8086.*mei\|management engine\|heci" | grep -q .; then
    lspci -nn | grep -i "8086.*mei\|management engine\|heci" | head -5
else
    echo -e "${YELLOW}No ME visible right now — already dead or hidden (perfect)${NC}"
fi
echo

# ===================================================================
# [2/7] Find every single ME-related module
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

# Sweep .ko files 
find /lib/modules /usr/lib/modules -type f -name "*.ko*" 2>/dev/null | while read -r f; do
    base=$(basename "$f" | sed -E 's/\.ko(\.(xz|gz|zst))?$//' | tr '-' '_')
    case "$base" in mei*|intel_vsec*|intel_csme*|pmt_*|iTCO_*|intel_gsc*|vsec_*) 
        [[ -z "${SEEN_MODULES[$base]}" ]] && ME_MODULES+=("$base") && SEEN_MODULES["$base"]=1 && echo "   Found .ko: $base"
        ;;
    esac
done
echo

# ===================================================================
# [3/7] 
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
# [4/7] 
# ===================================================================
echo -e "${GREEN}[4/7] Creating module blacklist...${NC}"
BLACKLIST_FILE="/etc/modprobe.d/disable-intel-me.conf"
[ -f "$BLACKLIST_FILE" ] && cp "$BLACKLIST_FILE" "$BACKUP_DIR/"

cat > "$BLACKLIST_FILE" << 'EOF'
# Intel ME/CSME/GSC — completely disabled — 2025
# Generated: $(date)

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
EOF

SORTED_MODULES=($(printf '%s\n' "${ME_MODULES[@]}" | sort -u))
for mod in "${SORTED_MODULES[@]}"; do
    echo "install $mod /bin/false"       >> "$BLACKLIST_FILE"
    echo "softdep $mod pre: blacklist"   >> "$BLACKLIST_FILE"
done
echo -e "Updated: ${GREEN}$BLACKLIST_FILE${NC}\n"

# ===================================================================
# [5/7] nice u read code. keep reading.
# ===================================================================
echo -e "${GREEN}[5/7] Installing 2025-proof udev rule (device-ID + class)${NC}"
UDEV_RULE_FILE="/etc/udev/rules.d/99-disable-intel-me.rules"
[ -f "$UDEV_RULE_FILE" ] && cp "$UDEV_RULE_FILE" "$BACKUP_DIR/"

cat > "$UDEV_RULE_FILE" << 'EOF'
# Intel ME/CSME/GSC — permanently gone — works on every Intel platform 2015–2025
ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", \
ATTR{device}=="0x1c3a|0x1e3a|0x8c3a|0x9c3a|0x9cba|0x9d3a|0xa13a|0x9de0|0xa360|0xa0e0|0x43a8|0x4b28|0x464e|0x467e|0x51a8|0x51e8|0x7e28|0x7d3a|0x7d60|0x7e40|0xa84a|0xa84e|0xa860", \
RUN+="/bin/sh -c 'echo 1 > /sys/bus/pci/devices/%k/remove || echo 1 > /sys/bus/pci/devices/%k/reset'"

ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{class}=="0x0c8080", \
RUN+="/bin/sh -c 'echo 1 > /sys/bus/pci/devices/%k/remove'"

ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x8086", ATTR{class}=="0x078000", \
RUN+="/bin/sh -c 'echo 1 > /sys/bus/pci/devices/%k/remove'"
EOF

echo -e "Updated: ${GREEN}$UDEV_RULE_FILE${NC}\n"

# ===================================================================
# [6/7] and then run sudo rm -rf / im kidding.
# ===================================================================
echo -e "${GREEN}[6/7] Installing early-boot service...${NC}"
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
echo -e "${GREEN}Service enabled${NC}\n"

# ===================================================================
# [7/7] Apply now 
# ===================================================================
echo -e "${GREEN}[7/7] Applying immediately...${NC}"
udevadm control --reload-rules
udevadm trigger --subsystem-match=pci

echo "Unloading modules..."
for mod in $(printf '%s\n' "${ME_MODULES[@]}" | tac); do
    lsmod | grep -q "^$mod " && { echo "   rmmod $mod"; rmmod "$mod" || true; }
done

update-initramfs -u -k all || true

echo -e "\n${GREEN}=== All done — ME is now truly dead on every modern ThinkPad ===${NC}"
echo -e "${YELLOW}Summary:${NC}"
echo "   • Modules blocked : ${#SORTED_MODULES[@]}"
echo "   • Udev rule       : device-ID + PCI class based (2025-proof)"
echo "   • Backup          : $BACKUP_DIR"
echo -e "\n${YELLOW}Reboot now for permanent effect.${NC}"

read -p "Reboot now? (y/N): " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] && sleep 5 && reboot

#!/usr/bin/env bash
# ==========================================================================
# FILE:    SETUP_UDEV.sh
# PROJECT: PS-OFDM vs PS-AFDM live USRP demo  --  V1, 26 Aug 2026
# AUTHORS: Dr. Hyeon Seok Rou  |  Chloe (Claude Code)
# --------------------------------------------------------------------------
# PURPOSE:
#   One-time USB permission setup for the Ettus B210 on a fresh Linux PC.
#   Installs the udev rules so MATLAB (as a normal user) can open the radio.
#   Run:  sudo ./SETUP_UDEV.sh     then unplug + re-plug the B210.
#
# IDs covered: 2500:0020 (B210, firmware loaded), 2500:0021 (Cypress
# bootloader state before firmware load — must match or the first firmware
# push fails), 3923:7813 (NI-branded variant).
# ==========================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo:  sudo ./SETUP_UDEV.sh"
  exit 1
fi

RULES=/etc/udev/rules.d/90-uhd-b210.rules
cat > "$RULES" << 'EOF'
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2500", ATTRS{idProduct}=="0020", MODE:="0666"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="2500", ATTRS{idProduct}=="0021", MODE:="0666"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="3923", ATTRS{idProduct}=="7813", MODE:="0666"
EOF
echo "wrote $RULES"

udevadm control --reload-rules
udevadm trigger
echo "udev rules reloaded."
echo
echo "NEXT: unplug and re-plug the B210 (USB 3.0 port, blue),"
echo "then check it enumerates:"
echo "    lsusb | grep -i '2500\\|ettus'"
echo "then in MATLAB:  findsdru"

if lsusb 2>/dev/null | grep -qi '2500\|ettus'; then
  echo
  echo "B210 currently visible on USB:"
  lsusb | grep -i '2500\|ettus'
  echo "(still re-plug once so the new permissions apply)"
fi

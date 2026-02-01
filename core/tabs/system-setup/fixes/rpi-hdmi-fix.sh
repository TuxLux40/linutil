#!/bin/sh
# Script to fix HDMI issues on Raspberry Pi devices, where it wouldn't boot if HDMI is not connected or monitor wasn't powered on during boot.
set -e

# Detect if running on a Raspberry Pi (POSIX sh-safe)
is_raspberry_pi() {
    # Prefer device tree model when available
    if [ -r /sys/firmware/devicetree/base/model ]; then
        if grep -qi "raspberry pi" /sys/firmware/devicetree/base/model; then
            return 0
        fi
    fi
    if [ -r /proc/device-tree/model ]; then
        if grep -qi "raspberry pi" /proc/device-tree/model; then
            return 0
        fi
    fi
    # Fallback checks
    if command -v raspi-config >/dev/null 2>&1; then
        return 0
    fi
    if grep -qi "raspberry pi" /proc/cpuinfo 2>/dev/null; then
        return 0
    fi
    return 1
}

# Guard: only run on Raspberry Pi
if ! is_raspberry_pi; then
    echo "Error: This script is intended for Raspberry Pi devices only." >&2
    exit 1
fi
if [ ! -f /boot/config.txt ]; then
    echo "Error: /boot/config.txt does not exist. Cannot proceed." >&2
    exit 1
fi
if ! grep -q "^hdmi_force_hotplug=1" /boot/config.txt; then
    echo "hdmi_force_hotplug=1" | sudo tee -a /boot/config.txt || echo "Failed to write to /boot/config.txt"
    echo "Added 'hdmi_force_hotplug=1' to /boot/config.txt. Please reboot for the changes to take effect."
else
    echo "'hdmi_force_hotplug=1' is already set in /boot/config.txt. No changes made."
fi
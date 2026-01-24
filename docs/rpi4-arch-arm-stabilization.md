# Raspberry Pi 4 (Arch Linux ARM) Stabilization Guide

This guide provides idempotent, production-friendly steps to stabilize a Raspberry Pi 4 (4 GB RAM) running Arch Linux ARM under memory pressure and service restart storms. It focuses on keeping SSH/Tailscale reachable, preventing aggressive systemd restart loops, enabling compressed swap in RAM, tuning the kernel for low memory, and controlling journald log growth and rate.

## Goals
- Keep SSH and Tailscale reachable under load
- Stop aggressive systemd restart loops
- Enable ZRAM swap with `zram-generator`
- Configure `earlyoom` for fast recovery, protecting critical services
- Apply safe low-RAM `sysctl` tunings (+ optional SD/IO tuning)
- Limit journald storage and rate, enable rotation and vacuum
- Cleanly disable/mask broken services (fix later if desired)

## ZRAM Swap (zram-generator)
Install and configure compressed swap in RAM with `zram-generator`.

```bash
sudo pacman -S --needed zram-generator
sudo tee /etc/systemd/zram-generator.conf >/dev/null << 'EOF'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
swap-priority = 100
EOF
sudo systemctl daemon-reload
# Start immediate without reboot (one of the two will exist)
sudo systemctl start systemd-zram-setup@zram0.service || sudo systemctl start dev-zram0.swap
```

Verify:
```bash
swapon --show
zramctl
cat /sys/block/zram0/comp_algorithm
systemctl status dev-zram0.swap --no-pager || true
```

## EarlyOOM (fast recovery under memory pressure)
Install, configure, protect SSH/Tailscale and prefer `earlyoom` over `systemd-oomd`.

```bash
sudo pacman -S --needed earlyoom
# Arch unit uses EnvironmentFile /etc/default/earlyoom
sudo tee /etc/default/earlyoom >/dev/null << 'EOF'
EARLYOOM_ARGS="-m 10 -s 10 -r 60 --avoid (^sshd$|^tailscaled$)"
EOF
sudo systemctl enable --now earlyoom.service
# Optional: disable systemd-oomd if enabled
sudo systemctl disable --now systemd-oomd.service || true
```

Protect critical services via OOMScore:
```bash
sudo install -d /etc/systemd/system/sshd.service.d /etc/systemd/system/tailscaled.service.d
sudo tee /etc/systemd/system/sshd.service.d/10-oom-protect.conf >/dev/null << 'EOF'
[Service]
OOMScoreAdjust=-900
EOF
sudo tee /etc/systemd/system/tailscaled.service.d/10-oom-protect.conf >/dev/null << 'EOF'
[Service]
OOMScoreAdjust=-900
EOF
sudo systemctl daemon-reload
```

Verify:
```bash
systemctl is-active earlyoom && systemctl is-enabled earlyoom
systemctl show sshd -p OOMScoreAdjust; systemctl show tailscaled -p OOMScoreAdjust
cat /proc/$(pidof sshd)/oom_score_adj 2>/dev/null || true
cat /proc/$(pidof tailscaled)/oom_score_adj 2>/dev/null || true
journalctl -u earlyoom -b --no-pager | tail -n 50
```

## Sysctl Tunings (low RAM + SD-friendly IO)
Balanced VM parameters for a 4 GB device with ZRAM swap.

```bash
sudo tee /etc/sysctl.d/99-lowram.conf >/dev/null << 'EOF'
vm.swappiness=100
vm.vfs_cache_pressure=200
vm.dirty_background_ratio=5
vm.dirty_ratio=10
vm.page-cluster=0
vm.min_free_kbytes=65536
EOF
sudo sysctl --system
```

Optional (bytes-based IO tuning, use either ratio or bytes):
```bash
# sudo tee /etc/sysctl.d/99-lowram-io.conf >/dev/null << 'EOF'
# vm.dirty_background_bytes=4194304   # 4 MiB
# vm.dirty_bytes=33554432             # 32 MiB
# EOF
# sudo sysctl --system
```

Verify:
```bash
sudo sysctl -a | grep -E 'vm\.swappiness|vm\.vfs_cache_pressure|vm\.dirty_background_ratio|vm\.dirty_ratio|vm\.page-cluster|vm\.min_free_kbytes'
```

## Journald Limits, Rotation, Vacuum
Constrain persistent journal size and rate, and periodically rotate/vacuum. With a 250 GB NVMe, a slightly higher cap is safe.

Recommended limits:
```bash
sudo install -d /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/limits.conf >/dev/null << 'EOF'
[Journal]
SystemMaxUse=2G
SystemMaxFileSize=200M
MaxRetentionSec=14day
RateLimitIntervalSec=30s
RateLimitBurst=1000
EOF
sudo systemctl restart systemd-journald
```

Manual rotation and vacuum (on demand or via timer):
```bash
sudo journalctl --rotate
sudo journalctl --vacuum-size=2G --vacuum-time=14d
journalctl --disk-usage
```

## Stress Test
Use `stress-ng` or temporary RAM/IO pressure to validate behavior.

```bash
sudo pacman -S --needed stress-ng
stress-ng --vm 3 --vm-bytes 75% --class io --timeout 120s --metrics-brief
# or without sudo: allocate RAM via tmpfs
dd if=/dev/zero of=/dev/shm/stressfile bs=64M count=20 status=progress
rm -f /dev/shm/stressfile
```

Monitor during stress:
```bash
free -h; vmstat 1 5; swapon --show
journalctl -u earlyoom -b --no-pager | tail -n 50
systemctl is-active sshd; systemctl is-active tailscaled || true
```

## Final Verification Checklist
- Swap: `swapon --show` lists `zram0` with high priority (≥100)
- Services: `earlyoom` active+enabled, `sshd`/`tailscaled` active
- OOM protection: `systemctl show sshd -p OOMScoreAdjust` → `-900` (process shows after restart)
- Journald: `journalctl --disk-usage` under the configured cap; rate limits applied
- Logs: `journalctl -p warning..alert -b` shows nothing critical
- RAM/IO: `free -h`, `vmstat 1 5` look stable under typical workloads

## Idempotency Notes
- All configuration writes overwrite the same files; re-running is safe.
- `systemctl disable --now` and `mask` are safe to repeat.
- `sysctl --system` applies all conf files; tune in a single `*.conf` to keep order predictable.
- `journalctl --rotate` and `--vacuum-*` are safe to run multiple times.

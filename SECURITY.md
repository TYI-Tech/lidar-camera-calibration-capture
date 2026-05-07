# Security Policy

This repository is intended to be publishable without robot credentials,
device identities, rosbag data, or deployment-specific configuration.

## What Not To Commit

- `.env`
- `calibration_data/`
- `logs/`
- `*.bag` or `*.bag.active`
- private registry URLs
- access tokens, refresh tokens, API keys, SSH keys, or certificates
- device fingerprints, serial numbers, pairing codes, or customer data
- internal hostnames, user home paths, or private network addresses

## Before Publishing

Run:

```bash
./scripts/calibration_capture.sh audit
git status --short
```

The audit command is a best-effort local scanner. It does not replace a
manual review of commit history, GitHub Actions secrets, container registries,
or uploaded release assets.

## Runtime Boundary

The capture container subscribes to existing ROS topics and may publish only
the configured calibration point cloud topic. It must not start, stop, restart,
or reconfigure the robot's production services.

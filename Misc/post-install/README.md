# Linux Post-Install Script

This repository contains a personal Linux post-installation script intended to bootstrap a fresh system with commonly used tools and sane defaults.

The script is designed to be:
- Cross-distro (**Ubuntu/Debian** and **Arch Linux**)
- Safe to re-run (idempotent where possible)
- Aware of **WSL** environments
- Non-interactive by default

---

## Supported Platforms

| Platform | Supported |
|--------|-----------|
| Ubuntu | ✅ |
| Debian | ✅ |
| Arch Linux | ✅ |
| WSL (v1/v2) | ✅ (auto-detected) |

Unsupported distributions will exit gracefully.

---

## Quick Start

Run directly from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/K4S1/K4S1/main/Misc/post-install/install.sh | sudo bash
```

> **Note**  
> The script must be run as root (`sudo`) because it installs system packages.

---

## Optional Features

Some components are disabled by default and can be enabled via environment variables.

### Enable Docker
```bash
curl -fsSL https://raw.githubusercontent.com/K4S1/K4S1/main/Misc/post-install/install.sh | sudo INSTALL_DOCKER=1 bash
```

Additional features can be added using the same pattern.

---

## What the Script Does

### 1. Environment Detection
- Detects Linux distribution via `/etc/os-release`
- Detects **WSL** via kernel identifiers
- Adjusts behavior accordingly (e.g. avoids systemd assumptions on WSL)

### 2. Package Installation
Installs a base set of commonly used CLI tools, mapped correctly per distribution.

Examples:
- `curl`, `wget`, `git`, `vim`, `tmux`
- `htop`, `jq`, `ripgrep`, `fd`
- DNS tools (`dig`, `nslookup`)
- Python tooling

Package names are resolved per distro:
- **Ubuntu/Debian**: `apt`
- **Arch**: `pacman`

### 3. Optional Tooling
- Docker (native repo, not distro snapshots)
- User is added to relevant groups where applicable

---

## WSL Behavior

When WSL is detected:
- Service enable/start steps are skipped or handled defensively
- The script remains safe to run inside WSL distributions

---

## Safety Notes

- Uses `set -Eeuo pipefail` for strict error handling
- Uses `curl -fsSL` to avoid partial or silent downloads
- Does **not** assume interactive input
- Designed to be readable and auditable before execution

---

## Recommended Usage

For maximum safety, you may prefer:

```bash
curl -fsSL https://raw.githubusercontent.com/K4S1/K4S1/main/Misc/post-install/install.sh -o install.sh
less install.sh
sudo bash install.sh
```

---

## Customization

This script is intended for **personal use**.

To customize:
- Edit package lists per distro
- Add optional feature blocks
- Extend WSL-specific logic if required

---

## License

Personal use. No warranty.

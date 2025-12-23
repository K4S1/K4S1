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

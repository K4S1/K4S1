# Linux Post-Install Script

Et personligt post-install script til Linux, designet til hurtigt at opsætte et nyt system på en reproducerbar måde.

Scriptet understøtter:
- Ubuntu / Debian
- Arch Linux
- WSL (Windows Subsystem for Linux)

---

## Funktioner

- Automatisk distro-detektion
- Interaktiv installationsmenu (TTY-baseret)
- Mulighed for non-interactive kørsel (flags / env vars)
- Valgbare installationskomponenter
- Docker som tilvalg
- Dotfiles-installation via `git --bare`
- DRY-RUN support (ingen ændringer)
- WSL-venlig (ingen antagelse om systemd)

---

## Anbefalet brug

Interaktiv kørsel med menu:

```bash
curl -fsSL https://raw.githubusercontent.com/K4S1/K4S1/main/Misc/post-install/install.sh -o install.sh
chmod +x install.sh
sudo ./install.sh
```

> Menuen virker kun, når scriptet køres som fil (ikke via `curl | bash`).

---

## Non-interactive brug

```bash
sudo NONINTERACTIVE=1 ./install.sh
```

Valg kan styres via miljøvariabler.

---

## DRY-RUN

Vis hvad scriptet ville gøre, uden at foretage ændringer:

```bash
sudo DRY_RUN=1 ./install.sh
```

---

## Dotfiles

Dotfiles kan installeres som tilvalg:

- Installeres via SSH (GitHub)
- Kræver en eksisterende SSH-key i `~/.ssh/github`
- Hvis SSH-adgang fejler, springes dotfiles over automatisk

---

## Noter

- Scriptet kræver `sudo`
- Cancel i menu afslutter uden at installere noget
- Egnet til både manuel brug og automatisering

---

## Licens

Personligt brug. Ingen garanti.

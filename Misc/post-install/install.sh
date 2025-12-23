#!/usr/bin/env bash
set -Eeuo pipefail

# ----------------------------
# Config (edit these)
# ----------------------------

# Packages by logical name. Keep these conservative and cross-distro.
COMMON_PKGS=(
  curl 
  wget 
  git
  vim
  nvim
  tmux
  unzip
  zip
  ca-certificates
  gnupg
  bpytop
  tree
  jq
  ripgrep
  speedtest-cli
  speedometer
)

# Ubuntu-only additions (names in apt)
UBUNTU_PKGS=(
  build-essential
  python3
  python3-pip
  dnsutils 
  fd-find 
  neovim
)

# Arch-only additions (names in pacman)
ARCH_PKGS=(
  base-devel
  python
  python-pip
)

# Optional tools you may install via other methods
INSTALL_DOCKER="${INSTALL_DOCKER:-0}"   # set to 1 to enable
INSTALL_TERRAFORM="${INSTALL_TERRAFORM:-0}"
INSTALL_NODE="${INSTALL_NODE:-0}"

# ----------------------------
# Logging helpers
# ----------------------------
log()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Run as root (use sudo)."
    exit 1
  fi
}

# ----------------------------
# Environment detection
# ----------------------------
is_wsl() {
  # WSL typically shows "Microsoft" in kernel release or /proc/version.
  grep -qiE "microsoft|wsl" /proc/sys/kernel/osrelease 2>/dev/null || \
  grep -qiE "microsoft|wsl" /proc/version 2>/dev/null
}

detect_distro() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian) echo "debian" ;;
      arch) echo "arch" ;;
      *) 
        # Some distros are arch-based or debian-based
        if [[ "${ID_LIKE:-}" == *"debian"* ]]; then echo "debian"; return; fi
        if [[ "${ID_LIKE:-}" == *"arch"* ]]; then echo "arch"; return; fi
        echo "unknown"
      ;;
    esac
  else
    echo "unknown"
  fi
}

# ----------------------------
# Package manager functions
# ----------------------------
apt_install() {
  log "Updating APT…"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  log "Installing packages (APT)…"
  apt-get install -y --no-install-recommends "$@"
}

pacman_install() {
  log "Updating pacman…"
  pacman -Syu --noconfirm
  log "Installing packages (pacman)…"
  pacman -S --noconfirm --needed "$@"
}

# ----------------------------
# Utilities
# ----------------------------
have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_sudo_user_home() {
  # If invoked with sudo, preserve target user context for dotfiles etc.
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    USER_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
  else
    USER_HOME="/root"
  fi
  export USER_HOME
}

# ----------------------------
# Optional installers (examples)
# ----------------------------
install_docker_debian() {
  log "Installing Docker (Debian/Ubuntu)…"
  if have_cmd docker; then
    log "Docker already present."
    return
  fi

  apt_install ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  # Use os-release values for codename if present
  # shellcheck disable=SC1091
  . /etc/os-release
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    usermod -aG docker "${SUDO_USER}" || true
    warn "Added ${SUDO_USER} to docker group. Re-login required."
  fi
}

install_docker_arch() {
  log "Installing Docker (Arch)…"
  if have_cmd docker; then
    log "Docker already present."
    return
  fi
  pacman_install docker docker-compose
  systemctl enable --now docker || warn "Could not enable docker service (maybe WSL)."
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    usermod -aG docker "${SUDO_USER}" || true
    warn "Added ${SUDO_USER} to docker group. Re-login required."
  fi
}

# ----------------------------
# Main
# ----------------------------
main() {
  need_root
  ensure_sudo_user_home

  DISTRO="$(detect_distro)"
  WSL="0"
  if is_wsl; then WSL="1"; fi

  log "Detected distro: ${DISTRO}"
  log "WSL: ${WSL}"

  case "${DISTRO}" in
    debian)
      # Translate fd-find name on Ubuntu (binary is "fdfind")
      apt_install "${COMMON_PKGS[@]}" "${UBUNTU_PKGS[@]}"

      # Provide an fd alias symlink if needed
      if have_cmd fdfind && ! have_cmd fd; then
        ln -sf "$(command -v fdfind)" /usr/local/bin/fd || true
      fi
    ;;
    arch)
      pacman_install "${COMMON_PKGS[@]}" "${ARCH_PKGS[@]}"
    ;;
    *)
      err "Unsupported distro. Only Ubuntu/Debian and Arch are handled."
      exit 2
    ;;
  esac

  # WSL-specific adjustments
  if [[ "${WSL}" == "1" ]]; then
    warn "WSL detected: skipping/adjusting systemd/service steps where appropriate."
    # Example: if you install services, don't assume systemctl works.
  fi

  # Optional components
  if [[ "${INSTALL_DOCKER}" == "1" ]]; then
    case "${DISTRO}" in
      debian) install_docker_debian ;;
      arch) install_docker_arch ;;
    esac
  fi

  log "Done."
}

main "$@"

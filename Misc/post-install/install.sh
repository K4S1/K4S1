#!/usr/bin/env bash
set -Eeuo pipefail

trap 'printf "\033[1;31m[ERR ]\033[0m Fejl på linje %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# ----------------------------
# Options (env vars)
# ----------------------------
DRY_RUN="${DRY_RUN:-0}"                 # 1 = print handlinger, men udfør ikke ændringer
NONINTERACTIVE="${NONINTERACTIVE:-0}"   # 1 = ingen menu (brug defaults/flags)

# Standard: installer "det meste"
INSTALL_BASE="${INSTALL_BASE:-1}"
INSTALL_FD="${INSTALL_FD:-1}"
INSTALL_EDITOR="${INSTALL_EDITOR:-1}"
INSTALL_DEV="${INSTALL_DEV:-1}"
INSTALL_NETTOOLS="${INSTALL_NETTOOLS:-1}"
INSTALL_EXTRAS="${INSTALL_EXTRAS:-0}"   # optional

# Tilvalg
INSTALL_DOCKER="${INSTALL_DOCKER:-0}"
INSTALL_DOTFILES="${INSTALL_DOTFILES:-0}"

# Dotfiles (fixed)
DOTFILES_REPO="git@github.com:K4S1/thedot.git"
DOTFILES_DIR_NAME=".thedot"             # ~/.thedot (git --bare)
DOTFILES_KEY_NAME="github"              # ~/.ssh/github (ed25519)

# ----------------------------
# Logging helpers
# ----------------------------
log()  { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf "\033[1;33m[DRY ]\033[0m %s\n" "$*"
    return 0
  fi
  eval "$@"
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Kør som root (brug sudo)."
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ----------------------------
# Environment detection
# ----------------------------
is_wsl() {
  grep -qiE "microsoft|wsl" /proc/sys/kernel/osrelease 2>/dev/null || \
  grep -qiE "microsoft|wsl" /proc/version 2>/dev/null
}

can_systemctl() {
  have_cmd systemctl && [[ -r /proc/1/comm ]] && grep -qx "systemd" /proc/1/comm
}

detect_distro_family() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
      ubuntu|debian) echo "debian" ;;
      arch) echo "arch" ;;
      *)
        if [[ "${ID_LIKE:-}" == *"debian"* ]]; then echo "debian"; return; fi
        if [[ "${ID_LIKE:-}" == *"arch"* ]]; then echo "arch"; return; fi
        echo "unknown"
      ;;
    esac
  else
    echo "unknown"
  fi
}

detect_os_id() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "${ID:-unknown}"
  else
    echo "unknown"
  fi
}

# ----------------------------
# Package lists (mapped per distro)
# ----------------------------
APT_BASE_PKGS=( curl wget git vim tmux unzip zip ca-certificates gnupg tree jq ripgrep dialog )
PACMAN_BASE_PKGS=( curl wget git vim tmux unzip zip ca-certificates gnupg tree jq ripgrep dialog )

APT_FD_PKGS=( fd-find )
PACMAN_FD_PKGS=( fd )

APT_EDITOR_PKGS=( neovim )
PACMAN_EDITOR_PKGS=( neovim )

APT_DEV_PKGS=( build-essential python3 python3-pip )
PACMAN_DEV_PKGS=( base-devel python python-pip )

APT_NET_PKGS=( dnsutils nmap mtr-tiny speedtest-cli )
PACMAN_NET_PKGS=( bind nmap mtr speedtest-cli )

APT_EXTRAS_PKGS=( htop bpytop speedometer )
PACMAN_EXTRAS_PKGS=( htop bpytop speedometer )

# ----------------------------
# Package manager functions
# ----------------------------
apt_update() { run "export DEBIAN_FRONTEND=noninteractive; apt-get update -y"; }
apt_install() { run "export DEBIAN_FRONTEND=noninteractive; apt-get install -y --no-install-recommends $*"; }

pacman_update() { run "pacman -Syu --noconfirm"; }
pacman_install() { run "pacman -S --noconfirm --needed $*"; }

# ----------------------------
# Menu (robust parsing, Cancel=exit)
# ----------------------------
set_all_off() {
  INSTALL_BASE=0 INSTALL_FD=0 INSTALL_EDITOR=0 INSTALL_DEV=0 INSTALL_NETTOOLS=0 INSTALL_EXTRAS=0 INSTALL_DOCKER=0 INSTALL_DOTFILES=0
}

enable_if_selected() {
  local item="$1"
  case "$item" in
    BASE)     INSTALL_BASE=1 ;;
    FD)       INSTALL_FD=1 ;;
    EDITOR)   INSTALL_EDITOR=1 ;;
    DEV)      INSTALL_DEV=1 ;;
    NETTOOLS) INSTALL_NETTOOLS=1 ;;
    EXTRAS)   INSTALL_EXTRAS=1 ;;
    DOCKER)   INSTALL_DOCKER=1 ;;
    DOTFILES) INSTALL_DOTFILES=1 ;;
  esac
}

menu_select_components() {
  [[ "$NONINTERACTIVE" == "1" ]] && return 0

  # Need stdin TTY for arrows/space. If no TTY, fall back to non-interactive defaults.
  if [[ ! -t 0 ]]; then
    warn "Ingen TTY til menu (typisk ved 'curl | bash'). Skifter til NONINTERACTIVE=1."
    NONINTERACTIVE=1
    return 0
  fi

  export TERM="${TERM:-xterm}"
  stty sane </dev/tty || true

  local height=20 width=78 listheight=10
  local output="" status=0

  if have_cmd dialog; then
    # FIX: Do NOT redirect stdout away; we need it for output capture.
    set +e
    output=$(
      dialog --title "Post-install" --checklist \
        "Vælg hvad der skal installeres (SPACE for at vælge/fravælge)" \
        $height $width $listheight \
        BASE     "Grundpakker (curl/git/vim/tmux/jq/ripgrep...)" on \
        FD       "fd (fd-find/fd) + evt symlink på Debian" on \
        EDITOR   "neovim" on \
        DEV      "build tools + python/pip" on \
        NETTOOLS "dns tools + nmap + mtr + speedtest" on \
        EXTRAS   "ekstra (htop/bpytop/speedometer...)" off \
        DOCKER   "Docker (tilvalg)" off \
        DOTFILES "Dotfiles (~/.thedot via SSH-key ~/.ssh/github)" off \
        --stdout \
        </dev/tty 2>/dev/tty
    )
    status=$?
    set -e

    # dialog: 0=OK, 1=Cancel, 255=ESC
    if [[ $status -ne 0 ]]; then
      warn "Bruger annullerede installationen."
      exit 0
    fi

  elif have_cmd whiptail; then
    set +e
    output=$(
      whiptail --title "Post-install" --checklist \
        "Vælg hvad der skal installeres (SPACE for at vælge/fravælge)" \
        $height $width $listheight \
        BASE     "Grundpakker (curl/git/vim/tmux/jq/ripgrep...)" ON \
        FD       "fd (fd-find/fd) + evt symlink på Debian" ON \
        EDITOR   "neovim" ON \
        DEV      "build tools + python/pip" ON \
        NETTOOLS "dns tools + nmap + mtr + speedtest" ON \
        EXTRAS   "ekstra (htop/bpytop/speedometer...)" OFF \
        DOCKER   "Docker (tilvalg)" OFF \
        DOTFILES "Dotfiles (~/.thedot via SSH-key ~/.ssh/github)" OFF \
        3>&1 1>&2 2>&3 \
        </dev/tty
    )
    status=$?
    set -e

    if [[ $status -ne 0 ]]; then
      warn "Bruger annullerede installationen."
      exit 0
    fi

  else
    warn "Hverken dialog eller whiptail er tilgængelig. Skifter til NONINTERACTIVE=1."
    NONINTERACTIVE=1
    return 0
  fi

  # Apply selections
  set_all_off
  output="${output//\"/}"
  for item in $output; do
    enable_if_selected "$item"
  done
}

print_plan() {
  local distro="$1" wsl="$2"
  log "Installationsplan"
  printf "  - Distro family: %s\n" "$distro"
  printf "  - WSL: %s\n" "$wsl"
  printf "  - DRY_RUN: %s\n" "$DRY_RUN"
  printf "  - NONINTERACTIVE: %s\n" "$NONINTERACTIVE"
  printf "  - BASE: %s | FD: %s | EDITOR: %s | DEV: %s | NETTOOLS: %s | EXTRAS: %s\n" \
    "$INSTALL_BASE" "$INSTALL_FD" "$INSTALL_EDITOR" "$INSTALL_DEV" "$INSTALL_NETTOOLS" "$INSTALL_EXTRAS"
  printf "  - DOCKER (tilvalg): %s\n" "$INSTALL_DOCKER"
  printf "  - DOTFILES (tilvalg): %s\n" "$INSTALL_DOTFILES"
}

# ----------------------------
# Docker install (optional)
# ----------------------------
install_docker_debian_family() {
  local os_id
  os_id="$(detect_os_id)"

  if have_cmd docker; then
    log "Docker findes allerede."
    return 0
  fi

  log "Installerer Docker (${os_id})…"
  apt_update
  apt_install ca-certificates curl gnupg
  run "install -m 0755 -d /etc/apt/keyrings"

  # shellcheck disable=SC1091
  . /etc/os-release

  local docker_base
  case "$os_id" in
    ubuntu) docker_base="https://download.docker.com/linux/ubuntu" ;;
    debian) docker_base="https://download.docker.com/linux/debian" ;;
    *) docker_base="https://download.docker.com/linux/ubuntu" ;;
  esac

  run "curl -fsSL ${docker_base}/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
  run "chmod a+r /etc/apt/keyrings/docker.gpg"
  run "printf '%s\n' \
'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${docker_base} ${VERSION_CODENAME} stable' \
> /etc/apt/sources.list.d/docker.list"

  apt_update
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    run "usermod -aG docker ${SUDO_USER} || true"
    warn "Tilføjet ${SUDO_USER} til docker-gruppen. Log ud/ind kræves."
  fi
}

install_docker_arch() {
  if have_cmd docker; then
    log "Docker findes allerede."
    return 0
  fi

  log "Installerer Docker (Arch)…"
  pacman_update
  pacman_install docker docker-compose

  if can_systemctl; then
    run "systemctl enable --now docker"
  else
    warn "systemctl er ikke tilgængelig (typisk WSL/no-systemd). Docker service er ikke aktiveret automatisk."
  fi

  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    run "usermod -aG docker ${SUDO_USER} || true"
    warn "Tilføjet ${SUDO_USER} til docker-gruppen. Log ud/ind kræves."
  fi
}

# ----------------------------
# Dotfiles (optional) via ~/.ssh/github
# ----------------------------
has_github_ssh_key() {
  local user="$1" home ssh_dir priv pub
  home="$(getent passwd "$user" | cut -d: -f6)"
  ssh_dir="${home}/.ssh"
  priv="${ssh_dir}/${DOTFILES_KEY_NAME}"
  pub="${priv}.pub"
  [[ -d "$ssh_dir" && -f "$priv" && -f "$pub" ]]
}

can_access_github_ssh() {
  local user="$1" home key out
  home="$(getent passwd "$user" | cut -d: -f6)"
  key="${home}/.ssh/${DOTFILES_KEY_NAME}"

  # GitHub returns exit code 1 even on successful auth, so parse output.
  out="$(sudo -u "$user" ssh \
    -i "$key" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=5 \
    -T git@github.com 2>&1 || true)"

  # Success pattern from GitHub
  echo "$out" | grep -qi "successfully authenticated"
}

install_dotfiles() {
  [[ "$INSTALL_DOTFILES" == "1" ]] || return 0

  local user="${SUDO_USER:-root}"
  local home
  home="$(getent passwd "$user" | cut -d: -f6)"

  local key="${home}/.ssh/${DOTFILES_KEY_NAME}"
  local bare_dir="${home}/${DOTFILES_DIR_NAME}"
  local worktree="${home}"

  log "Dotfiles valgt"

  if ! have_cmd git; then
    warn "git er ikke installeret endnu. Dotfiles springes over."
    return 0
  fi

  if ! has_github_ssh_key "$user"; then
    warn "Mangler SSH-key: ${home}/.ssh/${DOTFILES_KEY_NAME} (+ .pub). Dotfiles springes over."
    return 0
  fi

  if ! can_access_github_ssh "$user"; then
    warn "Kan ikke forbinde til GitHub via SSH med ${key}. Dotfiles springes over."
    return 0
  fi

  export GIT_SSH_COMMAND="ssh -i \"$key\" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

  if [[ -d "$bare_dir" ]]; then
    log "Dotfiles bare repo findes allerede: ${bare_dir}"
  else
    run "sudo -u \"$user\" git clone --bare \"$DOTFILES_REPO\" \"$bare_dir\""
  fi

  local dotgit="git --git-dir=\"${bare_dir}\" --work-tree=\"${worktree}\""

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN: ville checkout dotfiles"
    return 0
  fi

  if ! sudo -u "$user" bash -lc "$dotgit checkout"; then
    warn "Konflikter ved checkout. Flytter eksisterende filer til ~/.dotfiles-backup og prøver igen."

    sudo -u "$user" bash -lc "
      mkdir -p \"$worktree/.dotfiles-backup\" &&
      $dotgit checkout 2>&1 | grep -E \"^\s+\" | awk '{print \$1}' | while read -r f; do
        mkdir -p \"$worktree/.dotfiles-backup/\$(dirname \"\$f\")\"
        mv \"$worktree/\$f\" \"$worktree/.dotfiles-backup/\$f\"
      done
    " || true

    sudo -u "$user" bash -lc "$dotgit checkout"
  fi

  sudo -u "$user" bash -lc "$dotgit config status.showUntrackedFiles no"
  log "Dotfiles installeret."
}

# ----------------------------
# Main
# ----------------------------
main() {
  need_root

  local distro wsl
  distro="$(detect_distro_family)"
  wsl="0"; is_wsl && wsl="1"

  log "Distro family: ${distro}"
  log "WSL: ${wsl}"

  # Ensure dialog exists for interactive runs (stable arrows/space)
  if [[ "$NONINTERACTIVE" != "1" ]]; then
    case "$distro" in
      debian)
        if ! have_cmd dialog; then
          apt_update
          apt_install dialog
        fi
      ;;
      arch)
        if ! have_cmd dialog; then
          pacman_update
          pacman_install dialog
        fi
      ;;
    esac
  fi

  menu_select_components
  print_plan "$distro" "$wsl"

  case "$distro" in
    debian)
      apt_update
      [[ "$INSTALL_BASE" == "1" ]]     && apt_install "${APT_BASE_PKGS[*]}"
      [[ "$INSTALL_FD" == "1" ]]       && apt_install "${APT_FD_PKGS[*]}"
      [[ "$INSTALL_EDITOR" == "1" ]]   && apt_install "${APT_EDITOR_PKGS[*]}"
      [[ "$INSTALL_DEV" == "1" ]]      && apt_install "${APT_DEV_PKGS[*]}"
      [[ "$INSTALL_NETTOOLS" == "1" ]] && apt_install "${APT_NET_PKGS[*]}"

      if [[ "$INSTALL_FD" == "1" ]]; then
        if have_cmd fdfind && ! have_cmd fd; then
          run "ln -sf \"$(command -v fdfind)\" /usr/local/bin/fd || true"
        fi
      fi

      if [[ "$INSTALL_EXTRAS" == "1" ]]; then
        if [[ "$DRY_RUN" == "1" ]]; then
          run "true # ville installere EXTRAS: ${APT_EXTRAS_PKGS[*]}"
        else
          if ! (export DEBIAN_FRONTEND=noninteractive; apt-get install -y --no-install-recommends "${APT_EXTRAS_PKGS[@]}"); then
            warn "EXTRAS havde problemer på denne release. Fortsætter."
          fi
        fi
      fi
    ;;

    arch)
      pacman_update
      [[ "$INSTALL_BASE" == "1" ]]     && pacman_install "${PACMAN_BASE_PKGS[*]}"
      [[ "$INSTALL_FD" == "1" ]]       && pacman_install "${PACMAN_FD_PKGS[*]}"
      [[ "$INSTALL_EDITOR" == "1" ]]   && pacman_install "${PACMAN_EDITOR_PKGS[*]}"
      [[ "$INSTALL_DEV" == "1" ]]      && pacman_install "${PACMAN_DEV_PKGS[*]}"
      [[ "$INSTALL_NETTOOLS" == "1" ]] && pacman_install "${PACMAN_NET_PKGS[*]}"

      if [[ "$INSTALL_EXTRAS" == "1" ]]; then
        if [[ "$DRY_RUN" == "1" ]]; then
          run "true # ville installere EXTRAS: ${PACMAN_EXTRAS_PKGS[*]}"
        else
          if ! pacman -S --noconfirm --needed "${PACMAN_EXTRAS_PKGS[@]}"; then
            warn "EXTRAS havde problemer (pakker kan mangle i repo). Fortsætter."
          fi
        fi
      fi
    ;;

    *)
      err "Unsupported distro. Kun Ubuntu/Debian og Arch er understøttet."
      exit 2
    ;;
  esac

  if [[ "$INSTALL_DOCKER" == "1" ]]; then
    case "$distro" in
      debian) install_docker_debian_family ;;
      arch)   install_docker_arch ;;
    esac
  fi

  install_dotfiles

  log "Færdig."
}

main "$@"

#!/usr/bin/env bash
set -Eeuo pipefail

# ----------------------------
# Error handling
# ----------------------------
trap 'printf "\033[1;31m[ERR ]\033[0m Fejl på linje %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

# ----------------------------
# Options (env vars)
# ----------------------------
DRY_RUN="${DRY_RUN:-0}"                 # 1 = print handlinger, men udfør ikke ændringer
NONINTERACTIVE="${NONINTERACTIVE:-0}"   # 1 = ingen menu/prompts (brug defaults/flags)

# Standard: installer "det meste"
INSTALL_BASE="${INSTALL_BASE:-1}"
INSTALL_FD="${INSTALL_FD:-1}"
INSTALL_EDITOR="${INSTALL_EDITOR:-1}"
INSTALL_DEV="${INSTALL_DEV:-1}"
INSTALL_NETTOOLS="${INSTALL_NETTOOLS:-1}"
INSTALL_EXTRAS="${INSTALL_EXTRAS:-0}"   # stadig optional

# Tilvalg
INSTALL_DOCKER="${INSTALL_DOCKER:-0}"
INSTALL_DOTFILES="${INSTALL_DOTFILES:-0}"

# Dotfiles (fixed)
DOTFILES_REPO="git@github.com:K4S1/thedot.git"
DOTFILES_DIR_NAME=".thedot"             # ~/.thedot
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

ensure_sudo_user_home() {
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    USER_HOME="$(getent passwd "${SUDO_USER}" | cut -d: -f6)"
  else
    USER_HOME="/root"
  fi
  export USER_HOME
}

# ----------------------------
# Menu / prompts
# ----------------------------
prompt_yn() {
  local q="$1" var="$2" ans
  read -r -p "${q} [Y/n] " ans </dev/tty || true
  case "${ans,,}" in
    n|no) printf -v "$var" "0" ;;
    *)    printf -v "$var" "1" ;;
  esac
}


menu_select_components() {
  [[ "$NONINTERACTIVE" == "1" ]] && return 0

  # Kræv en rigtig TTY til interaktiv menu
  if [[ ! -t 0 || ! -t 1 ]]; then
    warn "Ingen TTY til menu (typisk ved pipe/CI). Skifter til NONINTERACTIVE=1."
    NONINTERACTIVE=1
    return 0
  fi

  # Gør terminalen “sane” og sæt et sikkert TERM (for arrow keys)
  export TERM="${TERM:-xterm}"
  stty sane </dev/tty || true

  # Defaults hvis bruger cancel'er
  local choices=""
  local height=20 width=78 listheight=10

  if have_cmd dialog; then
    # dialog skriver typisk til stderr; --stdout giver os resultatet på stdout
    choices=$(
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
        </dev/tty >/dev/tty
    ) || return 0

  elif have_cmd whiptail; then
    # whiptail: brug /dev/tty og korrekt fd-swap
    choices=$(
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
        </dev/tty >/dev/tty
    ) || return 0

  else
    warn "Hverken dialog eller whiptail er tilgængelig. Skifter til NONINTERACTIVE=1."
    NONINTERACTIVE=1
    return 0
  fi

  # Reset og sæt flags baseret på valg
  INSTALL_BASE=0 INSTALL_FD=0 INSTALL_EDITOR=0 INSTALL_DEV=0 INSTALL_NETTOOLS=0 INSTALL_EXTRAS=0 INSTALL_DOCKER=0 INSTALL_DOTFILES=0

  # dialog returnerer typisk: "BASE" "FD" ... (med anførselstegn)
  [[ "$choices" == *"BASE"* ]]     && INSTALL_BASE=1
  [[ "$choices" == *"FD"* ]]       && INSTALL_FD=1
  [[ "$choices" == *"EDITOR"* ]]   && INSTALL_EDITOR=1
  [[ "$choices" == *"DEV"* ]]      && INSTALL_DEV=1
  [[ "$choices" == *"NETTOOLS"* ]] && INSTALL_NETTOOLS=1
  [[ "$choices" == *"EXTRAS"* ]]   && INSTALL_EXTRAS=1
  [[ "$choices" == *"DOCKER"* ]]   && INSTALL_DOCKER=1
  [[ "$choices" == *"DOTFILES"* ]] && INSTALL_DOTFILES=1
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
# Package lists (mapped per distro)
# ----------------------------

APT_BASE_PKGS=( curl wget git vim tmux unzip zip ca-certificates gnupg tree jq ripgrep )
PACMAN_BASE_PKGS=( curl wget git vim tmux unzip zip ca-certificates gnupg tree jq ripgrep )

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
# Docker install
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
    *)
      warn "Ukendt OS ID (${os_id}); bruger ubuntu repo til Docker."
      docker_base="https://download.docker.com/linux/ubuntu"
    ;;
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
# Dotfiles (git --bare) via ~/.ssh/github
# ----------------------------
has_github_ssh_key() {
  local user="$1"
  local home ssh_dir key priv pub
  home="$(getent passwd "$user" | cut -d: -f6)"
  ssh_dir="${home}/.ssh"
  key="${ssh_dir}/${DOTFILES_KEY_NAME}"
  priv="$key"
  pub="${key}.pub"

  [[ -d "$ssh_dir" ]] || return 1
  [[ -f "$priv" ]] || return 1
  [[ -f "$pub" ]] || return 1

  # Warn on weak perms (do not fail)
  local perm
  perm="$(stat -c '%a' "$priv" 2>/dev/null || true)"
  if [[ -n "$perm" && "$perm" != "600" && "$perm" != "400" ]]; then
    warn "SSH-key permissions for ${priv} er ${perm}. Anbefalet: 600"
  fi

  return 0
}

can_access_github_ssh() {
  local user="$1"
  local home key
  home="$(getent passwd "$user" | cut -d: -f6)"
  key="${home}/.ssh/${DOTFILES_KEY_NAME}"

  sudo -u "$user" ssh \
    -i "$key" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    -o ConnectTimeout=5 \
    git@github.com >/dev/null 2>&1
}

install_dotfiles() {
  [[ "$INSTALL_DOTFILES" == "1" ]] || return 0

  local user="${SUDO_USER:-root}"
  local home
  home="$(getent passwd "$user" | cut -d: -f6)"

  local key="${home}/.ssh/${DOTFILES_KEY_NAME}"
  local bare_dir="${home}/${DOTFILES_DIR_NAME}"   # ~/.thedot
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
    warn "Tjek: nøglen er tilføjet i GitHub + evt. netværk/DNS."
    return 0
  fi

  # Force git to use this key (ingen afhængighed af ssh-agent)
  export GIT_SSH_COMMAND="ssh -i \"$key\" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

  if [[ -d "$bare_dir" ]]; then
    log "Dotfiles bare repo findes allerede: ${bare_dir}"
  else
    log "Cloner dotfiles repo til ${bare_dir}"
    run "sudo -u \"$user\" git clone --bare \"$DOTFILES_REPO\" \"$bare_dir\""
  fi

  local dotgit="git --git-dir=\"${bare_dir}\" --work-tree=\"${worktree}\""

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN: ville checkout dotfiles til ${worktree}"
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
  ensure_sudo_user_home

  local distro wsl
  distro="$(detect_distro_family)"
  wsl="0"
  if is_wsl; then wsl="1"; fi

  log "Distro family: ${distro}"
  log "WSL: ${wsl}"

  # Menu (kan fravælges med NONINTERACTIVE=1)
  menu_select_components
  print_plan "$distro" "$wsl"

  case "$distro" in
    debian)
      apt_update

      if [[ "$INSTALL_BASE" == "1" ]]; then
        apt_install "${APT_BASE_PKGS[*]}"
      fi

      if [[ "$INSTALL_FD" == "1" ]]; then
        apt_install "${APT_FD_PKGS[*]}"
        # fd binary on Debian/Ubuntu is often "fdfind"
        if have_cmd fdfind && ! have_cmd fd; then
          run "ln -sf \"$(command -v fdfind)\" /usr/local/bin/fd || true"
        fi
      fi

      if [[ "$INSTALL_EDITOR" == "1" ]]; then
        apt_install "${APT_EDITOR_PKGS[*]}"
      fi

      if [[ "$INSTALL_DEV" == "1" ]]; then
        apt_install "${APT_DEV_PKGS[*]}"
      fi

      if [[ "$INSTALL_NETTOOLS" == "1" ]]; then
        apt_install "${APT_NET_PKGS[*]}"
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

      if [[ "$INSTALL_BASE" == "1" ]]; then
        pacman_install "${PACMAN_BASE_PKGS[*]}"
      fi

      if [[ "$INSTALL_FD" == "1" ]]; then
        pacman_install "${PACMAN_FD_PKGS[*]}"
      fi

      if [[ "$INSTALL_EDITOR" == "1" ]]; then
        pacman_install "${PACMAN_EDITOR_PKGS[*]}"
      fi

      if [[ "$INSTALL_DEV" == "1" ]]; then
        pacman_install "${PACMAN_DEV_PKGS[*]}"
      fi

      if [[ "$INSTALL_NETTOOLS" == "1" ]]; then
        pacman_install "${PACMAN_NET_PKGS[*]}"
      fi

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

  # Docker (tilvalg)
  if [[ "$INSTALL_DOCKER" == "1" ]]; then
    case "$distro" in
      debian) install_docker_debian_family ;;
      arch)   install_docker_arch ;;
    esac
  fi

  # Dotfiles (tilvalg)
  install_dotfiles

  log "Færdig."
}

main "$@"

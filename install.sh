#!/usr/bin/env bash
# Arch Linux "master" : réinstalle toutes les apps après une install fraîche.
# Usage : ./install.sh   (en utilisateur normal, pas en root)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGLIST="$SCRIPT_DIR/pkglist.txt"

info() { printf '\e[1;34m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m==>\e[0m %s\n' "$*"; }
ok()   { printf '\e[1;32m==>\e[0m %s\n' "$*"; }

[[ $EUID -eq 0 ]] && { echo "Lance ce script en utilisateur normal, pas en root."; exit 1; }
command -v pacman >/dev/null || { echo "Ce script est prévu pour Arch Linux."; exit 1; }
[[ -f "$PKGLIST" ]] || { echo "pkglist.txt introuvable à côté du script."; exit 1; }

# --- 1. Système à jour + outils de base ---
info "Mise à jour du système"
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm base-devel git

# --- 2. yay (AUR helper) ---
if ! command -v yay >/dev/null; then
  info "Installation de yay"
  tmp="$(mktemp -d)"
  git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
  (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
  rm -rf "$tmp"
fi

# --- 3. Liste des paquets ---
mapfile -t pkgs < <(grep -vE '^\s*(#|$)' "$PKGLIST" | awk '{print $1}')

# Modules VirtualBox selon le noyau installé
if [[ "$(uname -r)" == *-arch* ]]; then
  pkgs+=(virtualbox-host-modules-arch)
else
  pkgs+=(virtualbox-host-dkms)
  for k in $(pacman -Qq linux linux-lts linux-zen linux-hardened 2>/dev/null || true); do
    pkgs+=("${k}-headers")
  done
fi

# --- 4. Installation (une par une : un échec AUR ne bloque pas le reste) ---
failed=()
for p in "${pkgs[@]}"; do
  info "Installation : $p"
  if ! yay -S --needed --noconfirm --answerclean None --answerdiff None "$p"; then
    warn "Échec : $p"
    failed+=("$p")
  fi
done

# --- 5. Post-configuration ---
if pacman -Q docker &>/dev/null; then
  info "Activation de Docker"
  sudo systemctl enable --now docker.service
  sudo usermod -aG docker "$USER"
fi

if pacman -Q virtualbox &>/dev/null; then
  info "Configuration de VirtualBox"
  sudo usermod -aG vboxusers "$USER"
  sudo modprobe vboxdrv 2>/dev/null || warn "Module vboxdrv non chargé : redémarre puis réessaie."
fi

# --- 6. Résumé ---
echo
if ((${#failed[@]})); then
  warn "Paquets en échec : ${failed[*]}"
  warn "Vérifie leur nom sur https://aur.archlinux.org puis corrige pkglist.txt."
else
  ok "Toutes les apps sont installées."
fi

cat <<'EOF'

À faire à la main :
  1. Redémarrer (ou se déconnecter) pour les groupes docker et vboxusers.
  2. Twingate : sudo twingate setup
  3. Se connecter à Proton Mail, Proton VPN, Synology Drive, Parsec, Discord.
EOF

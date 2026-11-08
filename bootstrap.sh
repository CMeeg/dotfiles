#!/usr/bin/env bash
set -euo pipefail

# Installs PowerShell 7 from Microsoft's apt repo if needed, then hands over to install.ps1.

repo_dir="$(cd "$(dirname "$0")" && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
  if ! compgen -G '/etc/apt/sources.list.d/microsoft-prod.*' >/dev/null; then
    # shellcheck source=/dev/null
    . /etc/os-release
    deb="$(mktemp --suffix=.deb)"
    trap 'rm -f "$deb"' EXIT
    curl -fsSL -o "$deb" "https://packages.microsoft.com/config/debian/${VERSION_ID}/packages-microsoft-prod.deb"
    sudo dpkg -i "$deb"
  fi
  sudo apt update
  sudo apt install -y powershell
fi

exec pwsh -NoProfile -File "$repo_dir/install.ps1" "$@"

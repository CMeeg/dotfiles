# GitKraken version helpers.
#
# Sourced by install.sh and update.sh. GitKraken's .deb adds no apt repo, so
# `apt upgrade` never updates it. Its download URL redirects to a versioned
# path (…/linux/x64/<version>/…/gitkraken-amd64.deb), which is how the latest
# version is found. That URL format isn't a documented API, so callers must
# treat a failed lookup as "unknown" and carry on.

GITKRAKEN_DEB_URL="https://release.gitkraken.com/linux/gitkraken-amd64.deb"

# Prints the version in a GitKraken download URL; returns 1 if there isn't one.
gitkraken_version_from_url() {
  local url="$1"
  if [[ "$url" =~ /linux/x64/([0-9]+(\.[0-9]+)+)/ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    return 1
  fi
}

# Prints the latest GitKraken version, read from the download redirect without
# downloading the package; returns 1 on any failure.
gitkraken_latest_version() {
  local url
  url="$(curl -fsSL --max-time 20 -r 0-0 -o /dev/null -w '%{url_effective}' "$GITKRAKEN_DEB_URL")" || return 1
  gitkraken_version_from_url "$url"
}

# Returns 0 when the installed version differs from the latest, ignoring any
# Debian revision suffix (12.6.2-1 equals 12.6.2); returns 1 when they match.
gitkraken_needs_update() {
  local installed="${1%%-*}" latest="$2"
  [ "$installed" != "$latest" ]
}

#!/usr/bin/env sh
#
# bootstrap.sh — one-shot "fully decrypted machine" bootstrap.
#
# Run BEFORE installing chezmoi:
#   sh -c "$(curl -fsLS https://raw.githubusercontent.com/andreweick/dotfiles/main/bootstrap.sh)"
#
# Why this exists:
#   chezmoi generates its config (~/.config/chezmoi/chezmoi.toml) from
#   .chezmoi.toml.tmpl ONLY at `chezmoi init`, and this repo only enables age
#   encryption in that config if ~/.config/age/key.txt already exists. So the
#   key MUST be in place BEFORE `chezmoi init`. This script does exactly that,
#   then runs init — so encryption is configured in a single pass.
#
# What it does (no sudo required):
#   1. Install chezmoi to ~/.local/bin if missing (also our age decryptor).
#   2. Download the passphrase-encrypted master key from this public repo.
#   3. Decrypt it with your master password -> ~/.config/age/key.txt (0600).
#   4. chezmoi init --apply <user>  (key present -> all secrets decrypt).
#
# Environment overrides:
#   GITHUB_USER     chezmoi source + raw host (default: andreweick)
#   BOOTSTRAP_REF   git ref/branch to fetch the key from (default: main)
#   BOOTSTRAP_INIT  set to 0 to only place the key and skip chezmoi init

set -eu

GITHUB_USER="${GITHUB_USER:-andreweick}"
BOOTSTRAP_REF="${BOOTSTRAP_REF:-main}"
BOOTSTRAP_INIT="${BOOTSTRAP_INIT:-1}"

BIN_DIR="$HOME/.local/bin"
KEY_DEST="$HOME/.config/age/key.txt"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/dotfiles/${BOOTSTRAP_REF}"
ENC_KEY_URL="${RAW_BASE}/private_dot_config/private_age/master_key_passphrase.age"

export PATH="$BIN_DIR:$PATH"

note() { printf '%s\n' "$*"; }
die()  { printf '❌ %s\n' "$*" >&2; exit 1; }

# Prompts must read from the real terminal: with `sh -c "$(curl ...)"` stdin is
# the tty, but read from /dev/tty explicitly so `curl | sh` also behaves.
if [ -r /dev/tty ]; then TTY=/dev/tty; else TTY=/dev/stdin; fi

command -v curl >/dev/null 2>&1 || die "curl is required."

# --- 1. Ensure chezmoi (doubles as our age decryptor — no separate age needed) ---
if ! command -v chezmoi >/dev/null 2>&1; then
    note "📦 Installing chezmoi to ${BIN_DIR}..."
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$BIN_DIR"
fi
CHEZMOI="$(command -v chezmoi || printf '%s' "$BIN_DIR/chezmoi")"
[ -x "$CHEZMOI" ] || die "chezmoi not found after install."

# --- 2. Download the passphrase-encrypted master key ---
TMP_ENC="$(mktemp)"
TMP_KEY="$(mktemp)"
trap 'rm -f "$TMP_ENC" "$TMP_KEY"' EXIT INT TERM
note "⬇️  Downloading encrypted master key (${BOOTSTRAP_REF})..."
curl -fsLS "$ENC_KEY_URL" -o "$TMP_ENC" || die "Could not download $ENC_KEY_URL"

# --- 3. Confirm overwrite, then decrypt with the master password ---
if [ -f "$KEY_DEST" ]; then
    printf "⚠️  %s already exists. Overwrite? (y/N): " "$KEY_DEST"
    read -r ans < "$TTY"
    case "$ans" in [yY]|[yY][eE][sS]) ;; *) note "› Aborting. No changes made."; exit 0 ;; esac
fi

note "🔐 Enter your master password to decrypt the key (stored in 1Password)."
if ! "$CHEZMOI" age decrypt --passphrase "$TMP_ENC" > "$TMP_KEY"; then
    die "Decryption failed (wrong password?). No key written."
fi
[ -s "$TMP_KEY" ] || die "Decryption produced an empty key. Aborting."

mkdir -p "$(dirname "$KEY_DEST")"
chmod 700 "$(dirname "$KEY_DEST")"
mv "$TMP_KEY" "$KEY_DEST"
chmod 600 "$KEY_DEST"
note "✅ Master key placed at ${KEY_DEST}"

# --- 4. init + apply (key now present -> encryption configured in one pass) ---
if [ "$BOOTSTRAP_INIT" != "0" ]; then
    note "🚀 Running: chezmoi init --apply ${GITHUB_USER}"
    "$CHEZMOI" init --apply "$GITHUB_USER"
    note "🎉 Done — fully decrypted machine."
else
    note "Key placed. Next: chezmoi init --apply ${GITHUB_USER}"
fi

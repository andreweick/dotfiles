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
#   2. Ask whether to set up the FULL (decrypted) machine or PUBLIC-only:
#        full   -> download + decrypt the master key, then chezmoi init --apply
#                  (key present -> all secrets decrypt).
#        public -> chezmoi init --apply with no key (encrypted files skipped via
#                  .chezmoiignore.tmpl; no secrets touched).
#      With no interactive terminal (Codespaces, cloud-init, Docker, CI, or the
#      one-liner pasted into automation) the prompt is skipped and PUBLIC is
#      used — full mode needs a tty for the passphrase, and secrets shouldn't
#      land on ephemeral machines anyway. (For Codespaces et al., install.sh
#      outranks bootstrap.sh and is the real entry point; this is a backstop.)
#
# Environment overrides:
#   GITHUB_USER     chezmoi source + raw host (default: andreweick)
#   BOOTSTRAP_REF   git ref/branch to fetch the key from (default: main)
#   BOOTSTRAP_INIT  set to 0 to skip chezmoi init (full: place key only)
#   BOOTSTRAP_MODE  full | public — skip the interactive prompt

set -eu

GITHUB_USER="${GITHUB_USER:-andreweick}"
BOOTSTRAP_REF="${BOOTSTRAP_REF:-main}"
BOOTSTRAP_INIT="${BOOTSTRAP_INIT:-1}"
BOOTSTRAP_MODE="${BOOTSTRAP_MODE:-}"

BIN_DIR="$HOME/.local/bin"
KEY_DEST="$HOME/.config/age/key.txt"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/dotfiles/${BOOTSTRAP_REF}"
ENC_KEY_URL="${RAW_BASE}/private_dot_config/private_age/master_key_passphrase.age"

export PATH="$BIN_DIR:$PATH"

note() { printf '%s\n' "$*"; }
die()  { printf '❌ %s\n' "$*" >&2; exit 1; }

# Can we actually open the controlling terminal? Note: `[ -r /dev/tty ]` is NOT
# a valid test — the device node is world-readable (crw-rw-rw-) even when there
# is no controlling tty, so access(2) always succeeds. Only an open() reveals
# the truth (it fails with ENXIO when headless).
have_tty() { ( : < /dev/tty ) 2>/dev/null; }

# Prompts must read from the real terminal: with `sh -c "$(curl ...)"` stdin is
# the tty, but read from /dev/tty explicitly so `curl | sh` also behaves.
if have_tty; then TTY=/dev/tty; else TTY=/dev/stdin; fi

# Is a human at a terminal we can prompt? False under any headless provisioning
# (Codespaces, Gitpod, dev containers, cloud-init, Docker builds, CI, etc.), so
# the mode prompt below falls back to `public` instead of hanging on a `read`.
# Known automation env vars force non-interactive even if a pseudo-tty exists.
is_interactive() {
    [ -n "${CODESPACES:-}${CI:-}${GITPOD_WORKSPACE_ID:-}${REMOTE_CONTAINERS:-}${DEVCONTAINER:-}" ] && return 1
    [ -t 0 ] && return 0
    have_tty && return 0
    return 1
}

command -v curl >/dev/null 2>&1 || die "curl is required."

# --- 1. Ensure chezmoi (doubles as our age decryptor — no separate age needed) ---
if ! command -v chezmoi >/dev/null 2>&1; then
    note "📦 Installing chezmoi to ${BIN_DIR}..."
    sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$BIN_DIR"
fi
CHEZMOI="$(command -v chezmoi || printf '%s' "$BIN_DIR/chezmoi")"
[ -x "$CHEZMOI" ] || die "chezmoi not found after install."

# --- 2. Choose mode: full (decrypt secrets) or public-only ---
case "$BOOTSTRAP_MODE" in
    full|public) ;;
    "")
        if ! is_interactive; then
            # Headless (VM/container/CI provisioning, or an accidental paste of
            # the curl one-liner into automation). Full mode is impossible here
            # anyway — age won't read a passphrase without a tty — and secrets
            # shouldn't land on ephemeral machines. Fail safe to public.
            BOOTSTRAP_MODE=public
            note "› No interactive terminal detected — defaulting to public (no secrets)."
            note "  Set BOOTSTRAP_MODE=full and run from a terminal to decrypt secrets."
        else
            note ""
            note "How do you want to set up this machine?"
            note "  [f] full   — decrypt private keys & secrets (asks for master password)"
            note "  [p] public — install public dotfiles only, no secrets"
            printf "Choice ([f]/p): "
            read -r mode_ans < "$TTY"
            case "$mode_ans" in
                [pP]|[pP][uU][bB][lL][iI][cC]) BOOTSTRAP_MODE=public ;;
                *)                             BOOTSTRAP_MODE=full ;;
            esac
        fi
        ;;
    *) die "Invalid BOOTSTRAP_MODE='$BOOTSTRAP_MODE' (use full or public)." ;;
esac

# --- 3. Full mode: download + decrypt the master key into place ---
if [ "$BOOTSTRAP_MODE" = full ]; then
    TMP_ENC="$(mktemp)"
    TMP_RAW="$(mktemp)"
    TMP_KEY="$(mktemp)"
    trap 'rm -f "$TMP_ENC" "$TMP_RAW" "$TMP_KEY"' EXIT INT TERM
    note "⬇️  Downloading encrypted master key (${BOOTSTRAP_REF})..."
    curl -fsLS "$ENC_KEY_URL" -o "$TMP_ENC" || die "Could not download $ENC_KEY_URL"

    if [ -f "$KEY_DEST" ]; then
        printf "⚠️  %s already exists. Overwrite? (y/N): " "$KEY_DEST"
        read -r ans < "$TTY"
        case "$ans" in [yY]|[yY][eE][sS]) ;; *) note "› Aborting. No changes made."; exit 0 ;; esac
    fi

    note "🔐 Enter your master password to decrypt the key (stored in 1Password)."
    if ! "$CHEZMOI" age decrypt --passphrase "$TMP_ENC" > "$TMP_RAW"; then
        die "Decryption failed (wrong password?). No key written."
    fi

    # chezmoi's interactive passphrase prompt is a TUI that writes the prompt
    # text and terminal control sequences to stdout — which we captured above.
    # Extract only the age secret key(s) so prompt noise never pollutes the file.
    grep -oE 'AGE-SECRET-KEY-1[A-Z0-9]+' "$TMP_RAW" > "$TMP_KEY" || true
    [ -s "$TMP_KEY" ] || die "No age secret key found in decrypted output (wrong password?). Aborting."

    mkdir -p "$(dirname "$KEY_DEST")"
    chmod 700 "$(dirname "$KEY_DEST")"
    mv "$TMP_KEY" "$KEY_DEST"
    chmod 600 "$KEY_DEST"
    note "✅ Master key placed at ${KEY_DEST}"
else
    note "› Public-only mode: skipping master key (encrypted files will be ignored)."
fi

# --- 4. init + apply ---
if [ "$BOOTSTRAP_INIT" != "0" ]; then
    note "🚀 Running: chezmoi init --apply ${GITHUB_USER}"
    "$CHEZMOI" init --apply "$GITHUB_USER"
    if [ "$BOOTSTRAP_MODE" = full ]; then
        note "🎉 Done — fully decrypted machine."
    else
        note "🎉 Done — public dotfiles installed (no secrets)."
    fi
elif [ "$BOOTSTRAP_MODE" = full ]; then
    note "Key placed. Next: chezmoi init --apply ${GITHUB_USER}"
else
    note "Next: chezmoi init --apply ${GITHUB_USER}"
fi

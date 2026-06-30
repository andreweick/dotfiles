#!/usr/bin/env sh
#
# FILENAME: setup-age-key.sh
#
# Bootstraps the master age key by decrypting it with your master password.
# The master password is stored in 1Password (see README).
#
# Run this once on any new machine, then run `chezmoi apply`.

set -e

# --- Determine script's own directory to make it runnable from anywhere ---
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

# --- Configuration ---
# The final destination for your decrypted age private key.
KEY_DESTINATION="${HOME}/.config/age/key.txt"

# The path to your passphrase-encrypted master age key file (in this repo).
ENCRYPTED_KEY_PASSPHRASE="${SCRIPT_DIR}/private_dot_config/private_age/master_key_passphrase.age"


# --- Script Logic ---

# 1. Check that age is available.
if ! command -v age >/dev/null 2>&1; then
    echo "❌ ERROR: 'age' is not installed. Install it first (e.g. 'sudo apt install age')."
    exit 1
fi

# 2. Check that the encrypted master key exists.
if [ ! -f "${ENCRYPTED_KEY_PASSPHRASE}" ]; then
    echo "❌ ERROR: Encrypted master key not found at:"
    echo "   ${ENCRYPTED_KEY_PASSPHRASE}"
    exit 1
fi

# 3. Check if the final key already exists and ask to overwrite.
if [ -f "${KEY_DESTINATION}" ]; then
    printf "⚠️  WARNING: The key file at '%s' already exists. Overwrite? (y/N): " "${KEY_DESTINATION}"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            echo "› Proceeding with overwrite..."
            ;;
        *)
            echo "› Aborting. No changes made."
            exit 0
            ;;
    esac
fi

# 4. Ensure the destination directory exists with secure permissions.
mkdir -p "$(dirname "${KEY_DESTINATION}")"
# Set secure permissions only on the age directory, not the entire .config
chmod 700 "$(dirname "${KEY_DESTINATION}")"

# 5. Decrypt with the master password. `age` prompts for the passphrase.
echo "🔐 Decrypting master key — enter your master password when prompted."
echo "   (Stored in 1Password — see README.)"
if ! age --decrypt --output "${KEY_DESTINATION}" "${ENCRYPTED_KEY_PASSPHRASE}"; then
    echo "❌ ERROR: Decryption failed (wrong password?). No key written."
    rm -f "${KEY_DESTINATION}" >/dev/null 2>&1
    exit 1
fi

# 6. Set correct permissions and finish.
chmod 600 "${KEY_DESTINATION}"

echo "✅ Successfully placed master age key at: ${KEY_DESTINATION}"
echo "   Now run 'chezmoi apply' to decrypt and apply your encrypted files."

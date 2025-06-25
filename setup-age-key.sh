#!/usr/bin/env sh
#
# FILENAME: setup_age_key.sh
#
# This script interactively decrypts the master age key and places it in the
# correct location. Run this script once on a trusted machine before running
# `chezmoi apply` for the first time. This script can be run from any directory.
#
# The password is stored in 1password at "op://Private/xcjfxrcih4tzajtsocvlkpjgm4/password" (Age Encryption Password and Key(s))
#
# USAGE:
#   "$(chezmoi source-path)/setup_age_key.sh"

set -e

# --- Determine script's own directory to make it runnable from anywhere ---
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

# --- Configuration ---
# The final destination for your decrypted age private key.
KEY_DESTINATION="${HOME}/.config/age/key.txt"

# The absolute path to your *symmetrically encrypted* age key within this repo.
ENCRYPTED_KEY_SOURCE="${SCRIPT_DIR}/private_dot_config/age/secret_key.txt.age-symmetric"


# --- Script Logic ---

# 1. Check if the final key already exists.
if [ -f "${KEY_DESTINATION}" ]; then
  echo "✅ Primary age key already exists at ${KEY_DESTINATION}. No action needed."
  exit 0
fi

# 2. Check if the source encrypted file exists.
if [ ! -f "${ENCRYPTED_KEY_SOURCE}" ]; then
  echo "❌ ERROR: Source key file not found at ${ENCRYPTED_KEY_SOURCE}"
  exit 1
fi

# 3. Ensure the destination directory exists.
mkdir -p "$(dirname "${KEY_DESTINATION}")"

# 4. Decrypt the key.
#    The `age` command will now handle the interactive password prompt itself.
#    It will ask for the passphrase once, securely.
echo "🔐 Preparing to decrypt master key. Please enter your password when prompted."
age --decrypt -o "${KEY_DESTINATION}" "${ENCRYPTED_KEY_SOURCE}"

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Decryption failed. Please check your password."
    # Clean up the potentially empty destination file on failure
    rm -f "${KEY_DESTINATION}"
    exit 1
fi

# 5. Set correct permissions on the newly decrypted key.
chmod 600 "${KEY_DESTINATION}"

echo "✅ Successfully decrypted and placed primary age key at: ${KEY_DESTINATION}"
echo "You can now run 'chezmoi apply'."

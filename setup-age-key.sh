#!/usr/bin/env sh
#
# FILENAME: setup_age_key.sh
#
# This script manually decrypts the master age key and places it in the
# correct location. Run this script once on a trusted machine before running
# `chezmoi apply` for the first time.
#
# USAGE (interactive):
#   ./setup_age_key.sh
#
# USAGE (non-interactive):
#   AGE_PASSWORD="your-secret-password" ./setup_age_key.sh

set -e

# --- Configuration ---
# The final destination for your decrypted age private key.
KEY_DESTINATION="${HOME}/.config/age/key.txt"

# The relative path to your *symmetrically encrypted* age key within this repo.
# Assumes this script is run from the root of your dotfiles repository.
ENCRYPTED_KEY_SOURCE="./private_dot_config/age/secret_key.txt.age-symmetric"


# --- Script Logic ---

# 1. Check if the final key already exists.
if [ -f "${KEY_DESTINATION}" ]; then
  echo "✅ Primary age key already exists at ${KEY_DESTINATION}. No action needed."
  exit 0
fi

# 2. Check if the source encrypted file exists.
if [ ! -f "${ENCRYPTED_KEY_SOURCE}" ]; then
  echo "❌ ERROR: Source key file not found at ${ENCRYPTED_KEY_SOURCE}"
  echo "   Please make sure you are running this script from the root of your dotfiles repository."
  exit 1
fi

# 3. Check for the AGE_PASSWORD environment variable, or prompt if not set.
if [ -z "${AGE_PASSWORD}" ]; then
  # Check if the script is running in an interactive terminal.
  if [ -t 0 ]; then
    # Use a portable way to prompt for the password that works on Linux and macOS.
    echo "Enter Master Password: "
    # stty -echo temporarily disables echoing characters to the terminal.
    stty -echo
    read AGE_PASSWORD
    stty echo
    echo # Print a newline for cleaner output.
  fi

  if [ -z "${AGE_PASSWORD}" ]; then
    echo "❌ ERROR: AGE_PASSWORD environment variable is not set and no password was provided."
    echo "   Usage: AGE_PASSWORD=\"your-password\" ./setup_age_key.sh"
    exit 1
  fi
fi

# 4. Decrypt the key using the provided password.
echo "🔐 Decrypting key using AGE_PASSWORD..."
printf "%s" "${AGE_PASSWORD}" | age --decrypt -o "${KEY_DESTINATION}" "${ENCRYPTED_KEY_SOURCE}"

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

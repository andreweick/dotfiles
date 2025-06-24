#!/usr/bin/env sh
#
# FILENAME: run_before_decrypt-age-key.sh
#
# This script bootstraps the entire chezmoi decryption process.
# It checks for a master key in the CHEZMOI_MASTER_KEY or AGE_PASSWORD
# environment variables. If found, it uses that key to symmetrically decrypt
# the primary age private key.
# It only produces output when run in an interactive terminal, unless an error occurs.

set -e

# --- Configuration ---
# The final destination for your decrypted age private key.
# This MUST match the `identity` path in your chezmoi.toml.
KEY_DESTINATION="${HOME}/.config/age/key.txt"

# The path to your *symmetrically encrypted* age key within your chezmoi source repo.
# Update this to match where you added the file in Step 2.
ENCRYPTED_KEY_SOURCE_REL_PATH="private_dot_config/age/secret_key.txt.age-symmetric"

# --- Helper Functions ---

# log prints a message to stdout only if the script is running interactively.
log() {
  # Check if stdout is a terminal
  if [ -t 1 ]; then
    echo "$@"
  fi
}

# warn prints a message to stderr.
warn() {
  # Print to standard error
  echo "$@" >&2
}


# --- Script Logic ---

# 1. Check if the final key already exists. If so, we don't need to do anything.
if [ -f "${KEY_DESTINATION}" ]; then
  log "✅ Primary age key already exists at ${KEY_DESTINATION}. Skipping decryption."
  exit 0
fi

# 2. If the key doesn't exist, check for a master password environment variable.
log "ℹ️ Primary age key not found. Checking for master password..."

MASTER_PASSWORD=""
if [ -n "${CHEZMOI_MASTER_KEY}" ]; then
  MASTER_PASSWORD="${CHEZMOI_MASTER_KEY}"
  log "🔑 Using CHEZMOI_MASTER_KEY for decryption."
elif [ -n "${AGE_PASSWORD}" ]; then
  MASTER_PASSWORD="${AGE_PASSWORD}"
  log "🔑 Using AGE_PASSWORD for decryption."
fi

if [ -z "${MASTER_PASSWORD}" ]; then
  # If no variable is set, we can't proceed. Print errors to stderr.
  warn "⚠️ WARNING: Neither CHEZMOI_MASTER_KEY nor AGE_PASSWORD is set. Cannot decrypt primary age key."
  warn "           Encrypted files may fail to apply."
  exit 0
fi

# 3. If a master password is present, decrypt the private key.
log "🔐 Attempting to decrypt the primary age key..."

# Get the full path to the source file
ENCRYPTED_KEY_SOURCE_ABS_PATH="$(chezmoi source-path)/${ENCRYPTED_KEY_SOURCE_REL_PATH}"

# Ensure the destination directory exists
mkdir -p "$(dirname "${KEY_DESTINATION}")"

# Use the environment variable as a passphrase to decrypt the file.
# The decrypted content is written directly to the destination file.
echo "${MASTER_PASSWORD}" | age --decrypt -i - -o "${KEY_DESTINATION}" "${ENCRYPTED_KEY_SOURCE_ABS_PATH}"

# 4. Set correct permissions on the newly decrypted key. This is critical.
chmod 600 "${KEY_DESTINATION}"

log "✅ Successfully decrypted and placed primary age key at ${KEY_DESTINATION}"

exit 0

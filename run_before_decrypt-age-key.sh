#!/usr/bin/env sh
#
# FILENAME: run_before_decrypt-age-key.sh
#
# This script bootstraps the entire chezmoi decryption process.
# It checks for a master key in the CHEZMOI_MASTER_KEY or AGE_PASSWORD
# environment variables. If found, it uses that key to symmetrically decrypt
# the primary age private key.
# It only produces output when run in an interactive terminal, unless an error occurs.

# --- DEBUGGING: Print every command as it's executed ---
set -x

set -e

# --- Configuration ---
# The final destination for your decrypted age private key.
# This MUST match the `identity` path in your chezmoi.toml.
KEY_DESTINATION="${HOME}/.config/age/key.txt"

# The path to your *symmetrically encrypted* age key within your chezmoi source repo.
# Update this to match where you added the file.
ENCRYPTED_KEY_SOURCE_REL_PATH="private_dot_config/age/secret_key.txt.age-symmetric"

# --- Helper Functions ---

# log prints a message to stdout only if the script is running interactively.
log() {
  # Temporarily disable command tracing for this function
  { set +x; } 2>/dev/null
  if [ -t 1 ]; then
    echo "$@"
  fi
  set -x
}

# warn prints a message to stderr.
warn() {
  # Temporarily disable command tracing for this function
  { set +x; } 2>/dev/null
  echo "$@" >&2
  set -x
}


# --- Script Logic ---
warn "--- SCRIPT START ---"

# 1. Check if the final key already exists.
if [ -f "${KEY_DESTINATION}" ]; then
  log "✅ Primary age key already exists at ${KEY_DESTINATION}. Skipping decryption."
  warn "--- SCRIPT END: Key already exists. ---"
  exit 0
fi

# 2. Check for a master password environment variable.
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
  warn "⚠️ WARNING: Neither CHEZMOI_MASTER_KEY nor AGE_PASSWORD is set. Cannot decrypt primary age key."
  warn "           Encrypted files may fail to apply."
  warn "--- SCRIPT END: No password provided. ---"
  exit 0
fi

warn "DEBUG: Master password variable is set."

# 3. Decrypt the private key.
log "🔐 Attempting to decrypt the primary age key..."

# Use the CHEZMOI_SOURCE_DIR environment variable instead of calling `chezmoi source-path`.
# This avoids the state lock error.
ENCRYPTED_KEY_SOURCE_ABS_PATH="${CHEZMOI_SOURCE_DIR}/${ENCRYPTED_KEY_SOURCE_REL_PATH}"

warn "DEBUG: Source file is: ${ENCRYPTED_KEY_SOURCE_ABS_PATH}"
warn "DEBUG: Destination file is: ${KEY_DESTINATION}"

# Ensure the destination directory exists
mkdir -p "$(dirname "${KEY_DESTINATION}")"

# Use `printf` to pipe the password to the `age` command.
warn "DEBUG: Preparing to execute age command..."
printf "%s" "${MASTER_PASSWORD}" | age --decrypt -o "${KEY_DESTINATION}" "${ENCRYPTED_KEY_SOURCE_ABS_PATH}"
warn "DEBUG: age command finished with exit code $?."

# 4. Set correct permissions on the newly decrypted key.
chmod 600 "${KEY_DESTINATION}"

log "✅ Successfully decrypted and placed primary age key at ${KEY_DESTINATION}"
warn "--- SCRIPT END: Decryption complete. ---"

exit 0

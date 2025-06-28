#!/usr/bin/env sh
#
# FILENAME: generate_encrypted_keys.sh
#
# This helper script encrypts your master age private key in two ways:
#   1. Encrypted to ALL SUPPORTED SSH public keys found in ~/.ssh.
#   2. Encrypted with a symmetric master password.
#
# It assumes the unencrypted key is located at ~/.config/age/key.txt.
# It will check if the encrypted keys already exist and ask before overwriting.

set -e

# --- Configuration ---
# Assume the unencrypted private key is always at this location.
PLAINTEXT_KEY_PATH="${HOME}/.config/age/key.txt"
# Define the final destination for the generated keys inside the chezmoi source tree
CHEZMOI_KEYS_DIR="$(chezmoi source-path)/private_dot_config/age"
# Define locations to search for public keys
SSH_DIR="${HOME}/.ssh"

# --- Helper Function ---
# Asks the user for confirmation before overwriting an existing file.
confirm_overwrite() {
    local filename=$1
    local response
    if [ -f "$filename" ]; then
        # Use printf for portability between shells (e.g., macOS and Linux)
        printf "⚠️  WARNING: File '%s' already exists. Overwrite? (y/N): " "$filename"
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0 # Yes, proceed with overwrite
                ;;
            *)
                echo "   › Skipping generation for '$filename'."
                return 1 # No, do not overwrite
                ;;
        esac
    fi
    return 0 # File does not exist, proceed
}


# --- Script Logic ---

# 1. Check if the original, unencrypted age private key exists.
echo "› Verifying unencrypted key at '${PLAINTEXT_KEY_PATH}'..."
if [ ! -f "${PLAINTEXT_KEY_PATH}" ]; then
    echo "❌ ERROR: Unencrypted key not found at '${PLAINTEXT_KEY_PATH}'"
    echo "   Please make sure your master age key exists at that location."
    exit 1
fi
echo "› Key found."

# Ensure the destination directory exists
mkdir -p "${CHEZMOI_KEYS_DIR}"

echo ""
# 2. Encrypt with all available SSH keys.
if confirm_overwrite "${CHEZMOI_KEYS_DIR}/master_key_ssh.age"; then
    echo "🔎 Searching for SSH public keys..."

    # Create a temporary file to hold all potential public keys
    ALL_KEYS_TMP=$(mktemp)
    # Create a final, clean recipients file
    RECIPIENTS_FILE=$(mktemp)

    # Gather keys from all common locations into the temporary file
    find "${SSH_DIR}" -type f -name "*.pub" -exec cat {} + >> "${ALL_KEYS_TMP}" 2>/dev/null || true
    [ -f "${SSH_DIR}/authorized_keys" ] && cat "${SSH_DIR}/authorized_keys" >> "${ALL_KEYS_TMP}"
    [ -f "${SSH_DIR}/ignition" ] && cat "${SSH_DIR}/ignition" >> "${ALL_KEYS_TMP}"
    [ -d "${SSH_DIR}/authorized_keys.d" ] && find "${SSH_DIR}/authorized_keys.d" -type f -exec cat {} + >> "${ALL_KEYS_TMP}" 2>/dev/null || true

    # Filter out unsupported ecdsa keys, comments, and empty lines, then de-duplicate
    grep -v "ecdsa-sha2-nistp256" "${ALL_KEYS_TMP}" | grep -v "^\s*#" | grep -v "^\s*$" | sort -u > "${RECIPIENTS_FILE}"
    rm -f "${ALL_KEYS_TMP}"

    if [ ! -s "${RECIPIENTS_FILE}" ]; then
        echo "⚠️ WARNING: No SUPPORTED SSH public keys found. Skipping SSH-based encryption."
    else
        echo "› Preparing to encrypt to the following SUPPORTED SSH public key(s):"
        # Print fingerprints for verification
        while IFS= read -r key_line; do
            echo "${key_line}" | ssh-keygen -lf /dev/stdin | sed 's/^/     /'
        done < "${RECIPIENTS_FILE}"

        # Use the cleaned recipients file to encrypt. This is much more reliable.
        age --encrypt --armor --recipients-file "${RECIPIENTS_FILE}" --output "${CHEZMOI_KEYS_DIR}/master_key_ssh.age" "${PLAINTEXT_KEY_PATH}"
        echo "✅ Successfully created '${CHEZMOI_KEYS_DIR}/master_key_ssh.age'"
    fi
    # Clean up the final recipients file
    rm -f "${RECIPIENTS_FILE}"
fi


echo ""
# 3. Encrypt with a passphrase.
if confirm_overwrite "${CHEZMOI_KEYS_DIR}/master_key_passphrase.age"; then
    echo "› Preparing to encrypt with a master password."
    echo "  The 'age' command will now prompt you to enter and confirm the password."

    # Let the `age` command handle its own interactive password prompt directly.
    age --passphrase --armor --output "${CHEZMOI_KEYS_DIR}/master_key_passphrase.age" "${PLAINTEXT_KEY_PATH}"

    echo "✅ Successfully created '${CHEZMOI_KEYS_DIR}/master_key_passphrase.age'"
fi

echo ""
echo "--- Generation Complete ---"
echo "The encrypted key files have been placed directly in your chezmoi source directory."
echo "You can now commit the changes."

#!/usr/bin/env sh
#
# FILENAME: generate_encrypted_keys.sh
#
# This helper script encrypts your master age private key in two ways:
#   1. Encrypted to ALL SSH public keys found in ~/.ssh.
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
    echo "🔎 Searching for SSH public keys in ~/.ssh..."
    RECIPIENTS_FILE=$(mktemp)
    # Find all .pub files and concatenate their contents into the temp file
    find "${HOME}/.ssh" -type f -name "*.pub" -exec cat {} + > "${RECIPIENTS_FILE}"

    if [ ! -s "${RECIPIENTS_FILE}" ]; then
        echo "⚠️ WARNING: No SSH public keys found in ~/.ssh. Skipping SSH-based encryption."
    else
        echo "› Encrypting to all found SSH public keys..."
        # Added the --armor flag here to ensure ASCII output
        age --encrypt --armor --recipients-file "${RECIPIENTS_FILE}" --output "${CHEZMOI_KEYS_DIR}/master_key_ssh.age" "${PLAINTEXT_KEY_PATH}"
        echo "✅ Successfully created '${CHEZMOI_KEYS_DIR}/master_key_ssh.age'"
    fi
    # Clean up the temporary recipients file
    rm -f "${RECIPIENTS_FILE}"
fi


echo ""
# 3. Encrypt with a passphrase.
if confirm_overwrite "${CHEZMOI_KEYS_DIR}/master_key_passphrase.age"; then
    echo "› Preparing to encrypt with a master password."
    echo "  The 'age' command will now prompt you to enter and confirm the password."

    # This command already uses --armor, so it's correct.
    age --passphrase --armor --output "${CHEZMOI_KEYS_DIR}/master_key_passphrase.age" "${PLAINTEXT_KEY_PATH}"

    echo "✅ Successfully created '${CHEZMOI_KEYS_DIR}/master_key_passphrase.age'"
fi

echo ""
echo "--- Generation Complete ---"
echo "The encrypted key files have been placed directly in your chezmoi source directory."
echo "You can now commit the changes."

#!/usr/bin/env sh
#
# FILENAME: generate-encrypted-keys.sh
#
# This helper script encrypts your master age private key with a symmetric
# master password, producing master_key_passphrase.age in the chezmoi source
# tree. This is the file setup-age-key.sh uses to bootstrap new machines.
#
# It assumes the unencrypted key is located at ~/.config/age/key.txt.
# It will check if the encrypted key already exists and ask before overwriting.

set -e

# --- Configuration ---
# Assume the unencrypted private key is always at this location.
PLAINTEXT_KEY_PATH="${HOME}/.config/age/key.txt"
# Define the final destination for the generated key inside the chezmoi source tree
CHEZMOI_KEYS_DIR="$(chezmoi source-path)/private_dot_config/private_age"

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
# 2. Encrypt with a passphrase.
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

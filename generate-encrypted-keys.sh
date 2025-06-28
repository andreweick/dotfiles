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

    # Create an array of "-r <key>" arguments for the age command
    age_args=""
    all_keys=""

    # Gather keys from all common locations into a temporary file
    TMP_KEYS_FILE=$(mktemp)
    find "${SSH_DIR}" -type f -name "*.pub" -exec cat {} + >> "${TMP_KEYS_FILE}" 2>/dev/null || true
    [ -f "${SSH_DIR}/authorized_keys" ] && cat "${SSH_DIR}/authorized_keys" >> "${TMP_KEYS_FILE}"
    [ -f "${SSH_DIR}/ignition" ] && cat "${SSH_DIR}/ignition" >> "${TMP_KEYS_FILE}"
    [ -d "${SSH_DIR}/authorized_keys.d" ] && find "${SSH_DIR}/authorized_keys.d" -type f -exec cat {} + >> "${TMP_KEYS_FILE}" 2>/dev/null || true

    # Filter out unsupported ecdsa keys and de-duplicate
    # This is the crucial fix to prevent the "unknown recipient" error
    all_keys=$(grep -v "ecdsa-sha2-nistp256" "${TMP_KEYS_FILE}" | sort -u)
    rm -f "${TMP_KEYS_FILE}"

    if [ -z "${all_keys}" ]; then
        echo "⚠️ WARNING: No SUPPORTED SSH public keys found. Skipping SSH-based encryption."
    else
        echo "› Preparing to encrypt to the following SUPPORTED SSH public key(s):"
        # Build the arguments and print fingerprints
        while IFS= read -r key_line; do
            case "$key_line" in ""|\#*) continue ;; esac
            echo "${key_line}" | ssh-keygen -lf /dev/stdin | sed 's/^/     /'
            # Add the key as a recipient argument
            age_args="${age_args} -r '${key_line}'"
        done <<EOF
${all_keys}
EOF

        # Use eval to correctly handle the quoted arguments. It's safe here as we control the input.
        eval "age --encrypt --armor ${age_args} --output '${CHEZMOI_KEYS_DIR}/master_key_ssh.age' '${PLAINTEXT_KEY_PATH}'"
        echo "✅ Successfully created '${CHEZMOI_KEYS_DIR}/master_key_ssh.age'"
    fi
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

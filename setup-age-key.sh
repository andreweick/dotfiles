#!/usr/bin/env sh
#
# FILENAME: setup_age_key.sh
#
# This script intelligently bootstraps the master age key. It first attempts
# to decrypt using available SSH keys. If that fails, it falls back to
# prompting for a master password. It will ask for confirmation before
# overwriting an existing key file.
#
# Run this once on any new machine.

set -e

# --- Determine script's own directory to make it runnable from anywhere ---
SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

# --- Configuration ---
# The final destination for your decrypted age private key.
KEY_DESTINATION="${HOME}/.config/age/key.txt"

# The path to your SSH-encrypted master age key file.
ENCRYPTED_KEY_SSH="${SCRIPT_DIR}/private_dot_config/age/master_key_ssh.age"

# The path to your passphrase-encrypted master age key file.
ENCRYPTED_KEY_PASSPHRASE="${SCRIPT_DIR}/private_dot_config/age/master_key_passphrase.age"


# --- Script Logic ---

# 1. Check if the final key already exists and ask to overwrite.
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

# 2. Ensure the destination directory exists.
mkdir -p "$(dirname "${KEY_DESTINATION}")"

# 3. Method 1: Attempt decryption with SSH keys if an agent is available.
DECRYPTION_SUCCESSFUL=false
if [ -n "$SSH_AUTH_SOCK" ] && [ -f "${ENCRYPTED_KEY_SSH}" ]; then
    echo "🔐 Step 1: SSH agent detected. Attempting decryption with SSH keys..."
    # Find all files in ~/.ssh that do not end in .pub
    for key_path in $(find "${HOME}/.ssh" -type f -not -name "*.pub"); do
        echo "   › Trying key: ${key_path}"
        if age --decrypt --identity "${key_path}" --output /dev/null "${ENCRYPTED_KEY_SSH}" >/dev/null 2>&1; then
            age --decrypt --identity "${key_path}" --output "${KEY_DESTINATION}" "${ENCRYPTED_KEY_SSH}"
            DECRYPTION_SUCCESSFUL=true
            echo "   ✔ Success with SSH key: ${key_path}"
            break
        fi
    done
else
    echo "ℹ️ Step 1: SSH agent not forwarded or SSH key file not found. Skipping."
fi

# 4. Method 2: If SSH failed, fall back to passphrase.
if [ "$DECRYPTION_SUCCESSFUL" = "false" ]; then
    echo "🔐 Step 2: Falling back to master password..."
    if [ -f "${ENCRYPTED_KEY_PASSPHRASE}" ]; then
        printf "Enter Master Password: "
        stty -echo
        read PASSPHRASE
        stty echo
        printf "\n"

        if [ -n "${PASSPHRASE}" ]; then
            if printf "%s" "${PASSPHRASE}" | age --decrypt --output "${KEY_DESTINATION}" "${ENCRYPTED_KEY_PASSPHRASE}" >/dev/null 2>&1; then
                DECRYPTION_SUCCESSFUL=true
                echo "   ✔ Success with master password."
            fi
        fi
    else
        echo "   › Passphrase-encrypted key file not found. Skipping."
    fi
fi

# 5. Check if any method succeeded and handle errors.
if [ "$DECRYPTION_SUCCESSFUL" = "false" ]; then
    echo "❌ ERROR: All decryption methods failed."
    echo "   Could not decrypt the master key using any available SSH keys or the provided password."
    exit 1
fi

# 6. Set correct permissions and finish.
chmod 600 "${KEY_DESTINATION}"

echo "✅ Successfully decrypted and placed primary age key at: ${KEY_DESTINATION}"
echo "You can now run 'chezmoi apply'."

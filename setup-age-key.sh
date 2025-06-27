#!/usr/bin/env sh
#
# FILENAME: setup_age_key.sh
#
# This script intelligently bootstraps the master age key. It first attempts
# to decrypt using available SSH keys from the ssh-agent. If that fails, it
# falls back to prompting for a master password.
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

# 3. Method 1: Attempt decryption with keys from the ssh-agent.
DECRYPTION_SUCCESSFUL=false
# Check if an agent is running and has keys loaded.
# `ssh-add -l` returns a non-zero exit code if the agent has no keys.
if [ -n "$SSH_AUTH_SOCK" ] && [ -f "${ENCRYPTED_KEY_SSH}" ] && ssh-add -l >/dev/null 2>&1; then
    echo "🔐 Step 1: SSH agent detected with keys loaded. Attempting decryption..."

    # Use ssh-add -L to get the public keys, which age can use as recipients
    # to find the corresponding private key in the agent.
    # We create a temporary file with all the public keys from the agent.
    AGENT_KEYS_FILE=$(mktemp)
    ssh-add -L > "${AGENT_KEYS_FILE}"

    # We can now attempt decryption using the agent's keys.
    # The `-i -` flag is not used; `age` does this automatically with ssh-agent.
    # We test it first.
    if age --decrypt --recipients-file "${AGENT_KEYS_FILE}" --output /dev/null "${ENCRYPTED_KEY_SSH}" >/dev/null 2>&1; then
        # If the test succeeds, do the real decryption.
        age --decrypt --recipients-file "${AGENT_KEYS_FILE}" --output "${KEY_DESTINATION}" "${ENCRYPTED_KEY_SSH}"
        DECRYPTION_SUCCESSFUL=true
        echo "   ✔ Success with a key from the SSH agent."
    fi
    rm -f "${AGENT_KEYS_FILE}"
else
    echo "ℹ️ Step 1: SSH agent not available or no keys loaded. Skipping."
fi

# 4. Method 2: If SSH failed, fall back to passphrase.
if [ "$DECRYPTION_SUCCESSFUL" = "false" ]; then
    echo "🔐 Step 2: Falling back to master password..."
    if [ -f "${ENCRYPTED_KEY_PASSPHRASE}" ]; then
        echo "   › Please enter your master password when prompted by 'age'."

        if age --decrypt --output "${KEY_DESTINATION}" "${ENCRYPTED_KEY_PASSPHRASE}"; then
            DECRYPTION_SUCCESSFUL=true
            echo "   ✔ Success with master password."
        fi
    else
        echo "   › Passphrase-encrypted key file not found. Skipping."
    fi
fi

# 5. Check if any method succeeded and handle errors.
if [ "$DECRYPTION_SUCCESSFUL" = "false" ]; then
    echo "❌ ERROR: All decryption methods failed."
    echo "   Could not decrypt the master key using any available SSH keys or the provided password."
    rm -f "${KEY_DESTINATION}" >/dev/null 2>&1
    exit 1
fi

# 6. Set correct permissions and finish.
chmod 600 "${KEY_DESTINATION}"

echo "✅ Successfully decrypted and placed primary age key at: ${KEY_DESTINATION}"
echo "You can now run 'chezmoi apply'."

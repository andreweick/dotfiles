#!/usr/bin/env sh
#
# FILENAME: setup_age_key.sh
#
# This script intelligently bootstraps the master age key. It first attempts
# to decrypt using available SSH keys (from an agent or local files). If that
# fails, it falls back to prompting for a master password.
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

# 3. Method 1: Attempt decryption with SSH keys.
DECRYPTION_SUCCESSFUL=false
if [ -f "${ENCRYPTED_KEY_SSH}" ]; then
    echo "🔐 Step 1: Attempting decryption with SSH keys..."

    # --- Debugging: Show available and required keys ---
    if [ -n "$SSH_AUTH_SOCK" ] && ssh-add -l >/dev/null 2>&1; then
        echo "   › Fingerprints of keys available in ssh-agent:"
        ssh-add -l | sed 's/^/     /' # Indent for readability
    else
        echo "   › No active SSH agent found with loaded keys."
    fi

    echo "   › Fingerprints of recipients in the encrypted file:"
    # The age header is plain text. We can awk for the SSH recipient lines
    # and pipe each public key into ssh-keygen to get its fingerprint.
    awk '/^-> ssh-/ { print $2, $3 }' "${ENCRYPTED_KEY_SSH}" | while IFS= read -r key_line; do
        echo "${key_line}" | ssh-keygen -lf /dev/stdin | sed 's/^/     /'
    done
    if ! awk '/^-> ssh-/' "${ENCRYPTED_KEY_SSH}" | grep -q .; then
        echo "     (No SSH recipients found in file)"
    fi
    # --- End Debugging ---

    # Find all potential private keys and try to decrypt with them.
    # `age` will automatically use the agent if the identity path matches a key in the agent.
    for key_path in $(find "${HOME}/.ssh" -type f -not -name "*.pub"); do
        # Silently try to decrypt with the current key
        if age --decrypt --identity "${key_path}" --output "${KEY_DESTINATION}" "${ENCRYPTED_KEY_SSH}" >/dev/null 2>&1; then
            DECRYPTION_SUCCESSFUL=true
            echo "   ✔ Success: Decrypted using identity '${key_path}'"
            break # Exit the loop on the first success
        fi
    done
else
    echo "ℹ️ Step 1: SSH-encrypted key file not found. Skipping."
fi

# 4. Method 2: If SSH failed, fall back to passphrase.
if [ "$DECRYPTION_SUCCESSFUL" = "false" ]; then
    echo "🔐 Step 2: SSH decryption failed. Falling back to master password..."
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

#!/usr/bin/env bash
#
# --- Universal, Context-Aware Homebrew Cleanup Script ---

# First, check if Homebrew is installed. If not, exit gracefully.
if ! command -v brew &> /dev/null; then
    echo "ℹ️  Homebrew not found, skipping package management."
    exit 0
fi

# Define the path to the brewfile.
BREWFILE_PATH="$HOME/.config/brewfile/brewfile.txt"

# --- Safety Check: Exits gracefully if brewfile.txt is not found ---
if [ ! -f "$BREWFILE_PATH" ]; then
    echo "ℹ️  brewfile.txt not found, skipping Homebrew sync for this machine."
    echo "   (Checked path: $BREWFILE_PATH)"
    exit 0 # Exit successfully to allow the rest of chezmoi apply to continue
fi


# Step 1: Install and upgrade all packages defined in the brewfile.
echo "📦 Syncing packages from ~/.config/brewfile/brewfile.txt..."
brew bundle install --quiet --file "$BREWFILE_PATH"

# Step 2: Check for extraneous packages.
echo "🔎 Checking for packages installed but not in your brewfile.txt..."
CHECK_OUTPUT=$(brew bundle check --file "$BREWFILE_PATH" --verbose || true)
EXTRANEOUS_PACKAGES=$(echo "$CHECK_OUTPUT" | sed -n '/not listed in the Brewfile:/,$p' | sed '1d')

# Step 3: If extraneous packages are found, check if we are in an interactive session.
if [ -n "$EXTRANEOUS_PACKAGES" ]; then
    echo
    echo "❗️ Found packages installed that are not in your brewfile.txt:"
    echo "--------------------------------------------------"
    echo "$EXTRANEOUS_PACKAGES"
    echo "--------------------------------------------------"

    # --- CONTEXT-AWARE LOGIC ---
    # Check if standard input is a terminal.
    if [ -t 0 ]; then
        # --- INTERACTIVE MODE ---
        echo
        echo "Choose an action:"
        echo "  [Y]es, remove these packages and continue."
        echo "  [S]kip cleanup for now, but continue with other chezmoi changes."
        echo "  [A]bort the entire 'chezmoi apply' process."
        read -p "Your choice? (Y/S/A) " -n 1 -r REPLY
        echo

        REPLY_LOWER=$(echo "$REPLY" | tr '[:upper:]' '[:lower:]')

        case "$REPLY_LOWER" in
          y)
            echo "🗑️  User approved. Removing unlisted packages..."
            brew bundle cleanup --file "$BREWFILE_PATH" --force
            echo "✅ Cleanup complete. Chezmoi will continue."
            ;;
          s)
            echo "ℹ️  Skipping cleanup as requested. Chezmoi will continue with other tasks."
            ;;
          a)
            echo "🛑 Aborting entire 'chezmoi apply' process as requested."
            exit 1
            ;;
          *)
            echo "🛑 Invalid choice. Aborting for safety."
            exit 1
            ;;
        esac
    else
        # --- NON-INTERACTIVE MODE ---
        echo
        echo " unattended mode. Defaulting to the safest option: skipping cleanup."
        echo "ℹ️  These packages will NOT be removed. Chezmoi will continue."
    fi

else
    echo "✅ Your system is in sync with your brewfile.txt. No cleanup needed."
fi

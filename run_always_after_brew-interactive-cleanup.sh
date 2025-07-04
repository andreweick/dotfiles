#!/usr/bin/env bash

# --- Unified, Intelligent, Dual-Trigger Homebrew Script ---

# --- CONFIGURATION ---
# Set the time period in seconds. Default is 7 days.
readonly CHECK_INTERVAL_SECONDS=$((7 * 24 * 60 * 60))
# Location for the timestamp file.
readonly MARKER_FILE="$HOME/.config/brewfile/brew_last_run"
# Location of the brewfile itself.
readonly BREWFILE_PATH="$HOME/.config/brewfile/brewfile.txt"

# --- INITIAL CHECKS ---
if ! command -v brew &> /dev/null; then
    echo "ℹ️  Homebrew not found, skipping."
    exit 0
fi
if [ ! -f "$BREWFILE_PATH" ]; then
    echo "ℹ️  brewfile.txt not found, skipping."
    exit 0
fi

# --- DUAL-TRIGGER LOGIC ---
# This block decides if the main script logic needs to run.

# Default to not running. We'll set this to true if a condition is met.
SHOULD_RUN=false
RUN_REASON=""

# Helper function to get a file's modification time in seconds.
get_mtime() {
    if [[ "$(uname)" == "Darwin" ]]; then
        date -r "$1" +%s
    else
        date --reference="$1" +%s
    fi
}

# Always run if the timestamp marker file doesn't exist (i.e., first run).
if [ ! -f "$MARKER_FILE" ]; then
    SHOULD_RUN=true
    RUN_REASON="First run, performing initial sync."
else
    # Get the modification times of the brewfile and the last run marker.
    brewfile_mtime=$(get_mtime "$BREWFILE_PATH")
    last_run_mtime=$(get_mtime "$MARKER_FILE")

    # CONDITION 1: Run if brewfile.txt has been changed since the last run.
    if (( brewfile_mtime > last_run_mtime )); then
        SHOULD_RUN=true
        RUN_REASON="brewfile.txt has been modified, re-syncing."
    fi

    # CONDITION 2: Run if the weekly time limit has passed.
    current_time=$(date +%s)
    elapsed_seconds=$((current_time - last_run_mtime))
    if (( elapsed_seconds > CHECK_INTERVAL_SECONDS )); then
        SHOULD_RUN=true
        # Use a more specific reason if the time check is what triggered it.
        if [ -z "$RUN_REASON" ]; then
            RUN_REASON="Periodic weekly check is due."
        fi
    fi
fi

# --- EXECUTION ---
# Based on the logic above, either run the full script or skip.

if [ "$SHOULD_RUN" = true ]; then
    echo "⌛ $RUN_REASON"

    # --- CORE INTERACTIVE SCRIPT ---
    echo "📦 Syncing packages from brewfile.txt..."
    brew bundle install --file "$BREWFILE_PATH" --no-lock --quiet

    echo "🔎 Checking for packages installed but not in your brewfile.txt..."
    CHECK_OUTPUT=$(brew bundle check --file "$BREWFILE_PATH" --verbose || true)
    EXTRANEOUS_PACKAGES=$(echo "$CHECK_OUTPUT" | sed -n '/not listed in the Brewfile:/,$p' | sed '1d')

    if [ -n "$EXTRANEOUS_PACKAGES" ]; then
        echo
        echo "❗️ Found packages installed that are not in your brewfile.txt:"
        echo "--------------------------------------------------"
        echo "$EXTRANEOUS_PACKAGES"
        echo "--------------------------------------------------"

        if [ -t 0 ]; then # Interactive check
            echo
            echo "Choose an action:"
            echo "  [Y]es, remove these packages."
            echo "  [S]kip cleanup, but reset the timer."
            echo "  [A]bort 'chezmoi apply'. Timer will NOT be reset."
            read -p "Your choice? (Y/S/A) " -n 1 -r REPLY
            echo
            REPLY_LOWER=$(echo "$REPLY" | tr '[:upper:]' '[:lower:]')
            case "$REPLY_LOWER" in
              y)
                echo "🗑️  User approved. Removing unlisted packages..."
                brew bundle cleanup --file "$BREWFILE_PATH" --force --quiet
                echo "✅ Cleanup complete."
                ;;
              s)
                echo "ℹ️  Skipping cleanup as requested."
                ;;
              a)
                echo "🛑 Aborting entire 'chezmoi apply' process."
                exit 1
                ;;
              *)
                echo "🛑 Invalid choice. Aborting."
                exit 1
                ;;
            esac
        else # Non-interactive mode
            echo
            echo " unattended mode. Defaulting to skipping cleanup."
        fi
    else
        echo "✅ Your system is in sync with your brewfile.txt."
    fi

    # --- On success, update the timestamp to reset the timer ---
    echo "⏲️  Resetting the periodic timer."
    touch "$MARKER_FILE"

    echo "🎉 Homebrew check complete."
else
    echo "ℹ️  Skipping Homebrew check (up-to-date and last run was recent)."
    exit 0
fi

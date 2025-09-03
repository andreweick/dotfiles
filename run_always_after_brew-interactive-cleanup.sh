#!/usr/bin/env bash

# --- Unified, Intelligent, Dual-Trigger Homebrew Script ---

# --- CONFIGURATION ---
# Set the time period in seconds. Default is 7 days.
readonly CHECK_INTERVAL_SECONDS=$((7 * 24 * 60 * 60))
# Location for the timestamp file.
readonly MARKER_FILE="$HOME/.config/brewfile/brew_last_run.txt"
# Location of the brewfile itself.
readonly BREWFILE_PATH="$HOME/.config/brewfile/brewfile.txt"
# Auto-removal mode: "prompt" (current behavior) or "auto_prompt" (auto-remove with countdown)
readonly AUTO_REMOVE_MODE="auto_prompt"
# Countdown timeout in seconds for auto-removal
readonly AUTO_REMOVE_TIMEOUT=10

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

# CONDITION 0: Force update via environment variable
BREW_FORCE_LOWER=$(echo "$BREW_FORCE_UPDATE" | tr '[:upper:]' '[:lower:]')
if [ "$BREW_FORCE_LOWER" = "1" ] || [ "$BREW_FORCE_LOWER" = "true" ] || [ "$BREW_FORCE_LOWER" = "t" ]; then
    SHOULD_RUN=true
    RUN_REASON="Force update requested via BREW_FORCE_UPDATE environment variable."
fi

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
    brew bundle install --file "$BREWFILE_PATH" --quiet

    echo "🔎 Checking for packages installed but not in your brewfile.txt..."
    # Use brew bundle cleanup (without --force) to detect what would be removed
    CLEANUP_OUTPUT=$(brew bundle cleanup --file "$BREWFILE_PATH" 2>&1 || true)
    # Extract package names - they appear after "formulae:" line and before "Run `brew bundle cleanup --force`"
    EXTRANEOUS_PACKAGES=$(echo "$CLEANUP_OUTPUT" | sed -n '/^Would uninstall formulae:/,/^Run `brew bundle cleanup --force`/p' | grep -v "^Would uninstall formulae:" | grep -v "^Run \`brew bundle cleanup --force\`" | grep -v "^$")

    if [ -n "$EXTRANEOUS_PACKAGES" ]; then
        echo
        echo "❗️ Found packages installed that are not in your brewfile.txt:"
        echo "--------------------------------------------------"
        echo "$EXTRANEOUS_PACKAGES"
        echo "--------------------------------------------------"

        if [ -t 0 ]; then # Interactive check
            if [ "$AUTO_REMOVE_MODE" = "auto_prompt" ]; then
                echo
                # Countdown timer with key press detection
                countdown=$AUTO_REMOVE_TIMEOUT
                user_interrupted=false
                
                while [ $countdown -gt 0 ]; do
                    printf "\r⏱️  Auto-removing in %d seconds... Press any key to cancel " $countdown
                    if read -t 1 -n 1 -s; then
                        user_interrupted=true
                        echo # New line after countdown
                        break
                    fi
                    ((countdown--))
                done
                
                if [ "$user_interrupted" = false ]; then
                    echo # New line after countdown
                    echo "🗑️  Auto-removing unlisted packages..."
                    brew bundle cleanup --file "$BREWFILE_PATH" --force --quiet
                    echo "✅ Cleanup complete."
                else
                    # User interrupted, show full menu
                    echo
                    echo "Choose an action:"
                    echo "  [A]dd these packages to brewfile.txt"
                    echo "  [R]emove these packages"
                    echo "  [S]kip cleanup, but reset the timer"
                    echo "  [X] Abort 'chezmoi apply'. Timer will NOT be reset"
                    read -p "Your choice? (A/R/S/X) " -n 1 -r REPLY
                    echo
                    REPLY_LOWER=$(echo "$REPLY" | tr '[:upper:]' '[:lower:]')
                    case "$REPLY_LOWER" in
                      a)
                        echo "📝 Adding packages to brewfile.txt..."
                        # Convert package names to brew "package" format and append
                        echo "$EXTRANEOUS_PACKAGES" | while read -r pkg; do
                            if [ -n "$pkg" ]; then
                                echo "brew \"$pkg\"" >> "$BREWFILE_PATH"
                            fi
                        done
                        echo "✅ Packages added to brewfile.txt"
                        ;;
                      r)
                        echo "🗑️  Removing unlisted packages..."
                        brew bundle cleanup --file "$BREWFILE_PATH" --force --quiet
                        echo "✅ Cleanup complete."
                        ;;
                      s)
                        echo "ℹ️  Skipping cleanup as requested."
                        ;;
                      x)
                        echo "🛑 Aborting entire 'chezmoi apply' process."
                        exit 1
                        ;;
                      *)
                        echo "🛑 Invalid choice. Aborting."
                        exit 1
                        ;;
                    esac
                fi
            else
                # Original prompt mode
                echo
                echo "Choose an action:"
                echo "  [A]dd these packages to brewfile.txt"
                echo "  [R]emove these packages"
                echo "  [S]kip cleanup, but reset the timer"
                echo "  [X] Abort 'chezmoi apply'. Timer will NOT be reset"
                read -p "Your choice? (A/R/S/X) " -n 1 -r REPLY
                echo
                REPLY_LOWER=$(echo "$REPLY" | tr '[:upper:]' '[:lower:]')
                case "$REPLY_LOWER" in
                  a)
                    echo "📝 Adding packages to brewfile.txt..."
                    # Convert package names to brew "package" format and append
                    echo "$EXTRANEOUS_PACKAGES" | while read -r pkg; do
                        if [ -n "$pkg" ]; then
                            echo "brew \"$pkg\"" >> "$BREWFILE_PATH"
                        fi
                    done
                    echo "✅ Packages added to brewfile.txt"
                    ;;
                  r)
                    echo "🗑️  Removing unlisted packages..."
                    brew bundle cleanup --file "$BREWFILE_PATH" --force --quiet
                    echo "✅ Cleanup complete."
                    ;;
                  s)
                    echo "ℹ️  Skipping cleanup as requested."
                    ;;
                  x)
                    echo "🛑 Aborting entire 'chezmoi apply' process."
                    exit 1
                    ;;
                  *)
                    echo "🛑 Invalid choice. Aborting."
                    exit 1
                    ;;
                esac
            fi
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

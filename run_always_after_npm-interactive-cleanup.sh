#!/usr/bin/env bash

# --- Unified, Intelligent, Dual-Trigger npm Script ---

# --- CONFIGURATION ---
# Set the time period in seconds. Default is 7 days.
readonly CHECK_INTERVAL_SECONDS=$((7 * 24 * 60 * 60))
# Location for the timestamp file.
readonly MARKER_FILE="$HOME/.config/npm/last_run_npm.txt"
# Location of the npmfile itself.
readonly NPMFILE_PATH="$HOME/.config/npm/npmfile.txt"
# Auto-removal mode: "prompt" (current behavior) or "auto_prompt" (auto-remove with countdown)
readonly AUTO_REMOVE_MODE="auto_prompt"
# Countdown timeout in seconds for auto-removal
readonly AUTO_REMOVE_TIMEOUT=10

# --- INITIAL CHECKS ---
if ! command -v npm &> /dev/null; then
    echo "ℹ️  npm not found, skipping."
    exit 0
fi
if [ ! -f "$NPMFILE_PATH" ]; then
    echo "ℹ️  npmfile.txt not found, skipping."
    exit 0
fi

# Check if npmfile.txt has any packages (non-comment, non-empty lines)
PACKAGE_COUNT=$(grep -v '^#' "$NPMFILE_PATH" | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
if [ "$PACKAGE_COUNT" -eq 0 ]; then
    echo "ℹ️  npmfile.txt is empty (no packages listed), skipping."
    exit 0
fi

# --- DUAL-TRIGGER LOGIC ---
# This block decides if the main script logic needs to run.

# Default to not running. We'll set this to true if a condition is met.
SHOULD_RUN=false
RUN_REASON=""

# CONDITION 0: Force update via environment variable
NPM_FORCE_LOWER=$(echo "$NPM_FORCE_UPDATE" | tr '[:upper:]' '[:lower:]')
if [ "$NPM_FORCE_LOWER" = "1" ] || [ "$NPM_FORCE_LOWER" = "true" ] || [ "$NPM_FORCE_LOWER" = "t" ]; then
    SHOULD_RUN=true
    RUN_REASON="Force update requested via NPM_FORCE_UPDATE environment variable."
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
    # Get the modification times of the npmfile and the last run marker.
    npmfile_mtime=$(get_mtime "$NPMFILE_PATH")
    last_run_mtime=$(get_mtime "$MARKER_FILE")

    # CONDITION 1: Run if npmfile.txt has been changed since the last run.
    if (( npmfile_mtime > last_run_mtime )); then
        SHOULD_RUN=true
        RUN_REASON="npmfile.txt has been modified, re-syncing."
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
    echo "📦 Installing npm packages from npmfile.txt..."

    # Install packages from npmfile.txt (npm install -g is idempotent)
    while IFS= read -r package || [ -n "$package" ]; do
        # Skip comments and empty lines
        if [[ "$package" =~ ^[[:space:]]*# ]] || [[ -z "${package// }" ]]; then
            continue
        fi
        # Trim whitespace
        package=$(echo "$package" | xargs)
        if [ -n "$package" ]; then
            echo "  📥 Installing $package..."
            npm install -g "$package" --quiet 2>&1 | grep -v "^npm WARN" || true
        fi
    done < "$NPMFILE_PATH"

    echo "🔎 Checking for packages installed globally but not in your npmfile.txt..."

    # Get list of globally installed packages
    INSTALLED_JSON=$(npm list -g --depth=0 --json 2>/dev/null || echo '{"dependencies":{}}')
    INSTALLED_PACKAGES=$(echo "$INSTALLED_JSON" | grep -o '"[^"]*":' | grep -v '"dependencies":' | sed 's/"//g' | sed 's/://g' | sort)

    # Get list of packages from npmfile.txt
    EXPECTED_PACKAGES=$(grep -v '^#' "$NPMFILE_PATH" | grep -v '^[[:space:]]*$' | sed 's/[[:space:]]*//g' | sort)

    # Find packages that are installed but not in npmfile.txt
    # Also filter out npm itself and common system packages
    EXTRANEOUS_PACKAGES=""
    while IFS= read -r pkg; do
        if [ -n "$pkg" ] && [ "$pkg" != "npm" ] && ! echo "$EXPECTED_PACKAGES" | grep -q "^${pkg}$"; then
            if [ -z "$EXTRANEOUS_PACKAGES" ]; then
                EXTRANEOUS_PACKAGES="$pkg"
            else
                EXTRANEOUS_PACKAGES="$EXTRANEOUS_PACKAGES"$'\n'"$pkg"
            fi
        fi
    done <<< "$INSTALLED_PACKAGES"

    if [ -n "$EXTRANEOUS_PACKAGES" ]; then
        echo
        echo "❗️ Found packages installed globally that are not in your npmfile.txt:"
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
                    printf "\r⏱️  Skipping auto-remove in %d seconds... Press any key to select options (CTRL+C doesn't work!) " $countdown
                    if read -t 1 -n 1 -s; then
                        user_interrupted=true
                        echo # New line after countdown
                        break
                    fi
                    ((countdown--))
                done

                if [ "$user_interrupted" = false ]; then
                    echo # New line after countdown
                    echo "ℹ️  Skipping cleanup as requested."
                else
                    # User interrupted, show full menu
                    echo
                    echo "Choose an action:"
                    echo "  [A]dd these packages to npmfile.txt"
                    echo "  [R]emove these packages"
                    echo "  [S]kip cleanup, but reset the timer"
                    echo "  [X] Abort 'chezmoi apply'. Timer will NOT be reset"
                    read -p "Your choice? (A/R/S/X) " -n 1 -r REPLY
                    echo
                    REPLY_LOWER=$(echo "$REPLY" | tr '[:upper:]' '[:lower:]')
                    case "$REPLY_LOWER" in
                      a)
                        echo "📝 Adding packages to npmfile.txt..."
                        echo "$EXTRANEOUS_PACKAGES" | while IFS= read -r pkg; do
                            if [ -n "$pkg" ]; then
                                echo "$pkg" >> "$NPMFILE_PATH"
                            fi
                        done
                        echo "✅ Packages added to npmfile.txt"
                        ;;
                      r)
                        echo "🗑️  Removing unlisted packages..."
                        echo "$EXTRANEOUS_PACKAGES" | while IFS= read -r pkg; do
                            if [ -n "$pkg" ]; then
                                echo "  🗑️  Removing $pkg..."
                                npm uninstall -g "$pkg" --quiet 2>&1 | grep -v "^npm WARN" || true
                            fi
                        done
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
                echo "  [A]dd these packages to npmfile.txt"
                echo "  [R]emove these packages"
                echo "  [S]kip cleanup, but reset the timer"
                echo "  [X] Abort 'chezmoi apply'. Timer will NOT be reset"
                read -p "Your choice? (A/R/S/X) " -n 1 -r REPLY
                echo
                REPLY_LOWER=$(echo "$REPLY" | tr '[:upper:]' '[:lower:]')
                case "$REPLY_LOWER" in
                  a)
                    echo "📝 Adding packages to npmfile.txt..."
                    echo "$EXTRANEOUS_PACKAGES" | while IFS= read -r pkg; do
                        if [ -n "$pkg" ]; then
                            echo "$pkg" >> "$NPMFILE_PATH"
                        fi
                    done
                    echo "✅ Packages added to npmfile.txt"
                    ;;
                  r)
                    echo "🗑️  Removing unlisted packages..."
                    echo "$EXTRANEOUS_PACKAGES" | while IFS= read -r pkg; do
                        if [ -n "$pkg" ]; then
                            echo "  🗑️  Removing $pkg..."
                            npm uninstall -g "$pkg" --quiet 2>&1 | grep -v "^npm WARN" || true
                        fi
                    done
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
            echo "ℹ️  Running in unattended mode. Defaulting to skipping cleanup."
        fi
    else
        echo "✅ Your system is in sync with your npmfile.txt."
    fi

    # --- On success, update the timestamp to reset the timer ---
    echo "⏲️  Resetting the periodic timer."
    mkdir -p "$(dirname "$MARKER_FILE")"
    touch "$MARKER_FILE"

    echo "🎉 npm check complete."
else
    echo "ℹ️  Skipping npm check (up-to-date and last run was recent)."
    exit 0
fi

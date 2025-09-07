#!/usr/bin/env sh
# Dracula-themed chooser for just
# Falls back: gum -> fzf -> simple select

# Handle interrupts gracefully - exit cleanly on Ctrl-C
trap 'exit 0' INT TERM

# Dracula theme colors
PURPLE="#BD93F9"
CYAN="#8BE9FD"
GREEN="#50FA7B"
ORANGE="#FFB86C"
GRAY="#6272A4"
FG="#F8F8F2"
BG="#44475A"

if command -v gum >/dev/null 2>&1; then
    # Use gum filter for fuzzy search functionality
    # Read stdin (the recipe list from just) and pass to gum filter
    # Use exec to replace the shell process completely
    exec gum filter \
        --height 20 \
        --indicator "  " \
        --indicator.foreground "$PURPLE" \
        --cursor-text.foreground "$CYAN" \
        --header "🦇 Select a recipe (type to filter)" \
        --header.foreground "$GREEN" \
        --placeholder "Type to filter..." \
        --fuzzy

elif command -v fzf >/dev/null 2>&1; then
    # Use fzf with Dracula colors and preview
    # Use exec to replace the shell process completely
    exec fzf \
        --height 60% \
        --reverse \
        --preview "just --show {} 2>/dev/null || echo 'Recipe: {}'" \
        --preview-window right:50%:wrap \
        --header "🦇 Select a recipe" \
        --pointer "  " \
        --prompt "  " \
        --color "pointer:$PURPLE,header:$GREEN,info:$CYAN,spinner:$ORANGE,hl:$PURPLE,fg+:$FG,bg+:$BG,hl+:$PURPLE,prompt:$GRAY"

else
    # Last resort: simple select with numbered menu
    echo "No chooser found (install gum or fzf for better experience)" >&2
    echo "Available recipes:" >&2
    # Read input, skip headers, extract recipe names
    i=1
    while IFS= read -r line; do
        # Skip empty lines and header lines
        case "$line" in
            "Available recipes:"*|"") continue ;;
        esac

        # Check if line starts with whitespace (actual recipe)
        if echo "$line" | grep -q '^[[:space:]]'; then
            # Extract recipe name (first word after stripping whitespace)
            recipe=$(echo "$line" | sed 's/^[[:space:]]*//' | cut -d' ' -f1)
            # Skip if empty after processing
            [ -z "$recipe" ] && continue
        else
            continue
        fi

        eval "recipe_$i=\"\$recipe\""
        printf "%2d) %s\n" "$i" "$recipe" >&2
        i=$((i + 1))
    done

    # Check if we found any recipes
    if [ "$i" -eq 1 ]; then
        echo "No recipes found" >&2
        exit 1
    fi

    # Add quit option
    printf "%2d) %s\n" "$i" "quit" >&2

    # Get user selection
    printf "Select recipe (1-%d): " "$i" >&2
    read -r choice </dev/tty

    # Validate and output selection
    if [ -n "$choice" ] && [ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "$i" ] 2>/dev/null; then
        if [ "$choice" -eq "$i" ]; then
            # User selected quit option
            exit 0
        else
            eval "echo \"\$recipe_$choice\""
        fi
    else
        echo "Invalid selection" >&2
        exit 1
    fi
fi
#!/usr/bin/env sh
# Simple chooser for just
# Priority: gum -> fzf -> default just chooser

# Dracula theme colors
PURPLE="#BD93F9"
CYAN="#8BE9FD"
GREEN="#50FA7B"
ORANGE="#FFB86C"
GRAY="#6272A4"
FG="#F8F8F2"
BG="#44475A"

if command -v gum >/dev/null 2>&1; then
    # Use gum filter for fuzzy search
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
    # No chooser available - just will use its default behavior
    exit 127
fi


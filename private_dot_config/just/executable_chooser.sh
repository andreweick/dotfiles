#!/usr/bin/env sh
# Simple chooser for just
# Priority order can be controlled with JUST_CHOOSER_PRIORITY environment variable
# Default: gum -> fzf -> default just chooser
# Example: JUST_CHOOSER_PRIORITY="fzf,gum" to prefer fzf first

# Chooser priority (comma-separated list)
JUST_CHOOSER_PRIORITY="${JUST_CHOOSER_PRIORITY:-fzf,gum}"

# Dracula theme colors
PURPLE="#BD93F9"
CYAN="#8BE9FD"
GREEN="#50FA7B"
ORANGE="#FFB86C"
GRAY="#6272A4"
FG="#F8F8F2"
BG="#44475A"

# Function to run gum chooser
run_gum() {
    exec gum filter \
        --height 20 \
        --indicator "  " \
        --indicator.foreground "$PURPLE" \
        --cursor-text.foreground "$CYAN" \
        --header "🦇 Select a recipe (type to filter)" \
        --header.foreground "$GREEN" \
        --placeholder "Type to filter..." \
        --fuzzy
}

# Function to run fzf chooser
run_fzf() {
    exec fzf \
        --height 60% \
        --reverse \
        --preview "just --show {} 2>/dev/null || echo 'Recipe: {}'" \
        --preview-window right:50%:wrap \
        --header "🦇 Select a recipe" \
        --pointer "  " \
        --prompt "  " \
        --color "pointer:$PURPLE,header:$GREEN,info:$CYAN,spinner:$ORANGE,hl:$PURPLE,fg+:$FG,bg+:$BG,hl+:$PURPLE,prompt:$GRAY"
}

# Try choosers in priority order
IFS=',' read -r chooser1 chooser2 <<EOF
$JUST_CHOOSER_PRIORITY
EOF

for chooser in $chooser1 $chooser2; do
    case "$chooser" in
        gum)
            if command -v gum >/dev/null 2>&1; then
                run_gum
            fi
            ;;
        fzf)
            if command -v fzf >/dev/null 2>&1; then
                run_fzf
            fi
            ;;
    esac
done

# No chooser available - just will use its default behavior
exit 127


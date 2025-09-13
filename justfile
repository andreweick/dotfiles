# Dotfiles management with chezmoi

# Default recipe - shows interactive chooser when just running 'just'
default:
    @just --choose

# Exit without doing anything (for chooser menu)
quit:
    @echo "👋 Exiting..."

# Apply chezmoi changes to system
df-apply:
    chezmoi apply

# Pull from git and apply changes
df-update:
    chezmoi update

# Show chezmoi status and diff
status:
    chezmoi status

# Edit an encrypted file
edit file:
    chezmoi edit {{ file }}

# Add a new encrypted file
add-encrypted file:
    chezmoi add --encrypt {{ file }}

# Setup age decryption key (run once on new machines)
setup-age-key:
    "$(chezmoi source-path)/setup-age-key.sh"

# Commit changes with message
commit message:
    git add .
    git commit -m "{{ message }}"

# Push to remote repository
push:
    git push

# Force Homebrew update (bypasses weekly timer)
df-brew-force:
    BREW_FORCE_UPDATE=1 chezmoi apply

# Setup Atuin on second machine (login and sync)
atuin-setup:
    atuin login -u maeick
    atuin sync -f

# Check for unpushed git repositories in $HOME/code
check-unpushed:
    #!/bin/bash
    find $HOME/code -type d -name ".git" | while read gitdir; do
        repo=$(dirname "$gitdir")
        cd "$repo"
        if [ -n "$(git log @{u}.. 2>/dev/null)" ]; then
            echo "📤 $(basename "$repo"): has unpushed commits"
        elif ! git rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
            echo "🔗 $(basename "$repo"): no upstream branch set"
        fi
    done

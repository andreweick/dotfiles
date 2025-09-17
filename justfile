# Dotfiles management with chezmoi

# Default recipe - shows interactive chooser when just running 'just'
default:
    -@just --choose || true

# Exit without doing anything (for chooser menu)
quit:
    @echo "👋 Exiting..."

# Apply chezmoi changes to system
czm-apply:
    chezmoi apply

# Pull from git and apply changes
czm-update:
    chezmoi update

# Show chezmoi status and diff
czm-status:
    chezmoi status

# Edit an encrypted file
czm-edit file:
    chezmoi edit {{ file }}

# Add a new encrypted file
czm-add-encrypted file:
    chezmoi add --encrypt {{ file }}

# Setup age decryption key (run once on new machines)
czm-setup-age-key:
    "$(chezmoi source-path)/setup-age-key.sh"

# Force Homebrew update (bypasses weekly timer)
czm-brew-update:
    BREW_FORCE_UPDATE=1 chezmoi apply

# Setup Atuin on second machine (login and sync)
atuin-setup:
    atuin login -u maeick
    atuin sync -f


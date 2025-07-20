# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a dotfiles repository managed by [chezmoi](https://www.chezmoi.io/), designed to manage personal configuration files across multiple machines with secure handling of secrets.

## Essential Commands

### Daily Operations
```sh
# Pull updates from GitHub and apply to local system
chezmoi update

# Apply local changes to system
chezmoi apply

# Edit an encrypted file (automatically re-encrypts on save)
chezmoi edit ~/.config/rclone/secrets.conf
```

### Secret Management
```sh
# Initial setup - decrypt secrets on new machine
./setup-age-key.sh

# Update SSH keys or change master password
./generate-encrypted-keys.sh
```

## Architecture and Structure

### Security Architecture
- Uses `age` encryption for secrets with dual decryption methods:
  - SSH key-based (passwordless with SSH agent forwarding)
  - Master password fallback (stored in 1Password)
- Encrypted files use `.age` extension
- Sensitive configs split into base templates (`.tmpl`) and encrypted secrets

### File Naming Conventions
- `private_`: Files with 0600 permissions
- `dot_`: Becomes `.` in home directory (e.g., `dot_zshrc` → `.zshrc`)
- `.tmpl`: Chezmoi template files
- `.age`: Encrypted files

### Key Scripts
- `setup-age-key.sh`: Bootstrap script for decrypting secrets on new machines
- `generate-encrypted-keys.sh`: Updates encrypted SSH keys or master password
- `run_always_after_brew-interactive-cleanup.sh`: Manages Homebrew packages weekly

### Managed Configurations
- Shell: zsh, git config
- Editor: Neovim (Kickstart-based)
- Terminal: Ghostty, WezTerm, Starship prompt
- Cloud: RClone
- Security: SSH, AWS configs
- History: Atuin
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-grade dotfiles repository managed by [chezmoi](https://www.chezmoi.io/), designed to manage personal configuration files across multiple machines with secure handling of secrets, automatic package synchronization, and two-phase bootstrap support.

## Essential Commands

### Daily Operations
```sh
# Pull updates from GitHub and apply to local system
chezmoi update

# Apply local changes to system
chezmoi apply

# Edit an encrypted file (automatically re-encrypts on save)
chezmoi edit ~/.config/rclone/secrets.conf

# View available automation tasks
just --list
```

### Task Automation (via Just)
```sh
# Chezmoi operations
just czm-apply          # Apply dotfiles
just czm-update         # Update from GitHub
just czm-status         # Check status
just czm-brew-update    # Force Homebrew sync

# Package management
just npm-sync           # Force npm package sync
just npm-update         # Alias for npm-sync

# Media sync operations
just media-sync         # Sync media with checksums
just media-check        # Verify sync integrity

# Repository scanning
just code-status        # Check all ~/code repos for changes
```

### Secret Management
```sh
# Initial setup - decrypt secrets on new machine
./setup-age-key.sh

# Update SSH keys or change master password
./generate-encrypted-keys.sh
```

### Fresh Machine Bootstrap
```sh
# Phase 1: Install chezmoi and apply non-encrypted files
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply andreweick

# Phase 2: Decrypt secrets and apply encrypted files
"$(chezmoi source-path)/setup-age-key.sh"
chezmoi apply
```

## Architecture and Structure

### Security Architecture
- **Dual-tier encryption** using `age`:
  - **Master key** encrypted two ways:
    - SSH key-based (passwordless with SSH agent forwarding)
    - Master password fallback (stored in 1Password)
  - **All secrets** encrypted with master age key
- **Two-phase bootstrap**: Gracefully handles missing encryption keys
  - Phase 1: Non-encrypted files applied
  - Phase 2: After age key setup, encrypted files applied
- **Conditional file handling**: `.chezmoiignore.tmpl` skips encrypted files when key is missing
- **Modular SSH config**: Master config with `Include ~/.ssh/config.d/*.conf` for per-host configs

### File Naming Conventions
- `dot_`: Becomes `.` in home directory (e.g., `dot_zshrc` → `.zshrc`)
- `private_`: Files with 0600 permissions (directories get 0700)
- `executable_`: Files with 0755 permissions
- `create_`: Only create if template produces output (used for conditional completions)
- `.tmpl`: Chezmoi template files (processed with Go templates)
- `.age`: Encrypted files
- `encrypted_`: Prefix for encrypted files
- Combined patterns: `encrypted_private_executable_file.age`

### Key Scripts

**`setup-age-key.sh`** (93 lines)
- Bootstrap age decryption key on new machines
- Method 1 (Primary): SSH key-based decryption (searches `~/.ssh` for available keys)
- Method 2 (Fallback): Master password decryption
- Creates `~/.config/age/key.txt` with 0600 permissions
- Only runs once; asks for confirmation if key already exists

**`generate-encrypted-keys.sh`** (150+ lines)
- Maintain/rotate master encryption keys
- Encrypts master key to ALL SSH public keys (filters out unsupported ECDSA)
- Encrypts master key with passphrase
- De-duplicates recipients
- Asks before overwriting existing files

**`run_always_after_brew-interactive-cleanup.sh`** (200+ lines)
- Smart Homebrew package synchronization daemon
- Dual triggers: Time-based (every 7 days) + Change-based (when brewfile.txt modified)
- Installs packages from `brewfile.txt`
- Detects extraneous packages and offers interactive cleanup
- Auto-prompt mode with 10-second timeout
- Idempotent and safe to run frequently

**`run_always_after_npm-interactive-cleanup.sh`** (250+ lines)
- Smart npm global package synchronization daemon
- Dual triggers: Time-based (every 7 days) + Change-based (when npmfile.txt modified)
- Installs packages from `npmfile.txt` (uses idempotent `npm install -g`)
- Detects extraneous global packages and offers interactive cleanup
- Auto-prompt mode with 10-second timeout
- Safety check: Exits early if npmfile.txt is empty
- Timestamp tracked in `.config/npm/last_run_npm.txt`

**`install.sh`** (24 lines)
- One-liner installation for new machines
- Detects if chezmoi is installed, downloads if needed
- Initializes with `--apply`

### Directory Structure

```
dotfiles/
├── Root Configuration
│   ├── .chezmoi.toml.tmpl           # Chezmoi config (age encryption setup)
│   ├── .chezmoiignore.tmpl          # Conditional file ignore patterns
│   ├── justfile                     # Task automation recipes
│   ├── dot_zshrc.tmpl               # Zsh shell initialization
│   └── dot_gitconfig.tmpl           # Git config (SSH signing, Kaleidoscope)
│
├── Shell Completions
│   └── dot_zsh/completions/         # 11 dynamic completion templates
│
├── Private Configurations
│   ├── private_dot_config/
│   │   ├── age/                     # Master encryption keys (SSH + passphrase)
│   │   ├── atuin/                   # Shell history sync config
│   │   ├── brewfile/                # Homebrew package definitions
│   │   ├── cosign/                  # Container signing keys
│   │   ├── ghostty/                 # Terminal emulator config
│   │   ├── just/                    # Just task runner config + chooser script
│   │   ├── npm/                     # npm global package definitions
│   │   ├── nvim/                    # Neovim (Kickstart-based)
│   │   ├── rclone/                  # Cloud storage/sync config
│   │   ├── starship.toml            # Prompt configuration
│   │   └── wezterm/                 # Terminal emulator config
│   │
│   ├── private_dot_ssh/
│   │   ├── private_config.tmpl      # Master SSH config with Include directives
│   │   ├── private_config.d/        # Modular per-host SSH configs (5 files)
│   │   └── yubi/                    # Encrypted YubiKey SSH keys (8 files)
│   │
│   └── private_dot_aws/
│       └── private_config           # AWS SSO profiles (10+ profiles)
│
└── Documentation
    ├── README.md                    # Comprehensive user guide
    ├── CLAUDE.md                    # Project context for AI assistants
    └── dot_claude/                  # Claude Code configuration
        ├── CLAUDE.md                # AI development guidelines
        └── commands/commit.md       # Git commit workflow
```

### Managed Configurations

**Shell & Environment**
- Zsh with PATH setup, Starship prompt, dynamic completions (11 tools)
- Git with SSH commit signing, Kaleidoscope diff/merge
- Atuin shell history sync (encrypted, cross-machine)
- Zoxide smart directory jumper

**Terminal Emulators**
- Ghostty (Operator Mono SSm font, Ctrl+Grave quick terminal)
- WezTerm (Dracula theme, Operator Mono SSm font)

**Editor**
- Neovim (Kickstart.nvim-based, Lua configuration)

**Task Automation**
- Just task runner with fallback recipe lookup
- Interactive chooser (fzf/gum) for recipe selection
- 15+ recipes for dotfiles, media sync, and repo scanning

**Cloud & Storage**
- RClone (SFTP to 3 hosts: jefferson, pudge, ty)
- AWS CLI (10+ SSO profiles via missionfocus.awsapps.com)

**Security**
- SSH with modular configs (5 host-specific files)
- YubiKey SSH keys (2 YubiKeys: primary + backup, resident + non-resident)
- Cosign for container signing
- Age encryption for secrets (22 encrypted files total)

**Package Management**
- Homebrew with 30+ packages
  - Smart sync daemon (weekly + change detection)
  - Interactive cleanup for extraneous packages
- npm global packages
  - List-based management via `npmfile.txt`
  - Smart sync daemon (weekly + change detection)
  - Interactive cleanup for extraneous packages
  - Idempotent installation (`npm install -g`)

**Key Tools in Brewfile**
- Core: age, sops, chezmoi, cosign, atuin, starship
- Build: node, hugo, tailwindcss, jj, litestream
- Cloud: rclone, flyctl, gh
- Utilities: ripgrep, dust, fzf, gum, zoxide, just
- Desktop: aerospace (window manager)

### Dynamic Shell Completions

11 tools with auto-generated completions using `create_` prefix:
- atuin, chezmoi, cosign, flyctl, gh, gum, hugo, jj, just, podman, rclone
- Only created if tool is installed (uses `lookPath` check)
- Completion scripts generated via `output` function

### Encryption Statistics

- **22 total encrypted files**:
  - 8 YubiKey SSH keys (primary + backup, resident + non-resident)
  - 2 master age keys (SSH + passphrase methods)
  - 2 cloud configs (RClone secrets, Cosign key)
  - 10 licensed fonts (Operator Mono SSm, MonoLisa Variable)

## Important Notes

- **Two-phase bootstrap required**: Run `setup-age-key.sh` before encrypted files are accessible
- **Package sync runs automatically**:
  - Homebrew: Every 7 days or when `brewfile.txt` changes
  - npm: Every 7 days or when `npmfile.txt` changes
- **npm package management**: Add packages to `~/.config/npm/npmfile.txt` (one per line, supports `#` comments)
- **SSH config is modular**: Add new hosts in `private_dot_ssh/private_config.d/`
- **Just recipes for common tasks**: Use `just --list` to see all available commands
- **All secrets stored encrypted**: Never commit unencrypted sensitive files
- **Git commits signed with SSH keys**: OS-specific SSH key used for commit signatures
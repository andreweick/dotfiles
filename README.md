# 🔐 Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

Secrets are encrypted with [age](https://age-encryption.org/). A master key at
`~/.config/age/key.txt` decrypts everything. Until that key exists, `chezmoi
apply` simply skips the encrypted files — so bootstrap is two phases:

1. Apply the non-encrypted config.
2. Install the master key, then apply again to get the secrets.

**Packages:** macOS uses Homebrew (`brewfile.txt`); Linux uses
[mise](https://mise.jdx.dev) (`~/.config/mise/config.toml`). Both sync
automatically (weekly, or when the list changes).

---

## 1. Bootstrap a new box

Installs chezmoi and applies all non-encrypted dotfiles.

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply andreweick
```

If chezmoi is already installed:

```sh
chezmoi init github.com/andreweick/dotfiles --apply
```

Package managers are set up automatically on first apply:
- **macOS** — install Homebrew first: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- **Linux** — mise is installed for you; tools install on the next apply. A tiny
  apt base layer (`zsh`, `git`, `openssh-client`, `curl`, `ca-certificates`,
  `build-essential`) is also installed.

## 2. Bootstrap the key (decrypt secrets)

Run the setup script, enter the master password when prompted, then apply again.

```sh
"$(chezmoi source-path)/setup-age-key.sh"
chezmoi apply
```

> Master password is in 1Password: `op://Private/xcjfxrcih4tzajtsocvlkpjgm4/password`

That's it — encrypted files (SSH keys, rclone/cosign/sops secrets, fonts, etc.)
are now decrypted and in place.

## 3. Pull & update

```sh
chezmoi update        # pull latest from git + apply
chezmoi apply         # apply local changes
chezmoi status        # show what would change
```

Force an immediate package sync (bypass the weekly timer):

```sh
MISE_FORCE_UPDATE=1 chezmoi apply     # Linux
BREW_FORCE_UPDATE=1 chezmoi apply     # macOS
```

---

## Secrets cheat-sheet

```sh
chezmoi edit ~/.config/rclone/secrets.conf      # edit an encrypted file (auto re-encrypts)
chezmoi add --encrypt ~/.config/app/secret.conf # add a new encrypted file
```

Add a package: edit `~/.config/mise/config.toml` (Linux) or
`~/.config/brewfile/brewfile.txt` (macOS), then `chezmoi apply`.

## Maintenance: rotate the master password

On a machine that already has `~/.config/age/key.txt`:

```sh
./generate-encrypted-keys.sh   # re-encrypts the master key with a new password
```

Then commit the updated `private_dot_config/private_age/master_key_passphrase.age`.

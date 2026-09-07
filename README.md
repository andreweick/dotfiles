# 🔐 Dotfiles

Personal dotfiles managed with [chezmoi](https://www.chezmoi.io/).

Secrets are encrypted with [age](https://age-encryption.org/). A master key at
`~/.config/age/key.txt` decrypts everything; until it exists, `chezmoi apply`
skips the encrypted files. The one-command bootstrap below installs that key
*before* the first `chezmoi init`, so a new machine comes up fully decrypted in
a single pass.

**Packages:** macOS uses Homebrew (`brewfile.txt`), synced automatically
(weekly, or when the list changes). Linux has no automated package layer
beyond a small apt base (`aptfile.txt`). [mise](https://mise.jdx.dev) is
installed but carries no global tools — it's used only for per-project tool
pins (see e.g. `~/code/spouterinn/mise.toml`).

---

## 1. Bootstrap a new box (with secrets) — one command

This places the age key **before** `chezmoi init`, so encryption is configured
in a single pass and everything is decrypted. You'll be asked for the master
password once.

```sh
sh -c "$(curl -fsLS https://raw.githubusercontent.com/andreweick/dotfiles/main/bootstrap.sh)"
```

> Master password is in 1Password: `op://Private/xcjfxrcih4tzajtsocvlkpjgm4/password`

That's it — chezmoi is installed, the master key is decrypted to
`~/.config/age/key.txt`, and all secrets (SSH keys, rclone/cosign/sops, fonts)
are applied. Package managers set themselves up on first apply:
- **macOS** — install Homebrew first: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- **Linux** — no automated package installs of any kind right now
  (`aptfile.txt` is empty; see CLAUDE.md).

### Without secrets (or chezmoi already installed)

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply andreweick   # fresh box
chezmoi init github.com/andreweick/dotfiles --apply               # chezmoi already installed
```

This applies only the **non-encrypted** files (encrypted ones are skipped while
the key is absent). To add secrets later, place the key and **re-init** — a
plain `chezmoi apply` will NOT turn encryption on, because the encryption config
is written only at `chezmoi init`:

```sh
"$(chezmoi source-path)/setup-age-key.sh"   # decrypt key into ~/.config/age/key.txt
chezmoi init --apply andreweick             # re-init so the [age] config is generated
```

## 2. Pull & update

```sh
chezmoi update        # pull latest from git + apply
chezmoi apply         # apply local changes
chezmoi status        # show what would change
```

Force an immediate package sync (bypass the weekly timer):

```sh
BREW_FORCE_UPDATE=1 chezmoi apply     # macOS
```

---

## Secrets cheat-sheet

```sh
chezmoi edit ~/.config/rclone/secrets.conf      # edit an encrypted file (auto re-encrypts)
chezmoi add --encrypt ~/.config/app/secret.conf # add a new encrypted file
```

Add a package (macOS): edit `~/.config/brewfile/brewfile.txt`, then
`chezmoi apply`. Linux has no automated package layer beyond `aptfile.txt`.

## Maintenance: rotate the master password

On a machine that already has `~/.config/age/key.txt`:

```sh
./generate-encrypted-keys.sh   # re-encrypts the master key with a new password
```

Then commit the updated `private_dot_config/private_age/master_key_passphrase.age`.

# Dotfiles for

## Installation
Not installed:

```
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply $GITHUB_USERNAME
```

Already installed:

```
chezmoi init github.com/andreweick/dotfiles --apply
```

To add a secret to rclone

```
chezmoi edit ~/.config/rclone/secrets.conf
 ```


## Secret files
To add the secret files to a secure system, run

```sh
"$(chezmoi source-path)/setup-age-key.sh"
```

The password is stored in 1password at "op://Private/xcjfxrcih4tzajtsocvlkpjgm4/password" (Age Encryption Password and Key(s))

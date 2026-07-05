# Dotfiles management with chezmoi

# When a recipe isn't found here, search up the directory tree for it
# Stops at the first justfile without 'set fallback' (usually project root)
set fallback

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

# Golden -> NAS (preserve NAS-only transcode folder)
# Sync media files from Mini Pudge to Jackie2 using checksum for verification
media-sync:
    rclone sync pmcHasher: jackie2Hasher: \
      --checksum --delete-after \
      --exclude '/transcode-hevc-1080p-5bit-movies/**' \
      --exclude '#recycle/**' --exclude '@eaDir/**' --exclude '.DS_Store' \
      --checkers 8 --transfers 2 --stats-one-line


# use rclone check (read-only) with the same excludes, and add --one-way so extra files on the NAS don't count as errors. You don't need --checksum or --delete-after for check
# Verify  media files from Mini Pudge to Jackie2 using checksum for verification
media-check:
    rclone check pmcHasher: jackie2Hasher: \
      --one-way \
      --exclude '/transcode-hevc-1080p-5bit-movies/**' \
      --exclude '#recycle/**' --exclude '@eaDir/**' --exclude '.DS_Store' \
      --checkers 8 --stats-one-line

# Scan all repositories under ~/code and display their status (uncommitted, unpushed, unpulled)
code-git-status SHOW_ALL="":
    #!/usr/bin/env bash
    set -euo pipefail

    # Colors and symbols
    DIRTY_COUNT=0
    UNPUSHED_COUNT=0
    UNPULLED_COUNT=0
    CLEAN_COUNT=0

    gum style --foreground 212 --bold "Scanning repositories in ~/code..."
    echo ""

    # Find all directories that contain .git or .jj
    while IFS= read -r -d '' repo; do
        repo_dir=$(dirname "$repo")
        repo_name=$(basename "$repo_dir")

        # Determine VCS type
        if [[ -d "$repo_dir/.git" ]]; then
            vcs_type="git"
        elif [[ -d "$repo_dir/.jj" ]]; then
            vcs_type="jj"
        else
            continue
        fi

        cd "$repo_dir"

        has_issues=false
        status_lines=()

        if [[ "$vcs_type" == "git" ]]; then
            # Check for uncommitted changes
            if [[ -n $(git status --porcelain) ]]; then
                has_issues=true
                modified=$(git status --porcelain | grep -c "^ M" || true)
                added=$(git status --porcelain | grep -c "^A" || true)
                deleted=$(git status --porcelain | grep -c "^ D" || true)
                untracked=$(git status --porcelain | grep -c "^??" || true)

                status_lines+=("$(gum style --foreground 196 "  🔴 Uncommitted changes:") modified=$modified added=$added deleted=$deleted untracked=$untracked")
                ((DIRTY_COUNT++))
            fi

            # Check for unpushed commits (only if we have a remote)
            if git rev-parse --abbrev-ref @{u} &>/dev/null; then
                unpushed=$(git rev-list @{u}..HEAD --count 2>/dev/null || echo "0")
                if [[ $unpushed -gt 0 ]]; then
                    has_issues=true
                    status_lines+=("$(gum style --foreground 226 "  🟡 Unpushed commits:") $unpushed")
                    ((UNPUSHED_COUNT++))
                fi

                # Check for unpulled commits
                unpulled=$(git rev-list HEAD..@{u} --count 2>/dev/null || echo "0")
                if [[ $unpulled -gt 0 ]]; then
                    has_issues=true
                    status_lines+=("$(gum style --foreground 39 "  🔵 Unpulled commits:") $unpulled")
                    ((UNPULLED_COUNT++))
                fi
            fi
        elif [[ "$vcs_type" == "jj" ]]; then
            # Check for working copy changes
            if ! jj status 2>/dev/null | grep -q "The working copy is clean"; then
                has_issues=true
                status_lines+=("$(gum style --foreground 196 "  🔴 Working copy has changes")")
                ((DIRTY_COUNT++))
            fi

            # Check for unpushed changes (commits not on remote bookmarks)
            unpushed=$(jj log --no-graph -r 'ancestors(.) & ~remote_bookmarks()' -T 'commit_id' 2>/dev/null | wc -l | tr -d ' ')
            if [[ $unpushed -gt 0 ]]; then
                has_issues=true
                status_lines+=("$(gum style --foreground 226 "  🟡 Unpushed changes:") $unpushed commits")
                ((UNPUSHED_COUNT++))
            fi
        fi

        # Display repo status if it has issues or if SHOW_ALL is set
        if [[ $has_issues == true ]]; then
            gum style --foreground 212 --bold --border double --border-foreground 212 --padding "0 1" "$repo_name ($vcs_type)"
            printf '%s\n' "${status_lines[@]}"
            echo ""
        elif [[ -n "{{ SHOW_ALL }}" ]]; then
            ((CLEAN_COUNT++))
            gum style --foreground 46 --bold "$repo_name ($vcs_type)"
            gum style --foreground 46 "  🟢 Clean"
            echo ""
        else
            ((CLEAN_COUNT++))
        fi

    done < <(find ~/code -maxdepth 2 -type d \( -name .git -o -name .jj \) -print0)

    # Summary
    echo ""
    gum style --foreground 212 --bold --border double --border-foreground 212 --padding "0 2" "Summary"
    echo "$(gum style --foreground 196 "Dirty repos:     ") $DIRTY_COUNT"
    echo "$(gum style --foreground 226 "Unpushed repos:  ") $UNPUSHED_COUNT"
    echo "$(gum style --foreground 39 "Unpulled repos:  ") $UNPULLED_COUNT"
    echo "$(gum style --foreground 46 "Clean repos:     ") $CLEAN_COUNT"

# Clean up local branches whose remote tracking branch has been deleted
code-git-cleanup:
    #!/usr/bin/env bash
    set -euo pipefail

    # Temporary file to collect branches
    BRANCHES_FILE=$(mktemp)
    trap "rm -f $BRANCHES_FILE" EXIT

    gum style --foreground 212 --bold "Scanning repositories for orphaned branches..."
    echo ""

    TOTAL_ORPHANED=0

    # Find all git repositories
    while IFS= read -r -d '' repo; do
        repo_dir=$(dirname "$repo")
        repo_name=$(basename "$repo_dir")

        cd "$repo_dir"

        # Find branches where remote tracking branch is gone
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                branch=$(echo "$line" | awk '{print $1}')
                echo "$repo_name|$branch" >> "$BRANCHES_FILE"
                ((TOTAL_ORPHANED++))
            fi
        done < <(git branch -vv | grep ': gone]' || true)

    done < <(find ~/code -maxdepth 2 -type d -name .git -print0)

    if [[ $TOTAL_ORPHANED -eq 0 ]]; then
        gum style --foreground 46 --bold "✨ No orphaned branches found!"
        exit 0
    fi

    # Display message
    gum style --foreground 196 --bold "Found $TOTAL_ORPHANED orphaned branch(es):"
    gum style --foreground 39 "These branches have been found that do not have remote branches"
    echo ""

    # Create list of branches in repo/branch format
    BRANCHES_LIST=$(mktemp)
    trap "rm -f $BRANCHES_LIST" EXIT

    while IFS='|' read -r repo_name branch; do
        echo "$repo_name/$branch"
    done < "$BRANCHES_FILE" > "$BRANCHES_LIST"

    # Create chooser file with branches and action buttons
    CHOOSER_FILE=$(mktemp)
    cat "$BRANCHES_LIST" > "$CHOOSER_FILE"
    echo "✅ Proceed" >> "$CHOOSER_FILE"
    echo "❌ Cancel" >> "$CHOOSER_FILE"

    # Build --selected arguments (all branches + Proceed button pre-selected)
    SELECTED_ARGS=()
    while IFS= read -r branch_entry; do
        SELECTED_ARGS+=("--selected=$branch_entry")
    done < "$BRANCHES_LIST"
    SELECTED_ARGS+=("--selected=✅ Proceed")

    # Let user review and modify selection
    gum style --foreground 39 "Press Enter to proceed, or Space to modify selection:"
    SELECTED=$(gum choose --no-limit --height 15 "${SELECTED_ARGS[@]}" < "$CHOOSER_FILE" || true)

    if [[ -z "$SELECTED" ]] || echo "$SELECTED" | grep -q "❌ Cancel"; then
        gum style --foreground 226 "Cancelled - no branches were deleted"
        exit 0
    fi

    # Check if Proceed was selected
    if ! echo "$SELECTED" | grep -q "✅ Proceed"; then
        gum style --foreground 226 "Cancelled - no branches were deleted (must select Proceed)"
        exit 0
    fi

    DELETED_COUNT=0
    FAILED_COUNT=0

    # Delete selected branches (excluding the Proceed/Cancel buttons)
    while IFS= read -r selected_item; do
        [[ -z "$selected_item" ]] && continue
        [[ "$selected_item" == "✅ Proceed" ]] && continue
        [[ "$selected_item" == "❌ Cancel" ]] && continue

        # Parse repo_name/branch format
        repo_name=$(echo "$selected_item" | cut -d'/' -f1)
        branch=$(echo "$selected_item" | cut -d'/' -f2-)

        repo_dir=$(find ~/code -maxdepth 1 -type d -name "$repo_name" | head -1)
        if [[ -n "$repo_dir" ]]; then
            cd "$repo_dir"
            if git branch -d "$branch" 2>/dev/null; then
                gum style --foreground 46 "✓ Deleted $repo_name/$branch"
                ((DELETED_COUNT++))
            elif git branch -D "$branch" 2>/dev/null; then
                gum style --foreground 226 "⚠ Force deleted $repo_name/$branch (had unmerged changes)"
                ((DELETED_COUNT++))
            else
                gum style --foreground 196 "✗ Failed to delete $repo_name/$branch"
                ((FAILED_COUNT++))
            fi
        fi
    done <<< "$SELECTED"

    echo ""
    gum style --foreground 212 --bold --border double --border-foreground 212 --padding "0 2" "Summary"
    echo "$(gum style --foreground 46 "Deleted:  ") $DELETED_COUNT"
    if [[ $FAILED_COUNT -gt 0 ]]; then
        echo "$(gum style --foreground 196 "Failed:   ") $FAILED_COUNT"
    fi

# ── exe.dev VMs ─────────────────────────────────────────────────────────────
# Provision exe.dev VMs (exeuntu image) at three levels: a bare box, a box with
# your public dotfiles + tools, and upgrading a box to full (decrypted secrets).
# All run from your laptop against the exe.dev CLI (ssh exe.dev …).

# Create a BARE exe.dev VM — plain exeuntu, nothing added: no dotfiles, no
# tools, no secrets. A clean Linux box for throwaway experiments or when you
# don't want your config on it. Optional VM name (auto-generated if omitted).
#   just exe-new-bare          # auto-named
#   just exe-new-bare scratch  # named
exe-new-bare name="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(new)
    [[ -n "{{ name }}" ]] && args+=("--name={{ name }}")
    ssh exe.dev "${args[@]}"

# Create an exe.dev VM with your PUBLIC dotfiles + tools, but NO secrets.
# A first-boot setup script curl-pipes bootstrap.sh in public mode, which
# installs chezmoi, applies the public dotfiles, and runs the mise/apt sync
# daemons to install your CLI toolchain (mise, rg, …). Every encrypted file is
# skipped because no age key is present. Upgrade later with `just exe-decrypt`.
# Optional VM name (auto-generated if omitted).
#   just exe-new            # auto-named
#   just exe-new my-box     # named
exe-new name="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(new)
    [[ -n "{{ name }}" ]] && args+=("--name={{ name }}")
    # The setup script runs once at first boot on the VM. Public mode installs
    # the public dotfiles + toolchain and skips every encrypted file (no key).
    printf '%s\n' \
      '#!/usr/bin/env sh' \
      'export BOOTSTRAP_MODE=public' \
      'sh -c "$(curl -fsLS https://raw.githubusercontent.com/andreweick/dotfiles/main/bootstrap.sh)"' \
      | ssh exe.dev "${args[@]}" --setup-script=/dev/stdin

# Upgrade an existing PUBLIC exe.dev VM to FULL — decrypt secrets on it.
# Runs from your laptop: copies your local age key up over the SSH channel
# (never through the exe.dev control plane), then re-inits chezmoi so the [age]
# block is generated and the encrypted files are decrypted and applied. Only do
# this on VMs you trust as much as this laptop — the key decrypts your whole
# vault. Requires ~/.config/age/key.txt to exist locally.
#   just exe-decrypt my-box
exe-decrypt vm:
    #!/usr/bin/env bash
    set -euo pipefail
    key="$HOME/.config/age/key.txt"
    [[ -f "$key" ]] || { echo "❌ no local age key at $key — nothing to push" >&2; exit 1; }
    host="{{ vm }}.exe.xyz"
    echo "🔐 pushing age key to {{ vm }} and re-initializing chezmoi…"
    ssh "$host" 'mkdir -p ~/.config/age && chmod 700 ~/.config/age'
    scp "$key" "$host:.config/age/key.txt"
    # Why re-`init` an already-initialized chezmoi? Because chezmoi (re)generates
    # its config file (~/.config/chezmoi/chezmoi.toml) from .chezmoi.toml.tmpl
    # ONLY at `init` — never at `apply` or `update`. Our template emits the [age]
    # encryption block only when key.txt exists, so a box first set up in public
    # mode has NO [age] block: chezmoi still thinks it's a public machine and
    # skips every encrypted file. Placing the key isn't enough — you must re-init
    # so the config is regenerated WITH [age]. `init --apply andreweick` does the
    # regen and the apply in one pass. (`andreweick` = the source repo,
    # github.com/andreweick/dotfiles; harmless to re-pass on an initialized box —
    # it just git-pulls the existing source rather than re-cloning.)
    ssh "$host" 'chmod 600 ~/.config/age/key.txt && ~/.local/bin/chezmoi init --apply andreweick'
    echo "✅ {{ vm }} is now a full machine (secrets decrypted)."

# ── ad-hoc SSH transfer (no preconfigured rclone remote) ────────────────────
# rsync/scp-style convenience with rclone's engine, via rclone's on-the-fly
# SFTP connection string — hosts need NOT exist in rclone.conf. Transport is
# delegated to `ssh` (--sftp-ssh ssh), so ~/.ssh/config, config.d, IdentityFile,
# ProxyJump and known_hosts all apply exactly as they would for scp.
#
# The remote side is auto-detected: any arg shaped like [user@]host:/path (has a
# ':') becomes an SFTP remote; a plain path stays local. So the SAME recipe does
# push (local→remote), pull (remote→local), and server→server (both remote).
# Note: server→server streams THROUGH this machine (SFTP has no server-side copy).

# Copy files to/from/between SSH hosts. Additive — never deletes on the dest.
# DRY-RUN BY DEFAULT; pass `--go` to actually transfer.
#   just rclone-copy ~/file.txt          andy@host:/tmp/            # push (preview)
#   just rclone-copy ~/file.txt          andy@host:/tmp/ --go       # push (real)
#   just rclone-copy andy@host:/srv/data ~/backup/ --go             # pull
#   just rclone-copy andy@s1:/data       andy@s2:/data --go         # server→server
rclone-copy src dest *EXTRA:
    #!/usr/bin/env bash
    set -euo pipefail

    # Turn "[user@]host:/path" into an on-the-fly SFTP remote; leave locals alone.
    remotify() {
        local a="$1"
        [[ "$a" != *:* ]] && { printf '%s' "$a"; return; }   # local path, unchanged
        local hostpart="${a%%:*}" path="${a#*:}"
        if [[ "$hostpart" == *@* ]]; then
            printf ':sftp,host=%s,user=%s:%s' "${hostpart#*@}" "${hostpart%@*}" "$path"
        else
            printf ':sftp,host=%s:%s' "$hostpart" "$path"
        fi
    }
    SRC="$(remotify "{{ src }}")"
    DST="$(remotify "{{ dest }}")"

    # --go toggles real execution; everything else passes through to rclone.
    dryrun="--dry-run"; pass=()
    for a in {{ EXTRA }}; do
        if [[ "$a" == "--go" ]]; then dryrun=""; else pass+=("$a"); fi
    done
    [[ -n "$dryrun" ]] && echo "🌵 DRY RUN — add --go to transfer for real"

    rclone copy "$SRC" "$DST" \
      --sftp-ssh ssh --progress $dryrun ${pass[@]+"${pass[@]}"}

# Mirror src onto dest across SSH — DESTRUCTIVE: files on dest that aren't in
# src are DELETED. Same auto-detect + connection-string trick as rclone-copy.
# DRY-RUN BY DEFAULT — the preview lists what it would delete; review it, then
# pass `--go` to commit.
#   just rclone-sync ~/dir/        andy@host:/srv/data          # preview + deletes
#   just rclone-sync ~/dir/        andy@host:/srv/data --go     # commit
rclone-sync src dest *EXTRA:
    #!/usr/bin/env bash
    set -euo pipefail

    remotify() {
        local a="$1"
        [[ "$a" != *:* ]] && { printf '%s' "$a"; return; }
        local hostpart="${a%%:*}" path="${a#*:}"
        if [[ "$hostpart" == *@* ]]; then
            printf ':sftp,host=%s,user=%s:%s' "${hostpart#*@}" "${hostpart%@*}" "$path"
        else
            printf ':sftp,host=%s:%s' "$hostpart" "$path"
        fi
    }
    SRC="$(remotify "{{ src }}")"
    DST="$(remotify "{{ dest }}")"

    dryrun="--dry-run"; pass=()
    for a in {{ EXTRA }}; do
        if [[ "$a" == "--go" ]]; then dryrun=""; else pass+=("$a"); fi
    done

    gum style --foreground 196 --bold --border double --border-foreground 196 --padding "0 2" \
      "⚠️  rclone sync is DESTRUCTIVE — extra files on the destination will be DELETED"
    [[ -n "$dryrun" ]] && echo "🌵 DRY RUN — review the deletes below, then add --go to commit"

    rclone sync "$SRC" "$DST" \
      --sftp-ssh ssh --progress $dryrun ${pass[@]+"${pass[@]}"}

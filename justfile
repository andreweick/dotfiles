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
code-status SHOW_ALL="":
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

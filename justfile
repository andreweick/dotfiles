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
      --checkers 4 --transfers 2 --stats-one-line


# use rclone check (read-only) with the same excludes, and add --one-way so extra files on the NAS don't count as errors. You don't need --checksum or --delete-after for check
# Verify  media files from Mini Pudge to Jackie2 using checksum for verification
media-check:
    rclone check pmcHasher: jackie2Hasher: \
      --one-way \
      --exclude '/transcode-hevc-1080p-5bit-movies/**' \
      --exclude '#recycle/**' --exclude '@eaDir/**' --exclude '.DS_Store' \
      --checkers 4 --stats-one-line

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

# Delete stale local + remote git branches, age-driven and PR-aware. Non-interactive.
#
# DRY-RUN BY DEFAULT — prints what it WOULD delete and touches nothing. Add `--go`
# to actually delete (locals via git branch -d/-D, remotes via git push --delete).
# The staleness knob is `--age=N` days (default 30): branches merged into the default
# branch are always deletable; UNMERGED branches are deleted only once their tip is
# older than N days. With no target it walks every repo under ~/code; pass a repo
# name (under ~/code) or a path to scope to one.
#
# PROTECTED (never deleted): the default branch, the current branch, main/master/
# develop, renovate/* branches, and any branch with an OPEN GitHub PR. Open-PR
# protection needs `gh` authed against a github.com origin; without it a repo runs in
# a conservative fallback where REMOTE deletes are limited to merged-only (local
# deletes still follow the age rule — they're reflog-recoverable).
#
# Note: `git fetch --prune` runs per repo (even in dry-run) for an accurate picture.
# Squash/rebase-merged branches don't read as merged, so they're cleaned via the age
# rule rather than the merge check. GitHub remote deletions are recoverable ~90 days.
#   just code-git-cleanup                    # dry-run, all ~/code repos, age=30
#   just code-git-cleanup --go               # execute, all repos
#   just code-git-cleanup spouterinn         # dry-run, just ~/code/spouterinn
#   just code-git-cleanup spouterinn --go    # execute, single repo
#   just code-git-cleanup --age=60 --go      # execute, 60-day staleness threshold
[arg("ARGS", help="--go = delete for real (default: dry-run); --age=N = staleness in days (default 30); a bare name/path = single repo, else all ~/code")]
code-git-cleanup *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail

    # ── parse args (flags + optional target, any order) ──────────────────────
    LIVE=0; AGE=30; TARGET=""; want_age=0
    for a in {{ ARGS }}; do
        if [[ $want_age -eq 1 ]]; then AGE="$a"; want_age=0; continue; fi
        case "$a" in
            --go)    LIVE=1 ;;
            --age=*) AGE="${a#--age=}" ;;
            --age)   want_age=1 ;;
            --*)     echo "✋ unknown flag: $a" >&2; exit 2 ;;
            *)       TARGET="$a" ;;
        esac
    done
    [[ "$AGE" =~ ^[0-9]+$ ]] || { echo "✋ --age must be a whole number of days" >&2; exit 2; }
    THRESH=$(( AGE * 86400 ))
    NOW=$(date +%s)

    if [[ $LIVE -eq 0 ]]; then
        gum style --foreground 46 --bold --border double --border-foreground 46 --padding "0 2" \
          "🌵 DRY RUN — nothing will be deleted. Add --go to run for real. (age=${AGE}d)"
    fi

    # ── resolve which repos to process ───────────────────────────────────────
    REPOS=()
    if [[ -n "$TARGET" ]]; then
        case "$TARGET" in
            "~/"*)       dir="$HOME/${TARGET#\~/}" ;;
            /*|./*|../*) dir="$TARGET" ;;
            */*)         dir="$TARGET" ;;
            *)           dir="$HOME/code/$TARGET" ;;
        esac
        [[ -d "$dir/.git" ]] || { echo "✋ not a git repo: $dir" >&2; exit 1; }
        REPOS+=("$dir")
    else
        while IFS= read -r -d '' g; do REPOS+=("$(dirname "$g")"); done \
            < <(find ~/code -maxdepth 2 -type d -name .git -print0)
    fi

    # running totals (global — process_repo updates them via dynamic scope)
    T_LOCAL=0; T_REMOTE=0; T_FAIL=0

    process_repo() {
        local dir="$1" name; name="$(basename "$dir")"
        # pushd/popd (not a subshell) so the T_* totals still accumulate in this
        # shell, while the caller's cwd survives the walk.
        pushd "$dir" >/dev/null

        # Refresh remote-tracking refs + prune dead ones (read-only, needed for
        # accurate merged/stale calls). Non-fatal if offline / no remote.
        git fetch --prune --quiet 2>/dev/null || true

        # Default branch: origin/HEAD, else first existing of main/master/develop.
        local def
        def="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
        if [[ -z "$def" ]]; then
            local c
            for c in main master develop; do
                if git show-ref --verify --quiet "refs/remotes/origin/$c" \
                   || git show-ref --verify --quiet "refs/heads/$c"; then def="$c"; break; fi
            done
        fi
        [[ -z "$def" ]] && def="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"

        local cur; cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

        # Merge target: prefer origin/<def>, fall back to the local branch.
        local mergebase="origin/$def"
        git show-ref --verify --quiet "refs/remotes/origin/$def" || mergebase="$def"

        # GitHub open-PR protection (needs gh authed against a github.com origin).
        local origin_url has_origin=0 gh_ok=0
        origin_url="$(git remote get-url origin 2>/dev/null || echo "")"
        [[ -n "$origin_url" ]] && has_origin=1
        # Open-PR branch set as a \n-delimited string (bash 3.2 has no assoc arrays).
        local OPENPR=$'\n'
        if [[ "$origin_url" == *github.com* ]] && command -v gh >/dev/null 2>&1 \
           && gh auth status >/dev/null 2>&1; then
            gh_ok=1
            local b
            while IFS= read -r b; do [[ -n "$b" ]] && OPENPR="${OPENPR}${b}"$'\n'; done \
                < <(gh pr list --state open --limit 500 --json headRefName -q '.[].headRefName' 2>/dev/null || true)
        fi

        # Why a branch is protected (echoes reason, or empty if deletable).
        protect_reason() {
            case "$1" in
                "$def")              echo "default";  return ;;
                "$cur")              echo "current";  return ;;
                main|master|develop) echo "base";     return ;;
                renovate/*)          echo "renovate"; return ;;
            esac
            [[ "$OPENPR" == *$'\n'"$1"$'\n'* ]] && { echo "open-PR"; return; }
            echo ""
        }

        local header_shown=0
        emit_header() {
            [[ $header_shown -eq 1 ]] && return
            gum style --foreground 212 --bold --border double --border-foreground 212 \
              --padding "0 1" "$name  (default: $def)"
            header_shown=1
        }

        # ── local branches ───────────────────────────────────────────────────
        local b ts pr merged stale agedays
        while read -r b ts; do
            [[ -z "$b" || "$b" == "HEAD" ]] && continue
            pr="$(protect_reason "$b")"
            if [[ -n "$pr" ]]; then
                if [[ $LIVE -eq 0 && ( "$pr" == "open-PR" || "$pr" == "renovate" ) ]]; then
                    emit_header; gum style --foreground 244 "  local  $b  → kept ($pr)"
                fi
                continue
            fi
            merged=0; stale=0
            git merge-base --is-ancestor "$b" "$mergebase" 2>/dev/null && merged=1
            agedays=$(( (NOW - ts) / 86400 ))
            (( NOW - ts > THRESH )) && stale=1
            if [[ $merged -eq 1 ]]; then
                emit_header
                if [[ $LIVE -eq 0 ]]; then
                    gum style --foreground 39 "  local  $b  → would delete (merged)"; T_LOCAL=$((T_LOCAL+1))
                elif git branch -d "$b" 2>/dev/null; then
                    gum style --foreground 46 "  ✓ local  $b deleted (merged)"; T_LOCAL=$((T_LOCAL+1))
                else
                    gum style --foreground 196 "  ✗ local  $b failed"; T_FAIL=$((T_FAIL+1))
                fi
            elif [[ $stale -eq 1 ]]; then
                emit_header
                if [[ $LIVE -eq 0 ]]; then
                    gum style --foreground 39 "  local  $b  → would force-delete (stale ${agedays}d)"; T_LOCAL=$((T_LOCAL+1))
                elif git branch -D "$b" 2>/dev/null; then
                    gum style --foreground 226 "  ✓ local  $b force-deleted (stale ${agedays}d)"; T_LOCAL=$((T_LOCAL+1))
                else
                    gum style --foreground 196 "  ✗ local  $b failed"; T_FAIL=$((T_FAIL+1))
                fi
            fi
        done < <(git for-each-ref --format='%(refname:short) %(committerdate:unix)' refs/heads)

        # ── remote branches (origin) ─────────────────────────────────────────
        local rref del_remote=()
        while read -r rref ts; do
            [[ "$rref" == "origin" ]] && continue          # this is origin/HEAD
            b="${rref#origin/}"
            [[ "$b" == "HEAD" ]] && continue
            pr="$(protect_reason "$b")"
            if [[ -n "$pr" ]]; then
                if [[ $LIVE -eq 0 && ( "$pr" == "open-PR" || "$pr" == "renovate" ) ]]; then
                    emit_header; gum style --foreground 244 "  remote $b  → kept ($pr)"
                fi
                continue
            fi
            merged=0; stale=0
            git merge-base --is-ancestor "$rref" "$mergebase" 2>/dev/null && merged=1
            agedays=$(( (NOW - ts) / 86400 ))
            (( NOW - ts > THRESH )) && stale=1
            local reason=""
            if [[ $merged -eq 1 ]]; then
                reason="merged"
            elif [[ $stale -eq 1 && $gh_ok -eq 1 ]]; then
                reason="stale ${agedays}d"
            else
                continue                                   # recent, or stale w/o PR data
            fi
            emit_header
            if [[ $LIVE -eq 0 ]]; then
                gum style --foreground 39 "  remote $b  → would delete ($reason)"; T_REMOTE=$((T_REMOTE+1))
            else
                del_remote+=("$b")
            fi
        done < <(git for-each-ref --format='%(refname:short) %(committerdate:unix)' refs/remotes/origin)

        if [[ $LIVE -eq 1 && ${#del_remote[@]} -gt 0 ]]; then
            if git push origin --delete "${del_remote[@]}" 2>/dev/null; then
                for b in "${del_remote[@]}"; do
                    gum style --foreground 46 "  ✓ remote $b deleted"; T_REMOTE=$((T_REMOTE+1))
                done
            else
                # Batch push failed — retry individually to isolate the culprit.
                for b in "${del_remote[@]}"; do
                    if git push origin --delete "$b" 2>/dev/null; then
                        gum style --foreground 46 "  ✓ remote $b deleted"; T_REMOTE=$((T_REMOTE+1))
                    else
                        gum style --foreground 196 "  ✗ remote $b failed"; T_FAIL=$((T_FAIL+1))
                    fi
                done
            fi
        fi

        if [[ $has_origin -eq 1 && $gh_ok -eq 0 ]]; then
            emit_header
            gum style --foreground 214 "  ⚠ PR protection off (no gh/GitHub) — remote deletes limited to merged-only"
        fi

        popd >/dev/null
    }

    for dir in "${REPOS[@]}"; do process_repo "$dir"; done

    echo ""
    gum style --foreground 212 --bold --border double --border-foreground 212 --padding "0 2" "Summary"
    verb="would delete"; [[ $LIVE -eq 1 ]] && verb="deleted    "
    echo "$(gum style --foreground 46 "Local  $verb:") $T_LOCAL"
    echo "$(gum style --foreground 46 "Remote $verb:") $T_REMOTE"
    [[ $T_FAIL -gt 0 ]] && echo "$(gum style --foreground 196 "Failed:            ") $T_FAIL"
    if [[ $LIVE -eq 1 && $T_REMOTE -gt 0 ]]; then
        gum style --foreground 244 "Remote deletions on GitHub are recoverable for ~90 days."
    fi
    [[ $LIVE -eq 0 ]] && gum style --foreground 226 "Dry run — re-run with --go to apply."

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
# A first-boot setup script installs chezmoi and applies the dotfiles straight
# from GitHub, which also runs the mise/apt sync daemons to lay down the CLI
# toolchain (rg, fzf, gh, …), then switches the login shell to zsh.
# Upgrade later with `just exe-decrypt`.
# Optional VM name (exe.dev generates one if omitted).
#   just exe-new            # auto-named
#   just exe-new my-box     # named
exe-new name="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=(new)
    [[ -n "{{ name }}" ]] && args+=("--name={{ name }}")
    # No BOOTSTRAP_MODE needed: secrets are excluded structurally, not by a flag.
    # With no ~/.config/age/key.txt at init time, .chezmoi.toml.tmpl omits the
    # [age] block; with encryption unconfigured chezmoi's encryption suffix is
    # empty, so encrypted targets keep their `.age` extension and the `**/*.age`
    # rule in .chezmoiignore.tmpl matches them. A setup script couldn't decrypt
    # anything anyway -- age needs a tty to read the passphrase, and first boot
    # has none.
    #
    # -b is load-bearing: get.chezmoi.io defaults BINDIR to a RELATIVE `bin`,
    # i.e. wherever /exe.dev/setup happens to run from. `just exe-decrypt`
    # hardcodes ~/.local/bin/chezmoi, and that dir is first on PATH.
    #
    # The trailing chsh points the login shell at the config this repo actually
    # ships. exeuntu logs you in as bash, but mise -- along with starship, atuin
    # and zoxide -- is activated only in dot_zshrc.tmpl and fish's
    # conf.d/10-tools.fish.tmpl; there is no bash config here at all. Skip this
    # and you land in bash with the whole mise toolchain installed under
    # ~/.local/share/mise/installs yet absent from PATH, which reads as "the
    # tools never installed". zsh itself arrives via aptfile.txt during the
    # apply above, so the chsh has to follow it. `id -un` rather than $USER,
    # which a non-interactive first-boot script can't count on. Guarded and
    # non-fatal: a box without zsh keeps bash instead of failing setup.
    #
    # The `uname -s` check is belt-and-braces. This heredoc only ever executes
    # on the exeuntu VM -- it is piped to --setup-script, not run locally -- so
    # it cannot touch this Mac's login shell. The guard states that invariant in
    # the code rather than leaving it to be inferred from the pipeline.
    printf '%s\n' \
      '#!/usr/bin/env sh' \
      'sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply andreweick' \
      'if [ "$(uname -s)" = "Linux" ] && command -v zsh >/dev/null 2>&1; then' \
      '  sudo chsh -s "$(command -v zsh)" "$(id -un)" ||' \
      '    echo "setup: could not change login shell to zsh, staying on bash" >&2' \
      'fi' \
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
[arg("src", help="Source: local path or [user@]host:/path (remote is SFTP over ssh)")]
[arg("dest", help="Destination: local path or [user@]host:/path")]
[arg("EXTRA", help="--go = real run; --mkparents = skip dest-parent guard; --bwlimit/--checkers/--transfers/--retries override the conservative defaults; rest pass through to rclone")]
rclone-copy src dest *EXTRA:
    #!/usr/bin/env bash
    set -euo pipefail

    # Turn "[user@]host:/path" into an on-the-fly SFTP remote; leave locals alone.
    # Transport is delegated to `ssh` PER-REMOTE via the connection string's `ssh`
    # option (the on-the-fly equivalent of --sftp-ssh). It MUST be per-remote: a
    # single global --sftp-ssh can't serve two different hosts, so server→server
    # would break. Embedding the host in `ssh '...'` also means ~/.ssh/config,
    # ProxyJump and IdentityFile all apply, exactly like scp.
    #
    # ControlMaster/ControlPath/ControlPersist multiplex every connection rclone
    # opens onto ONE shared SSH session per host. Without it, `ssh=` spawns a fresh
    # ssh process — a full TCP+handshake+auth — for each connection, and a burst of
    # those looks like a brute-force flood to the far end's connection rate-limiting
    # (an SSH gateway / provider network middleware / fail2ban), which then blocks us.
    # The ssh -o flags bypass host-key checking entirely (no first-connect prompt,
    # nothing written to known_hosts) for frictionless ad-hoc transfers — the
    # trade-off is no protection against a changed host key. The three sftp params
    # only silence rclone's cosmetic NOTICEs (shell probe, hash-binary probe,
    # host-key); known_hosts_file=/dev/null is just an always-present empty file
    # so rclone stops warning.
    remotify() {
        local a="$1"
        [[ "$a" != *:* ]] && { printf '%s' "$a"; return; }   # local path, unchanged
        local hostpart="${a%%:*}" path="${a#*:}"
        printf ":sftp,ssh='ssh -o ControlMaster=auto -o ControlPath=~/.ssh/cm-%%r@%%h:%%p -o ControlPersist=60s -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null %s',shell_type=unix,disable_hashcheck=true,known_hosts_file=/dev/null:%s" "$hostpart" "$path"
    }
    # Preflight: refuse to run unless the destination's PARENT dir already exists —
    # a cheap guard against a wrong host/IP (the wrong box won't have your tree, so
    # we bail before rclone creates anything). rclone still creates the final leaf
    # dir; pass --mkparents to skip this and let rclone build the whole tree.
    preflight() {
        local dest="$1"
        if [[ "$dest" == *:* ]]; then
            local hostpart="${dest%%:*}" parent
            parent="$(dirname "${dest#*:}")"
            [[ "$parent" == "." ]] && return 0   # remote home dir — always exists
            rclone lsf --dirs-only "$(remotify "$hostpart:$parent/")" >/dev/null 2>&1 && return 0
            echo "✋ Destination parent '$parent' not found on '$hostpart' — wrong host/path?" >&2
            echo "   Create it first, or pass --mkparents to build the tree. Aborting." >&2
            exit 1
        fi
        local parent; parent="$(dirname "$dest")"
        [[ -d "$parent" ]] || { echo "✋ Local destination parent '$parent' does not exist. Aborting (--mkparents to skip)." >&2; exit 1; }
    }

    SRC="$(remotify "{{ src }}")"
    DST="$(remotify "{{ dest }}")"

    # --go = real run; --mkparents = skip the parent-exists guard; rest → rclone.
    dryrun="--dry-run"; mkparents=0; pass=()
    for a in {{ EXTRA }}; do
        case "$a" in
            --go)        dryrun="" ;;
            --mkparents) mkparents=1 ;;
            *)           pass+=("$a") ;;
        esac
    done
    [[ "$mkparents" == 1 ]] || preflight "{{ dest }}"
    [[ -n "$dryrun" ]] && gum style --foreground 46 --bold --border double --border-foreground 46 --padding "0 2" \
      "🌵 DRY RUN — nothing will be transferred. Add --go to run for real."

    # Shared junk-file excludes (same list the interactive rclone wrapper uses).
    xf=(); [[ -f ~/.config/rclone/excludes.txt ]] && xf=(--exclude-from ~/.config/rclone/excludes.txt)

    # Any of these defaults is overridden if the same flag appears in EXTRA —
    # has_flag scans what the user passed so their choice always wins.
    has_flag() { local f="$1" a; for a in ${pass[@]+"${pass[@]}"}; do [[ "$a" == "$f" || "$a" == "$f="* ]] && return 0; done; return 1; }

    # Default to half of a 1 Gbit link (~60 MiByte/s).
    bw=(); has_flag --bwlimit || bw=(--bwlimit 60M)

    # Conservative concurrency + retry caps. The `ssh=` transport opens a fresh SSH
    # handshake per connection, so a stalled transfer retrying at high concurrency
    # can flood the far end and trip its connection rate-limiting (an SSH gateway or
    # provider network middleware — e.g. exe.dev's — that temporarily blocks a source
    # opening many connections). Low checkers/transfers + few retries keep us to a
    # polite trickle; combined with the ControlMaster multiplexing in remotify(),
    # connections are reused rather than re-handshaked. Not time-critical work —
    # slow and gentle beats fast and blocked.
    tune=()
    has_flag --checkers          || tune+=(--checkers 2)
    has_flag --transfers         || tune+=(--transfers 2)
    has_flag --retries           || tune+=(--retries 1)
    has_flag --low-level-retries || tune+=(--low-level-retries 3)

    # Assemble the exact argv, print it copy-pasteably, then run that same argv.
    cmd=(rclone copy "$SRC" "$DST" --ignore-case-sync --progress)
    [[ -n "$dryrun" ]] && cmd+=("$dryrun")
    cmd+=(${tune[@]+"${tune[@]}"} ${bw[@]+"${bw[@]}"} ${xf[@]+"${xf[@]}"} ${pass[@]+"${pass[@]}"})

    echo "📋 Command (copy to run it manually):"
    printf '  '; printf '%q ' "${cmd[@]}"; echo

    "${cmd[@]}"

# Mirror src onto dest across SSH — DESTRUCTIVE: files on dest that aren't in
# src are DELETED. Same auto-detect + connection-string trick as rclone-copy.
# DRY-RUN BY DEFAULT — the preview lists what it would delete; review it, then
# pass `--go` to commit.
#   just rclone-sync ~/dir/        andy@host:/srv/data          # preview + deletes
#   just rclone-sync ~/dir/        andy@host:/srv/data --go     # commit
[arg("src", help="Source: local path or [user@]host:/path (remote is SFTP over ssh)")]
[arg("dest", help="Destination to mirror onto — DESTRUCTIVE: extra files here are DELETED")]
[arg("EXTRA", help="--go = commit the sync; --mkparents = skip dest-parent guard; --bwlimit/--checkers/--transfers/--retries override the conservative defaults; rest pass through to rclone")]
rclone-sync src dest *EXTRA:
    #!/usr/bin/env bash
    set -euo pipefail

    # Per-remote `ssh` in the connection string — see rclone-copy for the full
    # rationale (per-remote requirement, host-key bypass, cosmetic-NOTICE params).
    remotify() {
        local a="$1"
        [[ "$a" != *:* ]] && { printf '%s' "$a"; return; }
        local hostpart="${a%%:*}" path="${a#*:}"
        printf ":sftp,ssh='ssh -o ControlMaster=auto -o ControlPath=~/.ssh/cm-%%r@%%h:%%p -o ControlPersist=60s -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null %s',shell_type=unix,disable_hashcheck=true,known_hosts_file=/dev/null:%s" "$hostpart" "$path"
    }
    # Preflight guard against a wrong host/IP — see rclone-copy. Extra important
    # here: syncing onto the wrong (or empty) box could mirror-DELETE. rclone still
    # creates the final leaf dir; pass --mkparents to skip and build the tree.
    preflight() {
        local dest="$1"
        if [[ "$dest" == *:* ]]; then
            local hostpart="${dest%%:*}" parent
            parent="$(dirname "${dest#*:}")"
            [[ "$parent" == "." ]] && return 0   # remote home dir — always exists
            rclone lsf --dirs-only "$(remotify "$hostpart:$parent/")" >/dev/null 2>&1 && return 0
            echo "✋ Destination parent '$parent' not found on '$hostpart' — wrong host/path?" >&2
            echo "   Create it first, or pass --mkparents to build the tree. Aborting." >&2
            exit 1
        fi
        local parent; parent="$(dirname "$dest")"
        [[ -d "$parent" ]] || { echo "✋ Local destination parent '$parent' does not exist. Aborting (--mkparents to skip)." >&2; exit 1; }
    }

    SRC="$(remotify "{{ src }}")"
    DST="$(remotify "{{ dest }}")"

    # --go = commit; --mkparents = skip the parent-exists guard; rest → rclone.
    dryrun="--dry-run"; mkparents=0; pass=()
    for a in {{ EXTRA }}; do
        case "$a" in
            --go)        dryrun="" ;;
            --mkparents) mkparents=1 ;;
            *)           pass+=("$a") ;;
        esac
    done
    [[ "$mkparents" == 1 ]] || preflight "{{ dest }}"

    gum style --foreground 196 --bold --border double --border-foreground 196 --padding "0 2" \
      "⚠️  rclone sync is DESTRUCTIVE — extra files on the destination will be DELETED"
    [[ -n "$dryrun" ]] && gum style --foreground 46 --bold --border double --border-foreground 46 --padding "0 2" \
      "🌵 DRY RUN — nothing will change. Review the deletes below, then add --go to commit."

    # Shared junk-file excludes (same list the interactive rclone wrapper uses).
    xf=(); [[ -f ~/.config/rclone/excludes.txt ]] && xf=(--exclude-from ~/.config/rclone/excludes.txt)

    # Any of these defaults is overridden if the same flag appears in EXTRA —
    # has_flag scans what the user passed so their choice always wins.
    has_flag() { local f="$1" a; for a in ${pass[@]+"${pass[@]}"}; do [[ "$a" == "$f" || "$a" == "$f="* ]] && return 0; done; return 1; }

    # Default to half of a 1 Gbit link (~60 MiByte/s).
    bw=(); has_flag --bwlimit || bw=(--bwlimit 60M)

    # Conservative concurrency + retry caps. The `ssh=` transport opens a fresh SSH
    # handshake per connection, so a stalled transfer retrying at high concurrency
    # can flood the far end and trip its connection rate-limiting (an SSH gateway or
    # provider network middleware — e.g. exe.dev's — that temporarily blocks a source
    # opening many connections). Low checkers/transfers + few retries keep us to a
    # polite trickle; combined with the ControlMaster multiplexing in remotify(),
    # connections are reused rather than re-handshaked. Not time-critical work —
    # slow and gentle beats fast and blocked.
    tune=()
    has_flag --checkers          || tune+=(--checkers 2)
    has_flag --transfers         || tune+=(--transfers 2)
    has_flag --retries           || tune+=(--retries 1)
    has_flag --low-level-retries || tune+=(--low-level-retries 3)

    # Assemble the exact argv, print it copy-pasteably, then run that same argv.
    cmd=(rclone sync "$SRC" "$DST" --ignore-case-sync --progress)
    [[ -n "$dryrun" ]] && cmd+=("$dryrun")
    cmd+=(${tune[@]+"${tune[@]}"} ${bw[@]+"${bw[@]}"} ${xf[@]+"${xf[@]}"} ${pass[@]+"${pass[@]}"})

    echo "📋 Command (copy to run it manually):"
    printf '  '; printf '%q ' "${cmd[@]}"; echo

    "${cmd[@]}"

# ── borgbackup / rsync.net ──────────────────────────────────────────────────
# READ-ONLY access to the off-site Borg repo, for INSPECTING and RESTORING.
#
# Nothing here writes to rsync.net. Backups are created by borgmatic CronJobs in
# the vipers cluster, and prune/compact happen there too — deliberately not
# mirrored into recipes. Every recipe below uses the APPEND-ONLY SSH key, which
# the rsync.net side will not let delete anything, so a fat-fingered command
# can't eat your backups.
#
# Three things EVERY borg call against this repo needs, all supplied here so
# they never get retyped out of shell history again:
#   BORG_REPO         ssh://de4596@de4596.rsync.net/./borg
#   BORG_REMOTE_PATH  borg14 — rsync.net's server-side borg is NOT on PATH as
#                     `borg`; without this every command fails at the far end
#   BORG_PASSPHRASE   the repo is repokey-blake2, so EVERY command needs it.
#                     Read from ~/.config/borg/passphrase, which chezmoi ships
#                     age-encrypted and decrypts on apply (0600).
#
# Borg must be 1.x — the repo was created against rsync.net's borg14 server and
# a 2.x client cannot open it. That's why ~/.config/mise/config.toml pins
# `borg = "1"`. `just borg-doctor` checks this.
#
# WHAT'S IN AN ARCHIVE. borgmatic writes pg_dumps at
#   borgmatic/postgresql_databases/<pg-hostname>/<database>
# in pg_dump CUSTOM format — so they're restored with `pg_restore`, not `psql`,
# and `pg_restore --list` reads the table of contents without restoring
# anything. `just borg-dbs` lists them; `just borg-get <db>` pulls one down.
#
# ARCHIVE NAMES are timestamps (borg-backup-2026-08-16T19:00:09.194131). Every
# recipe taking an archive accepts `latest` — or nothing at all — instead.

borg_repo := "ssh://de4596@de4596.rsync.net/./borg"
borg_pass := ".config/borg/passphrase"

# Run any borg command against the rsync.net repo, with repo / passphrase /
# remote-path already set. Escape hatch for anything the named recipes below
# don't cover. Remember borg's own `::archive` syntax for archive arguments.
#   just borg-run list
#   just borg-run info '::latest-archive-name'
#   just borg-run diff '::archive-a' 'archive-b'
[arg("ARGS", help="borg subcommand and flags, e.g. `list`, `info`, `check --repository-only`")]
borg-run +ARGS:
    #!/usr/bin/env bash
    set -euo pipefail

    # Prefer whatever's on PATH (mise activate puts it there in an interactive
    # shell), but fall back to asking mise directly — `just` invoked from a
    # non-activated context otherwise can't find it even though it's installed.
    if command -v borg >/dev/null 2>&1; then
        BORG_BIN="borg"
    elif BORG_BIN="$(mise which borg 2>/dev/null)" && [[ -n "$BORG_BIN" ]]; then
        :
    else
        echo "✋ borg not installed. It's in ~/.config/mise/config.toml — run: mise install" >&2
        exit 1
    fi

    # Append-only key, always. It can read everything and create archives, but
    # the far end refuses deletes. Nothing in this section needs more than that.
    KEY="$HOME/.ssh/rsync.net-borg-append-only-key"
    [[ -f "$KEY" ]] || { echo "✋ ssh key not found: $KEY" >&2; exit 1; }

    PASS_FILE="$HOME/{{ borg_pass }}"
    if [[ ! -f "$PASS_FILE" ]]; then
        echo "✋ no passphrase at $PASS_FILE" >&2
        echo "   Almost certainly means this machine has no age key, so chezmoi skipped" >&2
        echo "   the encrypted file. Fix with:" >&2
        echo "     just czm-setup-age-key && chezmoi init --apply andreweick" >&2
        exit 1
    fi

    export BORG_REPO="{{ borg_repo }}"
    export BORG_REMOTE_PATH="borg14"
    # Same SSH tuning the cluster CronJob uses (borg-backup/cronjob.yaml). The
    # ControlMaster/ControlPersist multiplexing is the load-bearing part:
    # rsync.net drops long-idle sessions, and borg reconnecting per-operation
    # looks like a connection flood to the far end's rate limiting.
    export BORG_RSH="ssh -i $KEY -o ServerAliveInterval=30 -o ServerAliveCountMax=10 -o ConnectTimeout=30 -o ControlMaster=auto -o ControlPath=/tmp/borg-ssh-%C -o ControlPersist=10m"

    # Read the passphrase HERE rather than handing borg a BORG_PASSCOMMAND:
    # borg splits that variable with shlex and runs it WITHOUT a shell, so any
    # pipe or redirect silently becomes arguments instead of a pipeline. Doing
    # it in bash sidesteps the question. The file is stored without a trailing
    # newline; `tr -d` is belt-and-braces against an editor putting one back.
    BORG_PASSPHRASE="$(tr -d '\n' < "$PASS_FILE")"
    export BORG_PASSPHRASE
    [[ -n "$BORG_PASSPHRASE" ]] || { echo "✋ passphrase file is empty: $PASS_FILE" >&2; exit 1; }

    exec "$BORG_BIN" {{ ARGS }}

# Preflight — can this machine reach and read the repo? Checks the binary and
# its major version, the SSH key, the decrypted passphrase, then does a
# read-only `borg info` to prove the whole chain end to end. Run this first.
borg-doctor:
    #!/usr/bin/env bash
    set -uo pipefail   # no -e: this recipe reports failures rather than aborting

    fail=0
    ok()   { gum style --foreground 46  "  ✓ $1"; }
    bad()  { gum style --foreground 196 "  ✗ $1"; fail=1; }
    warn() { gum style --foreground 214 "  ⚠ $1"; }

    gum style --foreground 212 --bold --border double --border-foreground 212 --padding "0 1" \
      "borg doctor"

    BORG_BIN="$(command -v borg 2>/dev/null || mise which borg 2>/dev/null || true)"
    if [[ -n "$BORG_BIN" ]]; then
        ver="$("$BORG_BIN" --version 2>/dev/null | awk '{print $2}')"
        ok "borg $ver at $BORG_BIN"
        case "$ver" in
            1.*) ok "on the 1.x line (required — a 2.x client cannot open this repo)" ;;
            *)   bad "borg $ver is NOT 1.x. This repo is repokey-blake2 against rsync.net's borg14 server and a 2.x client cannot open it. Check the 'borg' pin in ~/.config/mise/config.toml." ;;
        esac
        case "$BORG_BIN" in
            *homebrew*|/usr/local/bin/*) warn "that's a Homebrew path — Homebrew's borgbackup is 2.x, and two binaries on PATH is the shadowing failure the mise config warns about" ;;
        esac
    else
        bad "borg not installed — run: mise install"
    fi

    KEY="$HOME/.ssh/rsync.net-borg-append-only-key"
    if [[ -f "$KEY" ]]; then ok "ssh key $(basename "$KEY")"; else bad "missing ssh key: $KEY"; fi

    if [[ -f "$HOME/{{ borg_pass }}" ]]; then
        if [[ -s "$HOME/{{ borg_pass }}" ]]; then
            mode="$(stat -f %Lp "$HOME/{{ borg_pass }}" 2>/dev/null || stat -c %a "$HOME/{{ borg_pass }}")"
            ok "passphrase present ($(wc -c < "$HOME/{{ borg_pass }}" | tr -d ' ') bytes, mode $mode)"
            [[ "$mode" == "600" ]] || warn "expected mode 600, got $mode"
        else
            bad "passphrase file is empty: ~/{{ borg_pass }}"
        fi
    else
        bad "no passphrase at ~/{{ borg_pass }} — no age key on this machine? run: just czm-setup-age-key && chezmoi init --apply andreweick"
    fi

    if [[ $fail -eq 0 ]]; then
        echo ""
        gum style --foreground 244 "Contacting {{ borg_repo }} (read-only)…"
        if just --justfile "{{ justfile() }}" borg-run info --json >/dev/null 2>&1; then
            ok "repo reachable and readable over the append-only key"
        else
            bad "could not read the repo — re-run 'just borg-run info' to see borg's own error"
        fi
    fi

    echo ""
    if [[ $fail -eq 0 ]]; then
        gum style --foreground 46 --bold "All checks passed."
    else
        gum style --foreground 196 --bold "Some checks failed (see ✗ above)."
        exit 1
    fi

# Print the name of the most recent archive. Useful on its own, and it's what
# every recipe below falls back to when you don't name an archive.
borg-latest:
    @just --justfile "{{ justfile() }}" borg-run list --last 1 --format '{archive}{NL}'

# List archives in the repo, or the contents of one archive.
#   just borg-list                 # every archive, newest last
#   just borg-list latest          # contents of the newest archive
#   just borg-list borg-backup-2026-08-16T19:00:09.194131
[arg("ARCHIVE", help="Archive name, or `latest`. Omit to list all archives.")]
borg-list *ARCHIVE:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{ ARCHIVE }}" ]]; then
        just --justfile "{{ justfile() }}" borg-run list
    else
        # `::name` is borg's "archive within $BORG_REPO" syntax. Without the
        # leading `::` borg reads the bare name as a REPO location and tries to
        # resolve its first path segment as a hostname.
        archive="{{ ARCHIVE }}"
        [[ "$archive" == "latest" ]] && archive="$(just --justfile "{{ justfile() }}" borg-latest)"
        just --justfile "{{ justfile() }}" borg-run list "::$archive"
    fi

# Repo statistics, or statistics for a single archive.
#   just borg-info
#   just borg-info latest
[arg("ARCHIVE", help="Archive name, or `latest`. Omit for whole-repo stats.")]
borg-info *ARCHIVE:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{ ARCHIVE }}" ]]; then
        just --justfile "{{ justfile() }}" borg-run info
    else
        archive="{{ ARCHIVE }}"
        [[ "$archive" == "latest" ]] && archive="$(just --justfile "{{ justfile() }}" borg-latest)"
        just --justfile "{{ justfile() }}" borg-run info "::$archive"
    fi

# List the PostgreSQL dumps in an archive, with sizes — the fast answer to
# "what databases do I have and how big are they?". Defaults to the newest
# archive. Feed a name from here to `just borg-get`.
#   just borg-dbs
#   just borg-dbs borg-backup-2026-08-15T13:00:37.730369
[arg("ARCHIVE", help="Archive name, or `latest`/omitted for the newest")]
borg-dbs *ARCHIVE:
    #!/usr/bin/env bash
    set -euo pipefail
    archive="{{ ARCHIVE }}"
    if [[ -z "$archive" || "$archive" == "latest" ]]; then archive="$(just --justfile "{{ justfile() }}" borg-latest)"; fi

    gum style --foreground 212 --bold --border double --border-foreground 212 --padding "0 1" \
      "$archive"

    # Only regular files directly under a pg-hostname dir — that skips the
    # directories themselves and borgmatic's dumps.json manifest.
    just --justfile "{{ justfile() }}" borg-run list --format '{type}{TAB}{size}{TAB}{path}{NL}' "::$archive" \
      | awk -F'\t' '
            function human(b) {
                if (b >= 1073741824) return sprintf("%.1f GiB", b/1073741824);
                if (b >= 1048576)    return sprintf("%.1f MiB", b/1048576);
                if (b >= 1024)       return sprintf("%.1f KiB", b/1024);
                return sprintf("%d B", b);
            }
            $1=="-" && $3 ~ /^borgmatic\/postgresql_databases\/[^\/]+\/[^\/]+$/ {
                split($3, p, "/"); host=p[3]; db=p[4];
                printf "  %-24s %11s   %s\n", db, human($2), host
            }' \
      | sort
    echo ""
    gum style --foreground 244 "Dumps are pg_dump CUSTOM format — restore with pg_restore, not psql."
    gum style --foreground 244 "Pull one down with: just borg-get <database>"

# Download ONE database dump to the current directory as <database>.dump.
# Streams straight out of the repo — nothing is written to rsync.net.
#   just borg-get mealie
#   just borg-get mealie borg-backup-2026-08-15T13:00:37.730369
[arg("db", help="Database name as shown by `just borg-dbs`")]
[arg("ARCHIVE", help="Archive name, or `latest`/omitted for the newest")]
borg-get db *ARCHIVE:
    #!/usr/bin/env bash
    set -euo pipefail
    # `just` runs recipes from the justfile's own directory, not the one you
    # typed the command in. Without this, dumps land in the dotfiles repo.
    cd "{{ invocation_directory() }}"
    # Having cd'd away, nested `just` calls can no longer find this justfile by
    # search — name it explicitly, and pin its working directory to ours.
    JUST=(just --justfile "{{ justfile() }}" --working-directory "$PWD")

    archive="{{ ARCHIVE }}"
    if [[ -z "$archive" || "$archive" == "latest" ]]; then archive="$("${JUST[@]}" borg-latest)"; fi

    # Resolve the short database name to its full in-archive path. The pg
    # hostname sits in the middle of the path and isn't worth making you type.
    path="$("${JUST[@]}" borg-run list --format '{type}{TAB}{path}{NL}' "::$archive" \
        | awk -F'\t' -v db="{{ db }}" '$1=="-" && $2 ~ /^borgmatic\/postgresql_databases\/[^\/]+\// {
              n=split($2, p, "/"); if (p[4]==db) print $2
          }')"

    if [[ -z "$path" ]]; then
        echo "✋ no database named '{{ db }}' in $archive" >&2
        echo "   Run 'just borg-dbs' to see what's there." >&2
        exit 1
    fi
    if [[ "$(printf '%s\n' "$path" | wc -l | tr -d ' ')" -gt 1 ]]; then
        echo "✋ '{{ db }}' is ambiguous — matches more than one host:" >&2
        printf '   %s\n' $path >&2
        echo "   Use: just borg-run extract --stdout '::$archive' <full-path> > out.dump" >&2
        exit 1
    fi

    out="{{ db }}.dump"
    [[ -e "$out" ]] && { echo "✋ $out already exists here — move it aside first." >&2; exit 1; }

    gum style --foreground 244 "$path  →  $PWD/$out"
    "${JUST[@]}" borg-run extract --stdout "::$archive" "$path" > "$out"

    gum style --foreground 46 --bold "✓ $out ($(du -h "$out" | cut -f1))"
    gum style --foreground 244 "Inspect without restoring:  pg_restore --list $out"
    gum style --foreground 244 "Restore:                    pg_restore -d <target-db> $out"

# Stream any file out of an archive to stdout — no temp files, no extraction.
# Good for peeking at small files, or piping a dump straight into pg_restore.
#   just borg-cat latest borgmatic/postgresql_databases/dumps.json | jless
#   just borg-cat latest etc/borgmatic.d/config.yaml
[arg("archive", help="Archive name, or `latest`")]
[arg("path", help="Full in-archive path, as shown by `just borg-list <archive>`")]
borg-cat archive path:
    #!/usr/bin/env bash
    set -euo pipefail
    archive="{{ archive }}"
    [[ "$archive" == "latest" ]] && archive="$(just --justfile "{{ justfile() }}" borg-latest)"
    just --justfile "{{ justfile() }}" borg-run extract --stdout "::$archive" "{{ path }}"

# Find paths matching a pattern inside an archive. Plain substring match, case
# insensitive — for anything fancier use `just borg-list <archive>` and grep.
#   just borg-find mastodon
#   just borg-find config borg-backup-2026-08-15T13:00:37.730369
[arg("pattern", help="Substring to match against in-archive paths")]
[arg("ARCHIVE", help="Archive name, or `latest`/omitted for the newest")]
borg-find pattern *ARCHIVE:
    #!/usr/bin/env bash
    set -euo pipefail
    archive="{{ ARCHIVE }}"
    if [[ -z "$archive" || "$archive" == "latest" ]]; then archive="$(just --justfile "{{ justfile() }}" borg-latest)"; fi
    just --justfile "{{ justfile() }}" borg-run list --format '{size}{TAB}{path}{NL}' "::$archive" \
      | grep -i -- "{{ pattern }}" \
      || { echo "no match for '{{ pattern }}' in $archive" >&2; exit 1; }

# Compare two archives — what changed between them. Cheap way to see which
# databases actually grew or shrank between two runs.
#   just borg-diff borg-backup-2026-08-15T13:00:37.730369 latest
[arg("a", help="Older archive name")]
[arg("b", help="Newer archive name, or `latest`")]
borg-diff a b:
    #!/usr/bin/env bash
    set -euo pipefail
    A="{{ a }}"; B="{{ b }}"
    [[ "$A" == "latest" ]] && A="$(just --justfile "{{ justfile() }}" borg-latest)"
    [[ "$B" == "latest" ]] && B="$(just --justfile "{{ justfile() }}" borg-latest)"
    just --justfile "{{ justfile() }}" borg-run diff "::$A" "$B"

# Mount an archive as a browsable filesystem — the nicest way to poke around.
# Needs macFUSE, and the standalone borg release binary may not have FUSE
# support compiled in; if it errors, fall back to borg-find / borg-cat.
# Runs in the FOREGROUND so Ctrl-C unmounts cleanly.
#   just borg-mount ~/mnt/borg
#   just borg-mount ~/mnt/borg latest
[arg("mountpoint", help="Directory to mount at — created if missing")]
[arg("ARCHIVE", help="Archive name, or `latest`. Omit to mount the WHOLE repo (every archive as a subdir).")]
borg-mount mountpoint *ARCHIVE:
    #!/usr/bin/env bash
    set -euo pipefail
    # So a relative mountpoint means "relative to where you typed this", not
    # to the justfile's directory.
    cd "{{ invocation_directory() }}"
    JUST=(just --justfile "{{ justfile() }}" --working-directory "$PWD")
    mkdir -p "{{ mountpoint }}"
    archive="{{ ARCHIVE }}"
    if [[ -n "$archive" ]]; then
        [[ "$archive" == "latest" ]] && archive="$("${JUST[@]}" borg-latest)"
        target="::$archive"
    else
        target=""   # whole repo: every archive shows up as a subdirectory
    fi
    gum style --foreground 244 "Mounting at {{ mountpoint }} — Ctrl-C to unmount."
    "${JUST[@]}" borg-run mount -f ${target:+"$target"} "{{ mountpoint }}"

# Unmount a borg filesystem mounted by borg-mount.
[arg("mountpoint", help="The directory passed to borg-mount")]
borg-umount mountpoint:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ invocation_directory() }}"
    just --justfile "{{ justfile() }}" --working-directory "$PWD" borg-run umount "{{ mountpoint }}"

# Restore files from an archive into the CURRENT DIRECTORY.
# DRY-RUN BY DEFAULT — lists what it would write and touches nothing. Add --go.
# For a single database dump, `just borg-get <db>` is easier.
#   just borg-extract latest
#   just borg-extract latest --go
#   just borg-extract latest borgmatic/postgresql_databases/ --go
[arg("archive", help="Archive name, or `latest`")]
[arg("EXTRA", help="--go = write files for real; paths restrict what's restored; rest pass to borg extract")]
borg-extract archive *EXTRA:
    #!/usr/bin/env bash
    set -euo pipefail

    # `just` runs recipes from the justfile's own directory, not the one you
    # typed the command in. Without this, borg would unpack the archive into
    # the dotfiles repo instead of where you're standing. --working-directory
    # carries that through to the nested call, which is what borg actually
    # extracts into.
    cd "{{ invocation_directory() }}"
    JUST=(just --justfile "{{ justfile() }}" --working-directory "$PWD")

    archive="{{ archive }}"
    [[ "$archive" == "latest" ]] && archive="$("${JUST[@]}" borg-latest)"

    live=0; pass=()
    for a in {{ EXTRA }}; do
        case "$a" in
            --go) live=1 ;;
            *)    pass+=("$a") ;;
        esac
    done

    # borg extract writes into $PWD with no way to redirect it, so say plainly
    # where that is — the usual mistake is running this from the wrong place.
    gum style --foreground 212 --bold --border double --border-foreground 212 --padding "0 1" \
      "Extracting INTO: $PWD"

    if [[ $live -eq 0 ]]; then
        gum style --foreground 46 --bold --border double --border-foreground 46 --padding "0 2" \
          "🌵 DRY RUN — nothing will be written. Add --go to restore for real."
        "${JUST[@]}" borg-run extract --dry-run --list "::$archive" ${pass[@]+"${pass[@]}"}
    else
        "${JUST[@]}" borg-run extract --list "::$archive" ${pass[@]+"${pass[@]}"}
    fi

#!/usr/bin/env bash
# release.sh — cut releases for one or more triggers in this monorepo.
#
# Usage:
#   scripts/release.sh bump  <trigger>:<version> [<trigger>:<version> ...]
#   scripts/release.sh tag   <trigger>:<version> [<trigger>:<version> ...]
#   scripts/release.sh all   <trigger>:<version> [<trigger>:<version> ...]
#
# Subcommands:
#   bump   Create a release branch, bump versions in Cargo.toml +
#          spin-pluginify.toml for each named trigger, refresh
#          Cargo.lock, push the branch, and (unless --no-pr) open a
#          PR via `gh`.
#   tag    From an up-to-date local `main`, create a GPG-signed
#          annotated tag `<trigger>-v<version>` for each pair and push
#          them atomically. Versions in Cargo.toml on `main` must
#          already match the values you pass.
#   all    Run `bump`, wait for you to confirm the PR has merged, then
#          run `tag`.
#
# Flags (all subcommands):
#   --dry-run        Print the actions that would be taken; change nothing.
#   --no-push        Skip `git push` (branches and tags).
#   --no-pr          Skip `gh pr create` in `bump`.
#   --branch <name>  Branch name for `bump` (default: release/<date>-<slug>).
#   --remote <name>  Git remote (default: origin).
#
# Supported triggers:
#   sqs, mqtt, cron, command

set -euo pipefail

#------------------------------------------------------------------------------
# Trigger registry
#------------------------------------------------------------------------------
# trigger_meta <short> => "<crate-dir>|<package>|<pretty-label>"
trigger_meta() {
    case "$1" in
        sqs)     echo "trigger-sqs|trigger-sqs|SQS" ;;
        mqtt)    echo "trigger-mqtt|trigger-mqtt|MQTT" ;;
        cron)    echo "trigger-cron|trigger-cron|Cron" ;;
        command) echo "trigger-command|trigger-command|Command" ;;
        *) return 1 ;;
    esac
}

SUPPORTED_TRIGGERS="sqs mqtt cron command"

#------------------------------------------------------------------------------
# Globals (set by parse_args)
#------------------------------------------------------------------------------
SUBCMD=""
DRY_RUN=0
NO_PUSH=0
NO_PR=0
BRANCH=""
REMOTE="origin"
declare -a PAIRS=()

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

#------------------------------------------------------------------------------
# Logging helpers
#------------------------------------------------------------------------------
log()  { printf '==> %s\n' "$*" >&2; }
warn() { printf 'warn: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# run <cmd...> — execute, or print under --dry-run.
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '   [dry-run] %s\n' "$*" >&2
    else
        "$@"
    fi
}

#------------------------------------------------------------------------------
# Argument parsing
#------------------------------------------------------------------------------
usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

parse_args() {
    [[ $# -ge 1 ]] || usage 1
    SUBCMD="$1"; shift
    case "$SUBCMD" in
        bump|tag|all) ;;
        -h|--help|help) usage 0 ;;
        *) die "unknown subcommand: $SUBCMD (expected: bump|tag|all)" ;;
    esac

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --no-push) NO_PUSH=1 ;;
            --no-pr)   NO_PR=1 ;;
            --branch)  shift; [[ $# -gt 0 ]] || die "--branch requires a value"; BRANCH="$1" ;;
            --remote)  shift; [[ $# -gt 0 ]] || die "--remote requires a value"; REMOTE="$1" ;;
            -h|--help) usage 0 ;;
            --) shift; while [[ $# -gt 0 ]]; do PAIRS+=("$1"); shift; done ;;
            -*) die "unknown flag: $1" ;;
            *) PAIRS+=("$1") ;;
        esac
        shift
    done

    [[ ${#PAIRS[@]} -ge 1 ]] || die "at least one <trigger>:<version> pair is required"
}

#------------------------------------------------------------------------------
# Validation helpers
#------------------------------------------------------------------------------
is_semver() {
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]
}

# semver_gt A B — true if A > B.
semver_gt() {
    [[ "$1" != "$2" ]] && [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" ]]
}

require_clean_worktree() {
    if [[ $DRY_RUN -eq 1 ]]; then
        return 0
    fi
    if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
        die "working tree is not clean; commit or stash changes first"
    fi
}

# read_toml_version <file> — print the first top-level `version = "X.Y.Z"`.
read_toml_version() {
    awk '
        /^\[/ { in_pkg = ($0 ~ /^\[package\]/ || NR == 1) }
        NR == 1 && $0 !~ /^\[/ { in_pkg = 1 }
        in_pkg && /^[[:space:]]*version[[:space:]]*=[[:space:]]*"[^"]+"/ {
            match($0, /"[^"]+"/)
            v = substr($0, RSTART+1, RLENGTH-2)
            print v
            exit
        }
    ' "$1"
}

# Validate one trigger:version pair and emit
#   "<short>|<crate-dir>|<package>|<pretty>|<version>|<cargo-toml>|<pluginify-toml>"
validate_pair() {
    local pair="$1"
    [[ "$pair" == *:* ]] || die "expected <trigger>:<version>, got: $pair"
    local short="${pair%%:*}" version="${pair#*:}"
    local meta crate package pretty
    meta="$(trigger_meta "$short")" \
        || die "unknown trigger '$short' (supported: $SUPPORTED_TRIGGERS)"
    IFS='|' read -r crate package pretty <<<"$meta"
    is_semver "$version" || die "invalid semver: $version"
    local cargo="$REPO_ROOT/crates/$crate/Cargo.toml"
    local plug="$REPO_ROOT/crates/$crate/spin-pluginify.toml"
    [[ -f "$cargo" ]] || die "missing $cargo"
    [[ -f "$plug" ]]  || die "missing $plug"
    echo "$short|$crate|$package|$pretty|$version|$cargo|$plug"
}

#------------------------------------------------------------------------------
# Version rewriting
#------------------------------------------------------------------------------
# rewrite_version <file> <new-version> — rewrite ONLY the first top-level
# `version = "..."` line (under [package] for Cargo.toml, the bare top of
# spin-pluginify.toml). Leaves every other `version = ...` (e.g. inside
# `[dependencies]` tables) untouched.
rewrite_version() {
    local file="$1" newver="$2"
    local tmp
    tmp="$(mktemp)"
    awk -v newver="$newver" '
        BEGIN { done = 0; in_pkg = 1 }   # treat pre-table as package scope
        /^\[/ { in_pkg = ($0 ~ /^\[package\]/) }
        {
            if (!done && in_pkg && $0 ~ /^[[:space:]]*version[[:space:]]*=[[:space:]]*"[^"]+"/) {
                sub(/"[^"]+"/, "\"" newver "\"")
                done = 1
            }
            print
        }
        END { if (!done) exit 2 }
    ' "$file" >"$tmp" || { rm -f "$tmp"; die "failed to rewrite version in $file"; }

    if [[ $DRY_RUN -eq 1 ]]; then
        printf '   [dry-run] would update version in %s -> %s\n' "$file" "$newver" >&2
        if command -v diff >/dev/null 2>&1; then
            diff -u "$file" "$tmp" | sed 's/^/      /' >&2 || true
        fi
        rm -f "$tmp"
    else
        mv "$tmp" "$file"
    fi
}

#------------------------------------------------------------------------------
# Subcommand: bump
#------------------------------------------------------------------------------
cmd_bump() {
    require_clean_worktree

    if [[ $NO_PR -eq 0 && $DRY_RUN -eq 0 ]]; then
        command -v gh >/dev/null 2>&1 \
            || die "gh CLI not found; install it or pass --no-pr"
        gh auth status >/dev/null 2>&1 \
            || die "gh is not authenticated; run 'gh auth login' or pass --no-pr"
    fi

    # Validate every pair up front, capture metadata for reuse.
    local -a entries=()
    local pair entry version cur cargo
    for pair in "${PAIRS[@]}"; do
        entry="$(validate_pair "$pair")"
        IFS='|' read -r _ _ _ _ version cargo _ <<<"$entry"
        cur="$(read_toml_version "$cargo")" \
            || die "could not read current version from $cargo"
        [[ -n "$cur" ]] || die "no top-level version found in $cargo"
        if ! semver_gt "$version" "$cur"; then
            die "$cargo: requested version $version is not greater than current $cur"
        fi
        entries+=("$entry")
    done

    # Compute branch + commit/PR title.
    local slug commit_title=""
    slug="$(printf '%s\n' "${PAIRS[@]}" | tr ':' '-' | paste -sd_ -)"
    if [[ -z "$BRANCH" ]]; then
        BRANCH="release/$(date +%Y%m%d)-${slug}"
    fi
    for pair in "${PAIRS[@]}"; do
        local short="${pair%%:*}" ver="${pair#*:}"
        commit_title+="${commit_title:+, }${short} v${ver}"
    done
    commit_title="release: ${commit_title}"

    log "Branch:  $BRANCH"
    log "Commit:  $commit_title"

    run git -C "$REPO_ROOT" fetch "$REMOTE" main
    run git -C "$REPO_ROOT" checkout -B "$BRANCH" "$REMOTE/main"

    local -a changed=()
    for entry in "${entries[@]}"; do
        local short crate package pretty version cargo plug
        IFS='|' read -r short crate package pretty version cargo plug <<<"$entry"
        log "Bumping $short -> $version"
        rewrite_version "$cargo" "$version"
        rewrite_version "$plug"  "$version"
        changed+=("$cargo" "$plug")
    done

    log "Refreshing Cargo.lock"
    run cargo build --workspace --manifest-path "$REPO_ROOT/Cargo.toml"

    run git -C "$REPO_ROOT" add "${changed[@]}" "$REPO_ROOT/Cargo.lock"
    run git -C "$REPO_ROOT" commit -m "$commit_title"

    if [[ $NO_PUSH -eq 1 ]]; then
        log "Skipping push (--no-push)"
        return 0
    fi
    run git -C "$REPO_ROOT" push -u "$REMOTE" "$BRANCH"

    if [[ $NO_PR -eq 1 ]]; then
        log "Skipping PR creation (--no-pr)"
        return 0
    fi

    local body=$'Automated release prep.\n\nBumps:\n'
    for entry in "${entries[@]}"; do
        local short crate package pretty version _cargo _plug
        IFS='|' read -r short crate package pretty version _cargo _plug <<<"$entry"
        body+="- ${pretty} (\`${short}\`): \`${version}\`"$'\n'
    done
    body+=$'\nAfter merging, sign and push the release tags from main:\n\n```\nscripts/release.sh tag'
    for pair in "${PAIRS[@]}"; do body+=" ${pair}"; done
    body+=$'\n```\n'

    run gh pr create \
        --repo-clone-protocol https \
        --base main \
        --head "$BRANCH" \
        --title "$commit_title" \
        --body "$body" 2>/dev/null \
        || run gh pr create --base main --head "$BRANCH" --title "$commit_title" --body "$body"
}

#------------------------------------------------------------------------------
# Subcommand: tag
#------------------------------------------------------------------------------
cmd_tag() {
    require_clean_worktree

    local current_branch
    current_branch="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD || echo "")"
    [[ "$current_branch" == "main" ]] \
        || die "tag must be run from 'main' (currently on '${current_branch:-detached}')"

    run git -C "$REPO_ROOT" fetch "$REMOTE" main
    if [[ $DRY_RUN -eq 0 ]]; then
        local local_sha remote_sha
        local_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
        remote_sha="$(git -C "$REPO_ROOT" rev-parse "$REMOTE/main")"
        [[ "$local_sha" == "$remote_sha" ]] \
            || die "local main ($local_sha) is not at $REMOTE/main ($remote_sha); run 'git pull --ff-only'"
    fi

    local -a tags=()
    local pair entry
    for pair in "${PAIRS[@]}"; do
        entry="$(validate_pair "$pair")"
        local short crate package pretty version cargo _plug
        IFS='|' read -r short crate package pretty version cargo _plug <<<"$entry"

        local actual
        actual="$(read_toml_version "$cargo")" \
            || die "could not read current version from $cargo"
        [[ "$actual" == "$version" ]] \
            || die "$cargo on main has version '$actual', expected '$version' (was the bump PR merged?)"

        local tag="${short}-v${version}"
        if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
            die "tag $tag already exists locally"
        fi
        if git -C "$REPO_ROOT" ls-remote --exit-code --tags "$REMOTE" "refs/tags/$tag" >/dev/null 2>&1; then
            die "tag $tag already exists on $REMOTE"
        fi

        log "Signing tag $tag"
        run git -C "$REPO_ROOT" tag -s -m "Spin ${pretty} Trigger v${version}" "$tag"
        tags+=("$tag")
    done

    if [[ $NO_PUSH -eq 1 ]]; then
        log "Skipping push (--no-push)"
        log "Created tags: ${tags[*]}"
        return 0
    fi

    log "Pushing tags atomically: ${tags[*]}"
    run git -C "$REPO_ROOT" push --atomic "$REMOTE" "${tags[@]}"
}

#------------------------------------------------------------------------------
# Subcommand: all
#------------------------------------------------------------------------------
cmd_all() {
    cmd_bump
    echo
    log "Bump branch pushed. Open and merge the PR, then return here."
    if [[ $DRY_RUN -eq 0 ]]; then
        read -r -p "Press Enter once the PR has merged to main (Ctrl-C to abort)... " _
    fi
    run git -C "$REPO_ROOT" fetch "$REMOTE" main
    run git -C "$REPO_ROOT" checkout main
    run git -C "$REPO_ROOT" pull --ff-only "$REMOTE" main
    cmd_tag
}

#------------------------------------------------------------------------------
main() {
    parse_args "$@"
    case "$SUBCMD" in
        bump) cmd_bump ;;
        tag)  cmd_tag  ;;
        all)  cmd_all  ;;
    esac
}

main "$@"

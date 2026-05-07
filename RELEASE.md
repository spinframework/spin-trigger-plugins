# Cutting a new release

Each trigger plugin in this monorepo is released independently using a
per-trigger tag prefix:

| Trigger | Tag prefix       | Example tag          |
| ------- | ---------------- | -------------------- |
| sqs     | `sqs-v*`         | `sqs-v0.13.1`        |
| mqtt    | `mqtt-v*`        | `mqtt-v0.8.1`        |
| cron    | `cron-v*`        | `cron-v0.5.1`        |
| command | `command-v*`     | `command-v0.6.1`     |

## One-shot release with `scripts/release.sh`

`scripts/release.sh` automates the full release flow for one or more
triggers in a single command. It opens the version-bump PR via `gh` and
later creates and pushes GPG-signed tags atomically.

Prerequisites:

- A clean working tree.
- `git`, `cargo`, `gh` (with `gh auth login` completed), and a GPG key
  configured for signing (`git config user.signingkey ...`).
- CI is green for the commit you intend to release.

Subcommands:

- `bump`  — create a release branch, bump versions in `Cargo.toml` and
  `spin-pluginify.toml` for each named trigger, refresh `Cargo.lock`,
  push the branch, and open a PR.
- `tag`   — from an up-to-date local `main`, create
  `<trigger>-v<version>` GPG-signed tags and push them atomically.
- `all`   — run `bump`, prompt you to confirm the PR has merged, then
  run `tag`.

Each argument is a `<trigger>:<version>` pair. To release SQS 0.13.1 and
MQTT 0.8.1 in one PR / one push:

```sh
scripts/release.sh all sqs:0.13.1 mqtt:0.8.1
```

Or run the steps explicitly:

```sh
# 1. Open the version-bump PR.
scripts/release.sh bump sqs:0.13.1 mqtt:0.8.1

# 2. Once the PR has merged, fast-forward main and tag:
git checkout main && git pull --ff-only
scripts/release.sh tag sqs:0.13.1 mqtt:0.8.1
```

Useful flags (all subcommands):

- `--dry-run`  — print every action; change nothing.
- `--no-push`  — skip `git push` for branches and tags.
- `--no-pr`    — skip `gh pr create` in `bump`.
- `--branch <name>` — override the auto-generated branch name in `bump`.
- `--remote <name>` — git remote (default `origin`).

Pushing a tag triggers the corresponding release workflow
(`.github/workflows/release-<trigger>.yml`), which:

- Builds the plugin for all supported targets.
- Runs `spin pluginify` to package the plugin and produce the manifest.
- Uploads the tarballs and merged manifest to a GitHub Release for the
  pushed tag.

After the release workflow finishes:

1. Open a PR in the
   [spinframework/spin-plugins](https://github.com/spinframework/spin-plugins)
   repo to update the manifest for that trigger.
2. If applicable, open PR(s) in
   [spinframework/spin-docs](https://github.com/spinframework/spin-docs)
   for any new features or behaviour changes.

## Manual fallback

If you can't or don't want to use `scripts/release.sh`, the original
manual procedure still works:

1. Confirm that [CI is green](https://github.com/spinframework/spin-trigger-plugins/actions)
   for the commit selected to be tagged.
2. Bump the version in `crates/<trigger>/Cargo.toml` and
   `crates/<trigger>/spin-pluginify.toml`. Run `cargo build --workspace`
   to update `Cargo.lock`.
3. Open a pull request with these changes and merge once approved.
4. Check out the merged commit and create a GPG-signed annotated tag
   using the appropriate prefix:

   ```sh
   git tag -s -m "Spin <Trigger> Trigger v0.X.Y" <trigger>-v0.X.Y
   git push origin <trigger>-v0.X.Y
   ```

## Canary releases

Every push to `main` automatically updates the per-trigger canary
release for any trigger whose source files changed in the push:

- `sqs-canary`, `mqtt-canary`, `cron-canary`, `command-canary`

These are GitHub prereleases and are recreated in place on every
applicable push.

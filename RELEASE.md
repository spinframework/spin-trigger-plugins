# Cutting a new release

Each trigger plugin in this monorepo is released independently using a
per-trigger tag prefix. The supported prefixes are:

| Trigger | Tag prefix       | Example tag          |
| ------- | ---------------- | -------------------- |
| sqs     | `sqs-v*`         | `sqs-v0.13.1`        |
| mqtt    | `mqtt-v*`        | `mqtt-v0.8.1`        |
| cron    | `cron-v*`        | `cron-v0.5.1`        |
| command | `command-v*`     | `command-v0.6.1`     |

To cut a new release of a trigger:

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

5. Pushing the tag triggers the corresponding release workflow
   (`.github/workflows/release-<trigger>.yml`), which:
   - Builds the plugin for all supported targets.
   - Runs `spin pluginify` to package the plugin and produce the manifest.
   - Uploads the tarballs and merged manifest to a GitHub Release for the
     pushed tag.

6. Open a PR in the
   [spinframework/spin-plugins](https://github.com/spinframework/spin-plugins)
   repo to update the manifest for that trigger.

7. If applicable, open PR(s) in
   [spinframework/spin-docs](https://github.com/spinframework/spin-docs)
   for any new features or behaviour changes.

## Canary releases

In addition, every push to `main` automatically updates the per-trigger
canary release for any trigger whose source files changed in the push:

- `sqs-canary`, `mqtt-canary`, `cron-canary`, `command-canary`

These are GitHub prereleases and are recreated in place on every
applicable push.

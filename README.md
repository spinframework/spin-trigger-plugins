# Spin Trigger Plugins

This repository is the consolidated home for the Spin trigger plugins maintained
by the [Spin Framework](https://github.com/spinframework) project. It replaces
the previously separate repositories:

- [`spin-trigger-sqs`](https://github.com/spinframework/spin-trigger-sqs)
- [`spin-trigger-mqtt`](https://github.com/spinframework/spin-trigger-mqtt)
- [`spin-trigger-cron`](https://github.com/spinframework/spin-trigger-cron)
- [`spin-trigger-command`](https://github.com/spinframework/spin-trigger-command)

See [spinframework/spin#3457](https://github.com/spinframework/spin/issues/3457)
for the consolidation proposal.

## Layout

```
crates/
  trigger-sqs/       # Amazon SQS trigger
  trigger-mqtt/      # MQTT trigger
  trigger-cron/      # Cron trigger
  trigger-command/   # Command trigger
templates/           # Spin templates (per trigger)
examples/            # Example apps (per trigger)
```

## Building

```sh
cargo build --workspace
```

## Releases

Each trigger is released independently. A push of a tag of the form
`<trigger>-v<version>` (e.g. `sqs-v0.13.0`, `mqtt-v0.5.0`, `cron-v0.4.0`,
`command-v0.2.0`) triggers a release workflow that builds the plugin,
runs `spin-pluginify`, and publishes a GitHub Release containing the
plugin tarballs and manifest.

In addition, every push to `main` updates the corresponding per-trigger
`<trigger>-canary` GitHub Release for any trigger whose source files
changed in the push (paths-filtered).

## License

This project is dual-licensed under either of:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE) or
  <https://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([LICENSE-MIT](LICENSE-MIT) or
  <https://opensource.org/licenses/MIT>)

at your option.

### Contribution

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in the work by you, as defined in the Apache-2.0
license, shall be dual licensed as above, without any additional terms or
conditions.

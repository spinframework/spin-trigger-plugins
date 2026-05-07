# Spin Trigger Plugins

This repository is the consolidated home for the Spin trigger plugins maintained
by the [Spin Framework](https://github.com/spinframework) project.

## Layout

```
crates/
  trigger-sqs/       # Amazon SQS trigger
  trigger-mqtt/      # MQTT trigger
  trigger-cron/      # Cron trigger
  trigger-command/   # Command trigger
templates/           # Spin templates
examples/            # Example apps
```

## Building

```sh
cargo build --workspace
```

## License

This project is licensed under the Apache License, Version 2.0
([LICENSE-APACHE](LICENSE-APACHE) or
<https://www.apache.org/licenses/LICENSE-2.0>).

### Contribution

Unless you explicitly state otherwise, any contribution intentionally
submitted for inclusion in the work by you, as defined in the Apache-2.0
license, shall be licensed as above, without any additional terms or
conditions.

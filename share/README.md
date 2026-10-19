# ini core

An **example extension core** for Jumpstart. It demonstrates that the cores
mechanism can host a *different, non-native* service management format: the
classic INI service layout that Jumpstart itself used before it migrated to
Kongue `.kg` units.

Nothing here is compiled into Jumpstart. The core is an ordinary extension
directory that Jumpstart discovers, validates and runs through the generic
exec backend.

## Layout

```
init.kg                 manifest (§10) declaring the operations and the backend
bin/ini-adapter         persistent exec adapter speaking the §17 exec protocol
share/example.service an INI unit you can install to try it
```

## The INI format

Units are INI files named `<unit>.service`:

```ini
[Unit]
description = Example daemon
after = network

[Service]
exec = /usr/bin/sleep 1000
execPre =
execPost =
terminal = false
reload = /bin/kill -HUP $MAINPID
```

Recognised keys:

| Section | Key | Meaning |
| --- | --- | --- |
| `Unit` | `description` | Human-readable summary |
| `Unit` | `after` | Soft ordering hint |
| `Unit` | `wantst` | Members for a target-style group |
| `Service` | `exec` | Main command line (REQUIRED) |
| `Service` | `execPre` | Run once before start |
| `Service` | `execPost` | Run once after stop |
| `Service` | `terminal` | `true` to attach to PID 1's terminal |
| `Service` | `reload` | Reload command; `$MAINPID` is substituted |

Unit names are the file base name without `.service`. Jumpstart treats them as
opaque strings, so `example` and `example.service` both resolve to the same
unit.

## Storage

| Path | Purpose |
| --- | --- |
| `/etc/jumpstart/services` | system-mode unit directory (`INI_CORE_CONFIG_DIR`) |
| `/lib/jumpstart/services` | optional read-only fallback directory |
| `~/.config/jumpstart/services` | user-mode unit directory |
| core runtime directory (`JUMPSTART_CORE_RUNTIME_DIR`, §19.1) | PIDs and logs (`INI_CORE_RUNTIME_DIR` overrides) |
| `<unit dir>/.enabled/<unit>` | enablement marker |

## Operations

The manifest declares these subsystems and operations, all routed to
`bin/ini-adapter` as a persistent adapter:

- `core.verify`
- `unit.list`, `unit.resolve`, `unit.load`, `unit.validate`,
  `unit.translate`, `unit.activate`, `unit.deactivate`
- `service.start`, `service.stop`, `service.restart`, `service.reload`,
  `service.kill`, `service.enable`, `service.disable`, `service.status`

`unit.translate` renders the INI unit as the equivalent Kongue `.kg` unit,
which is a small illustration of how a compatibility core can help migration.

## Installing

Copy this directory into a core root, for example:

```sh
# system mode
sudo mkdir -p /usr/lib/jumpstart/cores
sudo cp -r examples/cores/ini /usr/lib/jumpstart/cores/ini

# user mode
mkdir -p ~/.local/lib/jumpstart/cores
cp -r examples/cores/ini ~/.local/lib/jumpstart/cores/ini
```

Then:

```sh
jumpctl cores list
jumpctl cores enable ini
jumpctl cores load ini
jumpctl cores run ini core.verify
```

To try a unit, copy `share/example.service` to your unit directory and use
`jumpctl start example`.

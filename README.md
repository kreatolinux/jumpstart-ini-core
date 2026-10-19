# jumpstart-ini-core

A [Jumpstart](https://github.com/kreatolinux/src) core for ini: a minimal INI-style unit format (Python adapter). Reference core for writing your own.

The repository root is the core directory. Installing means copying it to
`/usr/lib/jumpstart/cores/ini/` (`make install`), then `jumpctl cores enable ini`.
See `share/README.md` for what the core supports and how it is configured.

The Jumpstart cores specification (RFC 0001, `text/0001-jumpstart-cores.md` in the
`rfcs` repository) is the source of truth for the manifest, exec protocol and
operations. Try any operation without the daemon:
`jumpctl cores run ini unit.list`.

## Tests

The tests import Jumpstart's core runtime and the `jumpstartcore` library from
a Jumpstart checkout next to this repository (`../src-2`; edit `nim.cfg`
otherwise):

```sh
make test
```

## License

GPL-3.0 (`LICENSE`).

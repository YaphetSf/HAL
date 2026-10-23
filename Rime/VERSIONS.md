# Pinned Rime versions

Snapshots taken 2026-08-24. Both are vendored, not fetched at build time (D4, D5).
Changing either version means redoing the steps below and updating this file.

## librime 1.17.0

- Release: https://github.com/rime/librime/releases/tag/1.17.0
- Asset: `rime-33e7814-macOS-universal.tar.bz2` (official prebuilt, universal x86_64 + arm64)
- librime commit `33e7814`
- Bundled plugins: hchunhui/librime-lua `ec52e48`, lotem/librime-octagram `dfcc151`,
  rime/librime-predict `920bd41`

Vendored into `Rime/lib/`: `librime.1.17.0.dylib` (plus the upstream `librime.1.dylib` and
`librime.dylib` symlinks), `rime-plugins/*.dylib`, `include/*.h`.

The dylib links only against `libSystem` and `libc++` — every dependency (glog, yaml-cpp,
leveldb, marisa, opencc) is static, so the `rime-deps` asset is not needed. Its install
name is `@rpath/librime.1.dylib`, so the app embeds it under exactly that name.

## rime-ice (雾凇拼音)

- Repo: https://github.com/iDvel/rime-ice
- Commit: `75e6572bebc05b49021e842949ce947882e3e4b2` (2026-08-22)
- Tarball: https://github.com/iDvel/rime-ice/archive/75e6572bebc05b49021e842949ce947882e3e4b2.tar.gz

Vendored into `Rime/rime-ice/`, with everything outside the scope in PLAN.md §1.2 removed:
the double pinyin schemas, T9, the Squirrel and Weasel front-end configs, `others/`, the
repo's own docs, and the double-pinyin variants of `en_dicts/cn_en_*.txt`.

Kept: `default.yaml`, `rime_ice.{schema,dict}.yaml`, `melt_eng.*`, `radical_pinyin.*`
(rime_ice uses it for reverse lookup), `cn_dicts/`, `en_dicts/en*`, `opencc/`, `lua/`,
`symbols_*.yaml`, `custom_phrase.txt`, `LICENSE`.

`default.yaml` still lists the removed schemas in `schema_list`; HAL narrows that to
`rime_ice` with a `default.custom.yaml` patch in the user directory rather than editing the
snapshot (D12).

## Licences (D20)

librime is BSD-3-Clause, rime-ice is GPL-3.0. Personal use only, no distribution — revisit
D20 before that changes.

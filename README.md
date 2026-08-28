<p align="center">
  <img src="Resources/Brand/logo.svg" alt="HAL" width="120" height="120">
</p>

<h1 align="center">HAL</h1>

<p align="center">
  Simplified Chinese Pinyin input method for macOS.<br>
  Built with InputMethodKit, librime, and rime-ice.
</p>

## Features

- **Candidate window at the caret**, fully customisable input window.
- **Caps Lock switches Chinese and English** inside HAL, without handing the
  keyboard back to another input source.
- **`EN+`** (Shift + Caps Lock) completes English words from the system
  dictionary as you type; **`EN`** is a plain passthrough.
- **Fuzzy Pinyin rules you write yourself** — custom map fuzzy Pinyin or any input to any syllable,

## Requirements

macOS 26+, Apple Silicon.

## Install

Download the DMG from [Releases](https://github.com/YaphetSf/HAL/releases). Open `HAL.app`,
then add HAL in System Settings → Keyboard → Text Input → Edit.

Control centre: `~/Applications/HAL.app`. Rime overrides: `~/Library/Application Support/HAL/Rime`.

## Build from source

```bash
brew install xcodegen
scripts/build-install.sh
scripts/package-release.sh
xcodebuild test
```

## Licence

HAL: [MIT](LICENSE). librime: BSD-3-Clause. rime-ice: GPL-3.0. Versions:
[Rime/VERSIONS.md](Rime/VERSIONS.md).

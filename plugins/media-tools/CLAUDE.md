# media-tools

> YouTube audio download and iOS device media transfer workflows.

**Hub**: [Root CLAUDE.md](../../CLAUDE.md) | **Sibling**: [plugins/CLAUDE.md](../../plugins/CLAUDE.md)

**Skill**: [youtube-to-bookplayer](./skills/youtube-to-bookplayer/SKILL.md) — Download YouTube audio and push to BookPlayer on iPhone via USB.

---

## Skills

- [youtube-to-bookplayer](./skills/youtube-to-bookplayer/SKILL.md)

## Dependencies

All tools are installed via Homebrew or pip/uvx. The skill runs preflight checks and fails fast with install commands if anything is missing.

| Tool              | Purpose                                            | Install                                                           |
| ----------------- | -------------------------------------------------- | ----------------------------------------------------------------- |
| `yt-dlp`          | YouTube audio extraction                           | `brew install yt-dlp`                                             |
| `ffmpeg`          | Audio format conversion (auto-invoked by yt-dlp)   | `brew install ffmpeg`                                             |
| `exiftool`        | M4A metadata tagging (title, artist, album)        | `brew install exiftool`                                           |
| `pymobiledevice3` | iOS device communication via USB (HouseArrest API) | `uvx --python 3.13 --from pymobiledevice3 pymobiledevice3 --help` |

## Critical: VendDocuments vs VendContainer

**BookPlayer uses VendDocuments mode**, not VendContainer.

- The CLI command `pymobiledevice3 apps push` uses VendContainer mode internally and **fails silently** on BookPlayer
- The **Python API** with `documents_only=True` uses VendDocuments mode and **works correctly**
- This is the single most important implementation detail in this plugin — see the skill's Phase 4 for the correct Python approach

## Conventions

- **Python**: 3.13 only, via `uvx --python 3.13`
- **Temp files**: `mktemp -d` for working directories, cleaned up after success
- **Device selection**: `create_using_usbmux()` auto-selects first connected device
- **No hardcoded paths**: Use `$HOME`, `command -v`, auto-detection throughout

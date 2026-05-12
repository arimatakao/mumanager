# MuManager

MuManager is an interactive Bash script for browsing local music files and Extended M3U playlists.

The script scans the directory where it is launched, including nested directories, and lets you inspect audio files either quickly by file path and size or in a detailed metadata table.

## Requirements

MuManager uses:

- `bash`
- `find`
- `sort`
- `stat`
- `column` (optional, for aligned table output)
- `realpath` (optional, for relative playlist paths)
- `exiftool` — required for metadata views and lyrics fetch
- `jaq` — required for metadata views and lyrics fetch
- `curl` — required for fetching lyrics from lrclib.net

## Usage

Install with one command:

```bash
curl -fsSL https://raw.githubusercontent.com/arimatakao/mumanager/main/install.sh | bash
```

For a system-wide install:

```bash
curl -fsSL https://raw.githubusercontent.com/arimatakao/mumanager/main/install.sh | sudo bash -s -- --system
```

After installation, run:

```bash
mumanager
```

For local development, make the script executable:

```bash
chmod +x mumanager.sh
```

Run it:

```bash
./mumanager.sh
```

## Options and Actions

```
Usage: mumanager.sh [OPTIONS] [ACTIONS]

Options:
  -d, --dir DIR              Set directory to scan
  -h, --help                 Show this help

Actions:
  -c, --change-dir           Change scan directory interactively
  -t, --table                View music metadata table
  -f, --files                View music files (fast scan, no metadata)
  -p, --playlist             View playlist
  -e, --edit-playlist        Edit playlist
  -l, --lyrics               Fetch lyrics (.lrc) from lrclib.net
  -m, --menu                 Open interactive menu
```

If no action is given, the interactive menu opens. Actions can be combined:

```bash
./mumanager.sh -d ~/Music -f
./mumanager.sh --dir ~/Music --table
./mumanager.sh -d ~/Music --playlist
```

## Playlist Support

MuManager supports local Extended M3U playlists:

- `.m3u`
- `.m3u8`

Playlist metadata lines such as `#EXTM3U` and `#EXTINF` are ignored when resolving tracks. Relative track paths are resolved from the playlist file location.

When editing a playlist, added tracks are stored relative to the playlist location when possible. The editor uses keyboard navigation: `j`/`k` to move, `Space` to toggle a track, `s` to save, `q` to cancel.

## Lyrics

MuManager can fetch synced (`.lrc`) lyrics from [lrclib.net](https://lrclib.net) using the `-l` / `--lyrics` flag or menu option 6. It reads track metadata (`exiftool`) to build the query and saves the result as a `.lrc` file next to the audio file. Requires `exiftool`, `jaq`, and `curl`.

# MuManager

MuManager is an interactive Bash script for browsing local music files and Extended M3U playlists.

The script scans the directory where it is launched, including nested directories, and lets you inspect audio files either quickly by file path and size or in a detailed metadata table.

## Requirements

MuManager uses:

- `bash`
- `find`
- `sort`
- `stat`
- `column`
- `ffprobe` from FFmpeg
- `jq`

`ffprobe` and `jq` are required for metadata-based views.

## Usage

Make the script executable:

```bash
chmod +x mumanager.sh
```

Run it:

```bash
./mumanager.sh
```

## Playlist Support

MuManager supports local Extended M3U playlists:

- `.m3u`
- `.m3u8`

Playlist metadata lines such as `#EXTM3U` and `#EXTINF` are ignored when resolving tracks. Relative track paths are resolved from the playlist file location.

When editing a playlist, added tracks are written with an `#EXTINF` line when metadata is available. Tracks are stored relative to the playlist location when possible.

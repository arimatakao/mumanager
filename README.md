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

Then choose an action from the interactive menu:

```text
1) Change scan directory
2) View music table
3) View music files (fast scan)
4) View playlist
0) Exit
```

## Playlist Support

MuManager supports local Extended M3U playlists:

- `.m3u`
- `.m3u8`

Playlist metadata lines such as `#EXTM3U` and `#EXTINF` are ignored when resolving tracks. Relative track paths are resolved from the playlist file location.

#!/usr/bin/env bash

set -o pipefail

SCAN_DIR="$PWD"
PAUSE_AFTER_ACTION=1
LOOP_PLAYLISTS=1
CLEAR_HEADER=1

AUDIO_EXTENSIONS=(
  mp3 flac wav ogg oga opus m4a aac alac wma aiff aif ape
)

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

pause() {
  if (( ! PAUSE_AFTER_ACTION )); then
    return 0
  fi

  printf '\nPress Enter to continue...'
  read -r _
}

check_metadata_dependencies() {
  command -v exiftool >/dev/null 2>&1 || die 'exiftool is required to read metadata.'
  command -v jaq >/dev/null 2>&1 || die 'jaq is required to process metadata.'
}

check_lyrics_dependencies() {
  check_metadata_dependencies
  command -v curl >/dev/null 2>&1 || die 'curl is required to fetch lyrics.'
}

print_header() {
  (( CLEAR_HEADER )) && clear
  printf 'Scan directory: %s\n\n' "$(display_path "$SCAN_DIR")"
}

show_help() {
  cat <<'EOF'
MuManager scans a directory for music files, shows file and metadata tables,
and helps view or edit local M3U/M3U8 playlists.

Dependencies: exiftool, jaq (for metadata); curl (for lyrics); column, realpath (optional).

Project: https://github.com/arimatakao/mumanager

Usage: mumanager.sh [OPTIONS] [ACTIONS]

Options:
  -d, --dir DIR              Set directory to scan
  -h, --help                 Show this help

Actions:
  -c, --change-dir           Change scan directory interactively
  -t, --table                View music table
      --music-table
  -f, --files                View music files (fast scan)
      --view-files
  -p, --playlist             View playlist
      --view-playlist
  -e, --edit-playlist        Edit playlist
      --edit
  -l, --lyrics               Fetch lyrics (.lrc) from lrclib.net
      --fetch-lyrics
  -m, --menu                 Open interactive menu

If no action is provided, the interactive menu is opened.
Examples:
  ./mumanager.sh -d ~/Music -f
  ./mumanager.sh --dir ~/Music --table
  ./mumanager.sh -d ~/Music --playlist
EOF
}

show_menu() {
  print_header
  printf 'Choose an action:\n'
  printf '  1) Change scan directory\n'
  printf '  2) View music table\n'
  printf '  3) View music files (fast scan)\n'
  printf '  4) View playlist\n'
  printf '  5) Edit playlist\n'
  printf '  6) Fetch lyrics (.lrc)\n'
  printf '  0) Exit\n\n'
  printf 'Your choice: '
}

print_goodbye() {
  local phrases=(
    'Let it be.'
    'Here comes the sun.'
    'We will rock you.'
    'The show must go on.'
    'Nothing else matters.'
    'Smells like teen spirit.'
    "Hey ho, let's go!"
    'No woman, no cry.'
    'What a wonderful world.'
    'I got you, babe.'
    'Imagine.'
    'Born to run.'
    'Purple rain.'
    'Sweet dreams are made of this.'
    'I will survive.'
    'We are the champions.'
    'Come as you are.'
    'Like a rolling stone.'
    'Should I stay or should I go?'
    'Hit the road, Jack.'
    'All you need is love.'
    'Let there be rock.'
    'Get up, stand up.'
    'Every little thing is gonna be alright.'
    'Good vibrations.'
    'Walk this way.'
    'Respect.'
    'Dream on.'
    'Start me up.'
    'Hello, goodbye.'
  )

  printf '%s\n' "${phrases[RANDOM % ${#phrases[@]}]}"
}

build_find_args() {
  FIND_ARGS=('(')

  local first=1
  for ext in "${AUDIO_EXTENSIONS[@]}"; do
    if (( first )); then
      first=0
    else
      FIND_ARGS+=(-o)
    fi
    FIND_ARGS+=(-iname "*.$ext")
  done

  FIND_ARGS+=(')')
}

format_size() {
  local bytes="$1"
  if [[ -z "$bytes" || "$bytes" == "null" ]]; then
    printf '-'
    return
  fi

  if (( bytes >= 1073741824 )); then
    awk -v size="$bytes" 'BEGIN { printf "%.2f GB", size / 1073741824 }'
  elif (( bytes >= 1048576 )); then
    awk -v size="$bytes" 'BEGIN { printf "%.2f MB", size / 1048576 }'
  elif (( bytes >= 1024 )); then
    awk -v size="$bytes" 'BEGIN { printf "%.2f KB", size / 1024 }'
  else
    printf '%s B' "$bytes"
  fi
}

display_path() {
  local path="$1"

  if [[ -n "$HOME" && "$path" == "$HOME" ]]; then
    printf '~'
  elif [[ -n "$HOME" && "$path" == "$HOME/"* ]]; then
    printf '~/%s' "${path#"$HOME/"}"
  else
    printf '%s' "$path"
  fi
}

batch_song_rows() {
  local argfile
  argfile=$(mktemp) || die 'failed to create a temporary file.'
  printf '%s\n' "$@" >"$argfile"

  exiftool -json \
    -Title -FileName \
    -Composer -Artist -AlbumArtist \
    -Album -Duration -AudioBitrate -FileSize \
    -Lyrics -UnsynchronisedLyrics \
    -@ "$argfile" 2>/dev/null | \
  jaq -r '
    def scalar: if type == "array" then join(", ") else . end;
    sort_by((.Title // .FileName // "") | tostring | ascii_downcase) | .[] | [
      (.Title // .FileName // "-" | scalar),
      (.Composer // .Artist // .AlbumArtist // "-" | scalar),
      (.Album // "-" | scalar),
      (.AudioBitrate // "-" | scalar),
      (if ((.Lyrics // .UnsynchronisedLyrics // "") | scalar | length) > 0 then "yes" else "no" end),
      (.Duration // "-" | scalar),
      (.FileSize // "-" | scalar | .[0:8])
    ] | @tsv'

  rm -f "$argfile"
}

view_songs() {
  check_metadata_dependencies

  print_header
  printf 'Scanning audio metadata...\n\n'

  local -a files FIND_ARGS
  build_find_args
  mapfile -d '' -t files < <(find "$SCAN_DIR" -type f "${FIND_ARGS[@]}" -print0 2>/dev/null | sort -z)

  if (( ${#files[@]} == 0 )); then
    printf 'No music files found in directory: %s\n' "$(display_path "$SCAN_DIR")"
    pause
    return
  fi

  local tmp
  tmp=$(mktemp) || die 'failed to create a temporary file.'
  printf 'Track title\tComposer\tAlbum\tBitrate\tHas lyrics\tLength\tSize\n' >"$tmp"
  batch_song_rows "${files[@]}" >>"$tmp"

  if command -v column >/dev/null 2>&1; then
    column -t -s $'\t' -o ' │ ' "$tmp"
  else
    cat "$tmp"
  fi

  printf '\nTotal files: %d\n' "${#files[@]}"
  rm -f "$tmp"
  pause
}

view_music_files() {
  print_header
  printf 'Scanning audio files...\n\n'

  local tmp rows=0
  tmp=$(mktemp) || die 'failed to create a temporary file.'
  local -a FIND_ARGS
  build_find_args

  printf 'File size\tPath\n' >"$tmp"

  while IFS= read -r -d '' file; do
    printf '%s\t%s\n' \
      "$(format_size "$(stat -c '%s' "$file" 2>/dev/null)")" \
      "$(display_path "$file")" >>"$tmp"
    rows=$((rows + 1))
  done < <(find "$SCAN_DIR" -type f "${FIND_ARGS[@]}" -print0 2>/dev/null | sort -z)

  if (( rows == 0 )); then
    printf 'No music files found in directory: %s\n' "$(display_path "$SCAN_DIR")"
  else
    if command -v column >/dev/null 2>&1; then
      column -t -s $'\t' -o ' │ ' "$tmp"
    else
      cat "$tmp"
    fi
    printf '\nTotal files: %d\n' "$rows"
  fi

  rm -f "$tmp"
  pause
}

select_playlist() {
  local -n selected_path_ref=$1
  local -a playlists
  mapfile -d '' -t playlists < <(find "$SCAN_DIR" -type f \( -iname '*.m3u' -o -iname '*.m3u8' \) -print0 2>/dev/null | sort -z)

  print_header
  if (( ${#playlists[@]} == 0 )); then
    printf 'No playlists found in directory: %s\n' "$(display_path "$SCAN_DIR")"
    pause
    selected_path_ref=''
    return 1
  fi

  printf 'Select a playlist:\n'

  local index=1
  local playlist
  for playlist in "${playlists[@]}"; do
    printf '  %d) %s\n' "$index" "$(display_path "$playlist")"
    index=$((index + 1))
  done

  printf '  0) Back\n\n'
  printf 'Your choice: '

  local choice
  read -r choice

  case "$choice" in
    0)
      selected_path_ref=''
      return 1
      ;;
    ''|*[!0-9]*)
      printf '\nUnknown option: %s\n' "$choice"
      pause
      return 1
      ;;
    *)
      if (( choice < 1 || choice > ${#playlists[@]} )); then
        printf '\nUnknown option: %s\n' "$choice"
        pause
        return 1
      fi
      selected_path_ref="${playlists[$((choice - 1))]}"
      ;;
  esac
}

resolve_playlist_track() {
  local playlist_dir="$1"
  local entry="$2"

  case "$entry" in
    http://*|https://*)
      printf ''
      ;;
    /*)
      printf '%s' "$entry"
      ;;
    *)
      printf '%s/%s' "$playlist_dir" "$entry"
      ;;
  esac
}

canonical_path() {
  local path="$1"

  if command -v realpath >/dev/null 2>&1; then
    realpath -m "$path"
  else
    local dir base
    dir=$(dirname "$path")
    base=$(basename "$path")
    printf '%s/%s' "$(cd "$dir" 2>/dev/null && pwd -P)" "$base"
  fi
}

relative_playlist_entry() {
  local playlist_dir="$1"
  local file="$2"

  if command -v realpath >/dev/null 2>&1; then
    realpath --relative-to="$playlist_dir" "$file" 2>/dev/null && return
  fi

  printf '%s' "$file"
}

collect_audio_files() {
  local -n files_ref=$1
  local -a FIND_ARGS
  build_find_args

  mapfile -d '' -t files_ref < <(find "$SCAN_DIR" -type f "${FIND_ARGS[@]}" -print0 2>/dev/null | sort -z)
}

load_playlist_selection() {
  local playlist_path="$1"
  local -n selected_ref=$2

  local playlist_dir line track_path canonical
  playlist_dir=$(cd "$(dirname "$playlist_path")" && pwd) || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == \#* ]] && continue

    track_path=$(resolve_playlist_track "$playlist_dir" "$line")
    [[ -z "$track_path" || ! -f "$track_path" ]] && continue

    canonical=$(canonical_path "$track_path")
    selected_ref["$canonical"]=1
  done <"$playlist_path"
}

shorten_text() {
  local text="$1"
  local width="$2"

  if (( width <= 0 )); then
    printf ''
  elif (( ${#text} <= width )); then
    printf '%s' "$text"
  elif (( width <= 3 )); then
    printf '%.*s' "$width" "$text"
  else
    printf '%.*s...' "$((width - 3))" "$text"
  fi
}

draw_playlist_editor() {
  local playlist_path="$1"
  local cursor="$2"
  local offset="$3"
  local changed="$4"
  local -n files_ref=$5
  local -n selected_ref=$6

  local rows cols visible_rows end i file canonical marker pointer status path_width
  rows=$(tput lines 2>/dev/null || printf 24)
  cols=$(tput cols 2>/dev/null || printf 80)
  visible_rows=$(( rows - 8 ))
  (( visible_rows < 5 )) && visible_rows=5
  end=$(( offset + visible_rows ))
  (( end > ${#files_ref[@]} )) && end=${#files_ref[@]}
  path_width=$(( cols - 12 ))
  (( path_width < 20 )) && path_width=20

  print_header
  printf 'Editing playlist: %s\n' "$(display_path "$playlist_path")"
  printf 'Keys: j/k move, g/G top/bottom, Ctrl-D/Ctrl-U page, Space toggle, s save, q cancel\n\n'
  printf '    Sel  File\n'

  for (( i = offset; i < end; i++ )); do
    file="${files_ref[$i]}"
    canonical=$(canonical_path "$file")
    marker='[ ]'
    [[ -n "${selected_ref[$canonical]+x}" ]] && marker='[x]'
    pointer=' '
    (( i == cursor )) && pointer='>'
    printf '%s %s  %s\n' "$pointer" "$marker" "$(shorten_text "$(display_path "$file")" "$path_width")"
  done

  printf '\n'
  status='saved'
  (( changed )) && status='modified'
  printf 'Track %d/%d, playlist %s.\n' "$(( cursor + 1 ))" "${#files_ref[@]}" "$status"
}

write_playlist_selection() {
  local playlist_path="$1"
  local -n files_ref=$2
  local -n selected_ref=$3

  local playlist_dir tmp file canonical
  playlist_dir=$(cd "$(dirname "$playlist_path")" && pwd) || return 1
  tmp=$(mktemp) || die 'failed to create a temporary file.'

  printf '#EXTM3U\n' >"$tmp"
  for file in "${files_ref[@]}"; do
    canonical=$(canonical_path "$file")
    [[ -z "${selected_ref[$canonical]+x}" ]] && continue
    printf '%s\n' "$(relative_playlist_entry "$playlist_dir" "$file")" >>"$tmp"
  done

  mv "$tmp" "$playlist_path"
}

collect_playlist_changes() {
  local -n files_ref=$1
  local -n original_ref=$2
  local -n selected_ref=$3
  local -n added_ref=$4
  local -n removed_ref=$5

  local file canonical
  added_ref=()
  removed_ref=()

  for file in "${files_ref[@]}"; do
    canonical=$(canonical_path "$file")
    if [[ -n "${selected_ref[$canonical]+x}" && -z "${original_ref[$canonical]+x}" ]]; then
      added_ref+=("$file")
    elif [[ -z "${selected_ref[$canonical]+x}" && -n "${original_ref[$canonical]+x}" ]]; then
      removed_ref+=("$file")
    fi
  done
}

print_changed_files() {
  local title="$1"
  shift

  printf '%s (%d):\n' "$title" "$#"
  if (( $# == 0 )); then
    printf '  -\n'
    return
  fi

  local file
  for file in "$@"; do
    printf '  %s\n' "$(display_path "$file")"
  done
}

run_playlist_editor() {
  local playlist_path="$1"
  local -a files
  local -A original selected

  collect_audio_files files
  print_header
  if (( ${#files[@]} == 0 )); then
    printf 'No music files found in directory: %s\n' "$(display_path "$SCAN_DIR")"
    pause
    return
  fi

  load_playlist_selection "$playlist_path" original
  load_playlist_selection "$playlist_path" selected

  local cursor=0 offset=0 changed=0 rows visible_rows key old_stty
  old_stty=$(stty -g)
  trap 'stty "$old_stty"; trap - INT TERM; return 130' INT TERM
  stty -echo -icanon time 0 min 1

  while true; do
    rows=$(tput lines 2>/dev/null || printf 24)
    visible_rows=$(( rows - 8 ))
    (( visible_rows < 5 )) && visible_rows=5
    (( cursor < offset )) && offset=$cursor
    (( cursor >= offset + visible_rows )) && offset=$(( cursor - visible_rows + 1 ))
    (( offset < 0 )) && offset=0

    draw_playlist_editor "$playlist_path" "$cursor" "$offset" "$changed" files selected

    IFS= read -r -s -n 1 key
    case "$key" in
      j)
        (( cursor < ${#files[@]} - 1 )) && cursor=$(( cursor + 1 ))
        ;;
      k)
        (( cursor > 0 )) && cursor=$(( cursor - 1 ))
        ;;
      g)
        cursor=0
        ;;
      G)
        cursor=$(( ${#files[@]} - 1 ))
        ;;
      $'\004')
        cursor=$(( cursor + visible_rows / 2 ))
        (( cursor > ${#files[@]} - 1 )) && cursor=$(( ${#files[@]} - 1 ))
        ;;
      $'\025')
        cursor=$(( cursor - visible_rows / 2 ))
        (( cursor < 0 )) && cursor=0
        ;;
      ' ')
        local canonical
        canonical=$(canonical_path "${files[$cursor]}")
        if [[ -n "${selected[$canonical]+x}" ]]; then
          unset 'selected[$canonical]'
        else
          selected["$canonical"]=1
        fi
        changed=1
        ;;
      s)
        local -a added removed
        collect_playlist_changes files original selected added removed
        stty "$old_stty"
        trap - INT TERM
        write_playlist_selection "$playlist_path" files selected
        print_header
        printf 'Playlist saved: %s\n\n' "$(display_path "$playlist_path")"
        print_changed_files 'Added files' "${added[@]}"
        printf '\n'
        print_changed_files 'Removed files' "${removed[@]}"
        pause
        return
        ;;
      q)
        stty "$old_stty"
        trap - INT TERM
        print_header
        if (( changed )); then
          printf 'Changes discarded.\n'
        else
          printf 'No changes made.\n'
        fi
        pause
        return
        ;;
    esac
  done
}

edit_playlist() {
  while true; do
    local playlist_path
    select_playlist playlist_path || return
    run_playlist_editor "$playlist_path"
    (( LOOP_PLAYLISTS )) || return
  done
}

view_playlist() {
  check_metadata_dependencies

  while true; do
    local playlist_path
    select_playlist playlist_path || return

    print_header
    printf 'Reading playlist: %s\n\n' "$(display_path "$playlist_path")"

    local playlist_dir line track_path
    local -a track_files=()
    local missing=0 unsupported=0 total_files=0

    playlist_dir=$(cd "$(dirname "$playlist_path")" && pwd) || {
      printf 'Failed to enter playlist directory.\n'
      pause
      (( LOOP_PLAYLISTS )) || return
      continue
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
      line=${line%$'\r'}
      [[ -z "$line" || "$line" == \#* ]] && continue

      track_path=$(resolve_playlist_track "$playlist_dir" "$line")
      if [[ -z "$track_path" ]]; then
        unsupported=$(( unsupported + 1 ))
        continue
      fi

      total_files=$(( total_files + 1 ))

      if [[ ! -f "$track_path" ]]; then
        missing=$(( missing + 1 ))
        continue
      fi

      track_files+=("$track_path")
    done <"$playlist_path"

    local tmp
    tmp=$(mktemp) || die 'failed to create a temporary file.'
    printf 'Track title\tComposer\tAlbum\tBitrate\tHas lyrics\tLength\tSize\n' >"$tmp"

    if (( ${#track_files[@]} > 0 )); then
      batch_song_rows "${track_files[@]}" >>"$tmp"
    fi

    if (( ${#track_files[@]} == 0 )); then
      printf 'No readable local music files found in playlist.\n'
    else
      if command -v column >/dev/null 2>&1; then
        column -t -s $'\t' -o ' │ ' "$tmp"
      else
        cat "$tmp"
      fi
    fi

    printf '\nMissing files: %d\n' "$missing"
    printf 'Total files: %d\n' "$total_files"

    if (( unsupported > 0 )); then
      printf 'Unsupported remote playlist entries skipped: %d\n' "$unsupported"
    fi

    rm -f "$tmp"
    pause
    (( LOOP_PLAYLISTS )) || return
  done
}

change_scan_dir() {
  print_header
  printf 'Enter a directory path, or leave empty for the current directory:\n> '
  local new_dir
  read -r new_dir

  if [[ -z "$new_dir" ]]; then
    new_dir="$PWD"
  fi

  if [[ ! -d "$new_dir" ]]; then
    printf '\nDirectory does not exist: %s\n' "$(display_path "$new_dir")"
    pause
    return
  fi

  SCAN_DIR=$(cd "$new_dir" && pwd) || {
    printf '\nFailed to enter directory: %s\n' "$(display_path "$new_dir")"
    pause
    return
  }
}

set_scan_dir() {
  local new_dir="$1"

  [[ -n "$new_dir" ]] || die 'directory path is required.'
  [[ -d "$new_dir" ]] || die "directory does not exist: $new_dir"

  SCAN_DIR=$(cd "$new_dir" && pwd) || die "failed to enter directory: $new_dir"
}

# Sets globals _LYRICS_TYPE (synced|plain) and _LYRICS_BODY on success, returns 0.
# On failure sets _LYRICS_TYPE to an error token and returns 1.
_query_lrclib() {
  local file="$1"
  _LYRICS_TYPE=''
  _LYRICS_BODY=''

  local meta
  meta=$(exiftool -json -n -Title -Artist -AlbumArtist -Album -Duration "$file" 2>/dev/null | \
    jaq -r 'if length > 0 then .[0] | [
      (.Artist // .AlbumArtist // ""),
      (.Title // ""),
      (.Album // ""),
      ((.Duration // 0) | if type == "number" then floor else 0 end | tostring)
    ] | @tsv else "" end' 2>/dev/null) || { _LYRICS_TYPE='error'; return 1; }

  [[ -z "$meta" ]] && { _LYRICS_TYPE='error'; return 1; }

  local artist title album duration_secs
  IFS=$'\t' read -r artist title album duration_secs <<< "$meta"

  if [[ -z "$title" ]]; then
    _LYRICS_TYPE='no title in metadata'
    return 1
  fi

  local -a curl_args=(-s -G --max-time 15)
  curl_args+=(--data-urlencode "track_name=$title")
  [[ -n "$artist" ]] && curl_args+=(--data-urlencode "artist_name=$artist")
  [[ -n "$album" ]] && curl_args+=(--data-urlencode "album_name=$album")
  [[ "${duration_secs:-0}" != "0" ]] && curl_args+=(--data-urlencode "duration=$duration_secs")

  local response http_code body
  response=$(curl "${curl_args[@]}" -w $'\n%{http_code}' 'https://lrclib.net/api/get' 2>/dev/null)
  http_code=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | head -n -1)

  if [[ "$http_code" != "200" ]]; then
    _LYRICS_TYPE='not found'
    return 1
  fi

  local synced plain
  synced=$(printf '%s' "$body" | jaq -r '.syncedLyrics // empty' 2>/dev/null)
  plain=$(printf '%s' "$body" | jaq -r '.plainLyrics // empty' 2>/dev/null)

  if [[ -n "$synced" ]]; then
    _LYRICS_TYPE='synced'
    _LYRICS_BODY="$synced"
    return 0
  elif [[ -n "$plain" ]]; then
    _LYRICS_TYPE='plain'
    _LYRICS_BODY="$plain"
    return 0
  else
    _LYRICS_TYPE='no lyrics in response'
    return 1
  fi
}

fetch_lyrics() {
  check_lyrics_dependencies

  local -a files FIND_ARGS
  build_find_args
  mapfile -d '' -t files < <(find "$SCAN_DIR" -type f "${FIND_ARGS[@]}" -print0 2>/dev/null | sort -z)

  if (( ${#files[@]} == 0 )); then
    print_header
    printf 'No music files found in directory: %s\n' "$(display_path "$SCAN_DIR")"
    pause
    return
  fi

  local cols path_width
  cols=$(tput cols 2>/dev/null || printf 80)
  path_width=$(( cols - 16 ))
  (( path_width < 30 )) && path_width=30

  while true; do
    print_header
    printf 'Select a file to fetch lyrics for:\n\n'

    local i file lrc_marker
    for (( i = 0; i < ${#files[@]}; i++ )); do
      file="${files[$i]}"
      lrc_marker=''
      [[ -f "${file%.*}.lrc" ]] && lrc_marker=' [lrc]'
      printf '  %d) %s%s\n' \
        "$(( i + 1 ))" \
        "$(shorten_text "$(display_path "$file")" "$path_width")" \
        "$lrc_marker"
    done

    printf '  0) Back\n\n'
    printf 'Your choice: '

    local choice
    read -r choice

    case "$choice" in
      0)
        return
        ;;
      ''|*[!0-9]*)
        printf '\nUnknown option: %s\n' "$choice"
        pause
        continue
        ;;
      *)
        if (( choice < 1 || choice > ${#files[@]} )); then
          printf '\nUnknown option: %s\n' "$choice"
          pause
          continue
        fi
        ;;
    esac

    local selected="${files[$((choice - 1))]}"
    local lrc_path="${selected%.*}.lrc"

    print_header
    printf 'Searching lyrics for: %s\n' "$(display_path "$selected")"
    printf 'Querying lrclib.net...\n'

    _query_lrclib "$selected"

    if [[ -z "$_LYRICS_BODY" ]]; then
      printf '\nResult: %s\n' "$_LYRICS_TYPE"
      pause
      continue
    fi

    local total_lines
    total_lines=$(printf '%s\n' "$_LYRICS_BODY" | wc -l | tr -d ' ')

    print_header
    printf 'Lyrics preview (%s) — %s\n\n' "$_LYRICS_TYPE" "$(display_path "$selected")"
    printf '%s\n' "$_LYRICS_BODY" | head -n 10
    printf '\n... (%d lines total)\n' "$total_lines"

    if [[ -f "$lrc_path" ]]; then
      printf '\nNote: %s already exists and will be overwritten.\n' "$(display_path "$lrc_path")"
    fi

    printf '\nSave these lyrics? [y/N] '
    local confirm
    read -r confirm

    case "$confirm" in
      y|Y|yes|YES)
        printf '%s\n' "$_LYRICS_BODY" > "$lrc_path"
        printf '\nSaved: %s\n' "$(display_path "$lrc_path")"
        pause
        ;;
      *)
        printf '\nNot saved.\n'
        pause
        ;;
    esac
  done
}

run_action() {
  case "$1" in
    change-dir)   change_scan_dir ;;
    table)        view_songs ;;
    files)        view_music_files ;;
    playlist)     view_playlist ;;
    edit-playlist) edit_playlist ;;
    lyrics)       fetch_lyrics ;;
    menu)         main_loop ;;
    *) die "unknown action: $1" ;;
  esac
}

parse_arguments() {
  ACTIONS=()

  while (($#)); do
    case "$1" in
      -d|--dir)
        shift
        (($#)) || die 'missing directory after -d/--dir.'
        set_scan_dir "$1"
        ;;
      --dir=*)
        set_scan_dir "${1#*=}"
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      -c|--change-dir)
        ACTIONS+=(change-dir)
        ;;
      -t|--table|--music-table)
        ACTIONS+=(table)
        ;;
      -f|--files|--view-files)
        ACTIONS+=(files)
        ;;
      -p|--playlist|--view-playlist)
        ACTIONS+=(playlist)
        ;;
      -e|--edit-playlist|--edit)
        ACTIONS+=(edit-playlist)
        ;;
      -l|--lyrics|--fetch-lyrics)
        ACTIONS+=(lyrics)
        ;;
      -m|--menu)
        ACTIONS+=(menu)
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  (($# == 0)) || die "unknown argument: $1"
}

main_loop() {
  PAUSE_AFTER_ACTION=1
  LOOP_PLAYLISTS=1
  CLEAR_HEADER=1

  while true; do
    show_menu
    local choice
    read -r choice

    case "$choice" in
      1) change_scan_dir ;;
      2) view_songs ;;
      3) view_music_files ;;
      4) view_playlist ;;
      5) edit_playlist ;;
      6) fetch_lyrics ;;
      0) print_goodbye; exit 0 ;;
      *) printf '\nUnknown option: %s\n' "$choice"; pause ;;
    esac
  done
}

main() {
  parse_arguments "$@"

  if (( ${#ACTIONS[@]} == 0 )); then
    main_loop
    return
  fi

  PAUSE_AFTER_ACTION=0
  LOOP_PLAYLISTS=0
  CLEAR_HEADER=0

  local action
  for action in "${ACTIONS[@]}"; do
    run_action "$action"
  done
}

main "$@"

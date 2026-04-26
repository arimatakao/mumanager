#!/usr/bin/env bash

set -o pipefail

SCAN_DIR="$PWD"

AUDIO_EXTENSIONS=(
  mp3 flac wav ogg oga opus m4a aac alac wma aiff aif ape
)

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

pause() {
  printf '\nPress Enter to continue...'
  read -r _
}

check_metadata_dependencies() {
  command -v ffprobe >/dev/null 2>&1 || die 'ffprobe from the FFmpeg package is required.'
  command -v jq >/dev/null 2>&1 || die 'jq is required to read metadata.'
}

print_header() {
  clear
  printf 'MuManager - music and Extended M3U manager ( https://github.com/arimatakao/mumanager )\n'
  printf 'Scan directory: %s\n\n' "$(display_path "$SCAN_DIR")"
}

show_menu() {
  print_header
  printf 'Choose an action:\n'
  printf '  1) Change scan directory\n'
  printf '  2) View music table\n'
  printf '  3) View music files (fast scan)\n'
  printf '  4) View playlist\n'
  printf '  5) Edit playlist\n'
  printf '  0) Exit\n\n'
  printf 'Your choice: '
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

format_duration() {
  local raw="$1"
  if [[ -z "$raw" || "$raw" == "null" ]]; then
    printf '-'
    return
  fi

  local seconds
  seconds=$(printf '%.0f' "$raw" 2>/dev/null) || {
    printf '-'
    return
  }

  local hours=$(( seconds / 3600 ))
  local minutes=$(( (seconds % 3600) / 60 ))
  local secs=$(( seconds % 60 ))

  if (( hours > 0 )); then
    printf '%d:%02d:%02d' "$hours" "$minutes" "$secs"
  else
    printf '%d:%02d' "$minutes" "$secs"
  fi
}

format_bitrate() {
  local raw="$1"
  if [[ -z "$raw" || "$raw" == "null" || "$raw" == "0" ]]; then
    printf '-'
    return
  fi

  printf '%s kbps' "$(( (raw + 500) / 1000 ))"
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

metadata_field() {
  local json="$1"
  local field="$2"
  local fallback="$3"

  jq -r --arg field "$field" --arg fallback "$fallback" '
    def tag($names):
      (.format.tags // {}) as $tags
      | reduce $names[] as $name (null; . // $tags[$name]);

    if $field == "title" then
      tag(["title", "TITLE"]) // $fallback
    elif $field == "composer" then
      tag(["composer", "COMPOSER", "artist", "ARTIST", "album_artist", "ALBUMARTIST"]) // "-"
    elif $field == "album" then
      tag(["album", "ALBUM"]) // "-"
    elif $field == "duration" then
      .format.duration // ""
    elif $field == "bit_rate" then
      .format.bit_rate // ""
    elif $field == "size" then
      .format.size // ""
    elif $field == "lyrics" then
    if (
        tag([
          "lyrics", "LYRICS",
          "unsyncedlyrics", "UNSYNCEDLYRICS", "UNSYNCED LYRICS",
          "syncedlyrics", "SYNCEDLYRICS", "SYNCED LYRICS"
        ]) // ""
      ) | length > 0 then "yes" else "no" end
    else
      "-"
    end
  ' <<<"$json"
}

song_row() {
  local file="$1"
  local json title composer album bit_rate duration size has_lyrics

  json=$(ffprobe -v error \
    -show_entries format=duration,bit_rate,size:format_tags \
    -of json "$file" 2>/dev/null) || return 1

  title=$(metadata_field "$json" title "$(basename "$file")")
  composer=$(metadata_field "$json" composer "-")
  album=$(metadata_field "$json" album "-")
  bit_rate=$(format_bitrate "$(metadata_field "$json" bit_rate "")")
  has_lyrics=$(metadata_field "$json" lyrics "-")
  duration=$(format_duration "$(metadata_field "$json" duration "")")
  size=$(format_size "$(metadata_field "$json" size "")")

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$title" "$composer" "$album" "$bit_rate" "$has_lyrics" "$duration" "$size"
}

view_songs() {
  check_metadata_dependencies

  print_header
  printf 'Scanning audio metadata...\n\n'

  local tmp rows=0 skipped=0
  tmp=$(mktemp) || die 'failed to create a temporary file.'
  local -a FIND_ARGS
  build_find_args

  printf 'Track title\tComposer\tAlbum\tBitrate\tHas lyrics\tTrack length\tFile size\n' >"$tmp"

  while IFS= read -r -d '' file; do
    if song_row "$file" >>"$tmp"; then
      rows=$((rows + 1))
    else
      skipped=$((skipped + 1))
    fi
  done < <(find "$SCAN_DIR" -type f "${FIND_ARGS[@]}" -print0 2>/dev/null | sort -z)

  if (( rows == 0 )); then
    printf 'No music files found in directory: %s\n' "$(display_path "$SCAN_DIR")"
  else
    if command -v column >/dev/null 2>&1; then
      column -t -s $'\t' "$tmp"
    else
      cat "$tmp"
    fi
    printf '\nTotal files: %d\n' "$rows"
  fi

  if (( skipped > 0 )); then
    printf 'Files skipped because metadata could not be read: %d\n' "$skipped"
  fi

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
      column -t -s $'\t' "$tmp"
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
  done
}

view_playlist() {
  check_metadata_dependencies

  while true; do
    local playlist_path
    select_playlist playlist_path || return

    print_header
    printf 'Reading playlist: %s\n\n' "$(display_path "$playlist_path")"

    local tmp rows=0 skipped=0 missing=0 unsupported=0 total_files=0
    tmp=$(mktemp) || die 'failed to create a temporary file.'
    printf 'Track title\tComposer\tAlbum\tBitrate\tHas lyrics\tTrack length\tFile size\n' >"$tmp"

    local playlist_dir line track_path
    playlist_dir=$(cd "$(dirname "$playlist_path")" && pwd) || {
      printf 'Failed to enter playlist directory.\n'
      rm -f "$tmp"
      pause
      continue
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
      line=${line%$'\r'}
      [[ -z "$line" || "$line" == \#* ]] && continue

      track_path=$(resolve_playlist_track "$playlist_dir" "$line")
      if [[ -z "$track_path" ]]; then
        unsupported=$((unsupported + 1))
        continue
      fi

      total_files=$((total_files + 1))

      if [[ ! -f "$track_path" ]]; then
        missing=$((missing + 1))
        continue
      fi

      if song_row "$track_path" >>"$tmp"; then
        rows=$((rows + 1))
      else
        skipped=$((skipped + 1))
      fi
    done <"$playlist_path"

    if (( rows == 0 )); then
      printf 'No readable local music files found in playlist.\n'
    else
      if command -v column >/dev/null 2>&1; then
        column -t -s $'\t' "$tmp"
      else
        cat "$tmp"
      fi
    fi

    printf '\nMissing files: %d\n' "$missing"
    printf 'Total files: %d\n' "$total_files"

    if (( unsupported > 0 )); then
      printf 'Unsupported remote playlist entries skipped: %d\n' "$unsupported"
    fi
    if (( skipped > 0 )); then
      printf 'Files skipped because metadata could not be read: %d\n' "$skipped"
    fi

    rm -f "$tmp"
    pause
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

main() {
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
      0) printf 'Goodbye!\n'; exit 0 ;;
      *) printf '\nUnknown option: %s\n' "$choice"; pause ;;
    esac
  done
}

main "$@"

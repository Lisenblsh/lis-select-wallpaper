#!/usr/bin/env bash
set -euo pipefail

thumb_dir="${XDG_CACHE_HOME:-$HOME/.cache}/wallpapers/thumbs"
THUMBNAIL_WIDTH="250" # Size of thumbnails in pixels (16:9)
THUMBNAIL_HEIGHT="141"
mkdir -p "$thumb_dir"
menu_items=""
wallpaper="/tmp/wallpaper.png"

if [[ -f "$thumb_dir/current" ]]; then
  CURRENT_WALL=$(cat "$thumb_dir/current")
fi

create_thumbnails() {
  menu_items=""
  while read -r f; do
    base="$(basename "$f")"
    thumb="$thumb_dir/${base%.*}.png"

    [[ -f "$thumb" ]] || magick "$f" -thumbnail "${THUMBNAIL_WIDTH}x${THUMBNAIL_HEIGHT}^" \
      -gravity center -extent "${THUMBNAIL_WIDTH}x${THUMBNAIL_HEIGHT}" "$thumb"

    if [[ -z "$menu_items" ]]; then
      menu_items="img:$thumb"
    else
      menu_items+="\nimg:$thumb"
    fi
  done < <(
    find -L "$WALL_DIR" -maxdepth 3 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) |
      sort -V | awk '{
        name=$0
        if (name ~ /[0-9]/) { num[name]=$0 } else { text[name]=$0 }
    } END {
        for (f in text) print text[f]
        for (f in num) print num[f]
    }'
  )

  total=$(echo -e $menu_items | wc -l)
}

select_wallpaper() {
  create_thumbnails

  columns=3
  lines=$(((total + columns - 1) / columns))
  [[ $lines -gt 4 ]] && lines=4
  [[ $lines -lt 1 ]] && lines=1

  choice="$(
    echo -e "$menu_items" | wofi --show dmenu \
      --hide-search \
      --cache-file /dev/null \
      --define "image-size=${THUMBNAIL_WIDTH}x${THUMBNAIL_HEIGHT}" \
      --lines $lines \
      --columns $columns \
      --allow-images \
      --hide-scroll \
      --conf ~/.config/wofi/wallpaper.conf
  )"
  [[ -n "$choice" ]] || exit 1
  if [[ "$choice" == "" ]]; then
    get_random_wallpaper
  else
    thumb_file="${choice#img:}"
    base="$(basename "$thumb_file" .png)"

    wall="$(find -L "$WALL_DIR" -maxdepth 3 -type f -iname "$base.*" | head -n1)"

    [[ -f "$wall" ]] || {
      notify-send "wallpaper-picker" "Оригинал не найден"
      exit 1
    }

    echo $wall
  fi

}

start_daemon() {
  if ! swww query >/dev/null 2>&1; then
    swww-daemon --format xrgb >/dev/null 2>&1 &
    for _ in {1..20}; do
      swww query >/dev/null 2>&1 && break
      sleep 0.05
    done
  fi
}

get_aspect_ratio() {
  local gcd=$(printf "%d\n" "$(echo "$1" | awk '{ a=$1; b=$2; while (b != 0) { t=b; b=a%b; a=t } print a }')")
  local w=$(($(echo "$1" | awk '{print $1}') / $gcd))
  local h=$(($(echo "$1" | awk '{print $2}') / $gcd))

  echo "$w $h"
}

get_wallpaper() {
  echo "$wall" >"$thumb_dir/current"
  size=$(identify -ping -format '%w %h' "$1")
  image_aspect_ratio=$(get_aspect_ratio "$size")
  aspect_w=$(echo "$image_aspect_ratio" | awk '{print $1}')
  aspect_h=$(echo "$image_aspect_ratio" | awk '{print $2}')
  display_aspect_ratio=$(get_aspect_ratio "$width $height")
  display_aspect_w=$(echo "$display_aspect_ratio" | awk '{print $1}')
  display_aspect_h=$(echo "$display_aspect_ratio" | awk '{print $2}')

  a=$(calc "$aspect_w"*"$display_aspect_h")
  b=$(calc "$display_aspect_w"*"$aspect_h")

  if [[ "$aspect_w:$aspect_h" = "$display_aspect_ratio" || $a -ge $b ]]; then
    echo "$1"
  else
    magick \
      \( "$1" -scale 5% -scale 100% -blur 20 -resize '1920' \) \
      \( "$1" -resize '1920x1080' -background none -gravity center -extent '1920x1080' +gravity \) \
      -gravity Center -composite -crop '1920x1080+0+0' "$wallpaper"
    echo "$wallpaper"
  fi
}

get_random_wallpaper() {
  wall="$(find -L "$WALL_DIR" -maxdepth 3 -type f -iname "*.*" ! -name "$(basename "$CURRENT_WALL")" | shuf -n 1)"
  echo "$wall"
}

set_wallpaper() {
  swww img "$1" \
    --transition-type wipe \
    --transition-fps 60 \
    --transition-angle 30 \
    --transition-pos 0.5,0.5 \
    --transition-duration 0.70 \
    --resize crop \
    --fill-color 000000
}

print_help() {
  cat <<EOF
Usage: $0 [options]

Options:
-h             height
-w             width
-d             path to images
-r             set random image as wallpaper
--help         show this message
EOF
}

for arg in "$@"; do
  case "$arg" in
  --help)
    print_help
    exit 0
    ;;
  esac
done

height="1080"
width="1920"
WALL_DIR="$HOME/Pictures/Wallpapers"
random=false

# теперь обычные short options
while getopts "h:w:d:r" opt; do
  case "$opt" in
  h) height="$OPTARG" ;;
  w) width="$OPTARG" ;;
  d) WALL_DIR="$OPTARG" ;;
  r) random=true ;;
  *)
    print_help
    exit 1
    ;;
  esac
done

if $random; then
  start_daemon
  wall=$(get_random_wallpaper)
  wallpaper=$(get_wallpaper "$wall")
  set_wallpaper "$wallpaper"
else
  start_daemon
  wall=$(select_wallpaper)
  wallpaper=$(get_wallpaper "$wall")
  set_wallpaper "$wallpaper"
fi

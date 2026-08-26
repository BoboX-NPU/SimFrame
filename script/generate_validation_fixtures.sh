#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/LocalFixtures"
mkdir -p "$OUTPUT_DIR"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1206x2622:rate=30:duration=2" \
  -frames:v 1 "$OUTPUT_DIR/iphone-17-pro-grid.png"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1206x2622:rate=30:duration=2" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=2" \
  -c:v libx264 -preset ultrafast -crf 18 -pix_fmt yuv420p -c:a aac -shortest \
  "$OUTPUT_DIR/iphone-17-pro-grid-with-audio.mov"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1206x2622:rate=30:duration=0.2" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=0.2" \
  -c:v libx264 -preset ultrafast -crf 18 -pix_fmt yuv420p -c:a aac -shortest \
  "$OUTPUT_DIR/iphone-17-pro-grid-short-with-audio.mov"

echo "$OUTPUT_DIR"

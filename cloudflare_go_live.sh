#!/usr/bin/env bash
set -euo pipefail

RTMPS_BASE_URL="${CF_RTMPS_BASE_URL:-rtmps://live.cloudflare.com:443/live}"
MAX_RETRIES="${MAX_RETRIES:-10}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-3}"
STARTUP_CHECK_SECONDS="${STARTUP_CHECK_SECONDS:-5}"
VIDEO_SIZE="${VIDEO_SIZE:-426x240}"
FPS="${FPS:-5}"
MAC_INPUT_FPS="${MAC_INPUT_FPS:-30}"
MAC_PIXEL_FORMAT="${MAC_PIXEL_FORMAT:-}"
MAC_CAPTURE_SIZE="${MAC_CAPTURE_SIZE:-}"
LINUX_CAPTURE_SIZE="${LINUX_CAPTURE_SIZE:-$VIDEO_SIZE}"
VIDEO_BITRATE="${VIDEO_BITRATE:-180k}"
GOP_SIZE="${GOP_SIZE:-5}"
BUF_SIZE="${BUF_SIZE:-90k}"

usage() {
  cat <<'EOF'
Usage:
  ./cloudflare_go_live.sh STREAM_KEY [DEVICE_NUMBER]

Required:
  STREAM_KEY    Cloudflare Stream RTMPS stream key.

Need a stream key or HLS URL?
  Contact the Nomadic team at nomadicml.com

Optional positional arguments:
  DEVICE_NUMBER Camera index. On macOS this maps to DEVICE_NUMBER:none.
                On Linux this maps to /dev/videoDEVICE_NUMBER.

Optional environment variables:
  CF_RTMPS_BASE_URL        Defaults to rtmps://live.cloudflare.com:443/live
  MAX_RETRIES              Defaults to 10
  RETRY_DELAY_SECONDS      Defaults to 3
  STARTUP_CHECK_SECONDS    Seconds ffmpeg must stay alive before we log success
  VIDEO_SIZE               Output size, defaults to 426x240
  FPS                      Output FPS, defaults to 5
  MAC_INPUT_FPS            macOS capture FPS, defaults to 30
  MAC_PIXEL_FORMAT         macOS avfoundation pixel format, optional
  MAC_CAPTURE_SIZE         macOS capture size, defaults to 1280x720 for the
                           built-in camera and 640x480 for an explicitly
                           selected external camera
  LINUX_CAPTURE_SIZE       Linux capture size, defaults to VIDEO_SIZE
  VIDEO_BITRATE            Defaults to 180k
  GOP_SIZE                 Defaults to 5
  BUF_SIZE                 Defaults to 90k
  MAC_CAMERA_DEVICE        avfoundation device, defaults to 0:none
  LINUX_CAMERA_DEVICE      v4l2 device, auto-detected from /dev/video0-2 if unset
  CF_HLS_URL               Optional full HLS URL to print after startup

Examples:
  ./cloudflare_go_live.sh YOUR_STREAM_KEY
  ./cloudflare_go_live.sh YOUR_STREAM_KEY 1
  CF_HLS_URL="https://customer-.../manifest/video.m3u8" \
    ./cloudflare_go_live.sh YOUR_STREAM_KEY
  MAC_CAMERA_DEVICE="1:none" ./cloudflare_go_live.sh YOUR_STREAM_KEY
EOF
}

need_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    return 1
  fi
}

print_ffmpeg_install_help() {
  cat <<'EOF'
ffmpeg is required but was not found.

Install instructions:
  macOS:  brew install ffmpeg
  Ubuntu: sudo apt-get update && sudo apt-get install -y ffmpeg

Then run this script again.
EOF
}

find_linux_camera() {
  local candidate
  for candidate in /dev/video0 /dev/video1 /dev/video2; do
    if [[ -c "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

build_video_filter() {
  local width="${VIDEO_SIZE%x*}"
  local height="${VIDEO_SIZE#*x}"

  if [[ -z "$width" || -z "$height" || "$width" == "$VIDEO_SIZE" || "$height" == "$VIDEO_SIZE" ]]; then
    echo "VIDEO_SIZE must use WIDTHxHEIGHT format, got: ${VIDEO_SIZE}" >&2
    exit 1
  fi

  VIDEO_FILTER="fps=${FPS},scale=${width}:${height}:flags=fast_bilinear"
}

resolve_device_override() {
  local device_number="$1"

  if [[ -z "$device_number" ]]; then
    DEVICE_OVERRIDE=""
    return 0
  fi

  if ! [[ "$device_number" =~ ^[0-9]+$ ]]; then
    echo "DEVICE_NUMBER must be a non-negative integer, got: ${device_number}" >&2
    exit 1
  fi

  case "$(uname -s)" in
    Darwin)
      DEVICE_OVERRIDE="${device_number}:none"
      ;;
    Linux)
      DEVICE_OVERRIDE="/dev/video${device_number}"
      ;;
    *)
      DEVICE_OVERRIDE=""
      ;;
  esac
}

build_input_args() {
  local platform
  platform="$(uname -s)"

  case "$platform" in
    Darwin)
      local device="${MAC_CAMERA_DEVICE:-${DEVICE_OVERRIDE:-0:none}}"
      local capture_size="${MAC_CAPTURE_SIZE:-}"
      if [[ -z "$capture_size" ]]; then
        if [[ "$device" == "0:none" ]]; then
          capture_size="1280x720"
        else
          capture_size="640x480"
        fi
      fi
      INPUT_ARGS=(
        -f avfoundation
        -framerate "$MAC_INPUT_FPS"
        -video_size "$capture_size"
      )
      if [[ -n "$MAC_PIXEL_FORMAT" ]]; then
        INPUT_ARGS+=(
          -pixel_format "$MAC_PIXEL_FORMAT"
        )
      fi
      INPUT_ARGS+=(
        -i "$device"
      )
      CAMERA_HINT="Using macOS camera ${device} at ${capture_size} @ ${MAC_INPUT_FPS}fps. If this camera index is wrong, run: ffmpeg -f avfoundation -list_devices true -i \"\""
      ;;
    Linux)
      local device="${LINUX_CAMERA_DEVICE:-${DEVICE_OVERRIDE:-}}"
      if [[ -z "$device" ]]; then
        if ! device="$(find_linux_camera)"; then
          echo "No Linux camera device found in /dev/video0 through /dev/video2." >&2
          echo "Set LINUX_CAMERA_DEVICE=/dev/videoX and try again." >&2
          exit 1
        fi
      fi
      INPUT_ARGS=(
        -f v4l2
        -framerate "$FPS"
        -video_size "$LINUX_CAPTURE_SIZE"
        -i "$device"
      )
      CAMERA_HINT="Using Linux camera device ${device} at ${LINUX_CAPTURE_SIZE} @ ${FPS}fps"
      ;;
    *)
      cat <<'EOF'
This script currently supports macOS and Linux only.

For Windows, use OBS or ffmpeg manually with:
  rtmps://live.cloudflare.com:443/live/YOUR_STREAM_KEY
EOF
      exit 1
      ;;
  esac
}

get_hls_url() {
  if [[ -n "${CF_HLS_URL:-}" ]]; then
    local url="${CF_HLS_URL}"
    if [[ "$url" != *"?"* ]]; then
      url="${url}?protocol=llhls"
    elif [[ "$url" != *"protocol="* ]]; then
      url="${url}&protocol=llhls"
    fi
    printf '%s\n' "${url}"
    return 0
  fi

  return 1
}

print_session_summary() {
  local stream_key="$1"
  local destination="${RTMPS_BASE_URL%/}/$stream_key"

  cat <<EOF
Starting webcam stream to Cloudflare Stream.

Ingest:
  $destination

Profile:
  output ${VIDEO_SIZE} @ ${FPS}fps, bitrate ${VIDEO_BITRATE}

$CAMERA_HINT
EOF

  if hls_url="$(get_hls_url)"; then
    echo
    echo "Cloudflare HLS playback URL:"
    echo "  ${hls_url}"
  fi

  echo
  echo "Press Ctrl+C to stop streaming."
}

print_stream_started() {
  echo
  echo "[SUCCESS] Webcam stream is running."

  if hls_url="$(get_hls_url)"; then
    echo
    echo "Paste this URL into nomadic-ml-ui or nomadic-ml-stk to attach and analyze your live stream."
    echo "  ${hls_url}"
  else
    echo
    echo "Set CF_HLS_URL to display your playback URL here."
  fi
}

STREAM_KEY="${1:-}"
if [[ -z "$STREAM_KEY" ]]; then
  usage
  exit 1
fi
DEVICE_NUMBER="${2:-}"

resolve_device_override "$DEVICE_NUMBER"

if ! need_cmd ffmpeg; then
  print_ffmpeg_install_help
  exit 1
fi

build_video_filter
build_input_args
print_session_summary "$STREAM_KEY"

FFMPEG_ARGS=(
  -hide_banner
  -loglevel warning
  -fflags nobuffer
  -thread_queue_size 512
  "${INPUT_ARGS[@]}"
  -vf "$VIDEO_FILTER"
  -c:v libx264
  -preset ultrafast
  -tune zerolatency
  -flags low_delay
  -pix_fmt yuv420p
  -b:v "$VIDEO_BITRATE"
  -maxrate "$VIDEO_BITRATE"
  -bufsize "$BUF_SIZE"
  -g "$GOP_SIZE"
  -keyint_min "$GOP_SIZE"
  -an
  -flush_packets 1
  -muxdelay 0
  -muxpreload 0
  -f flv
  "${RTMPS_BASE_URL%/}/${STREAM_KEY}"
)

shutdown_requested=0
ffmpeg_pid=""

handle_shutdown() {
  shutdown_requested=1
  if [[ -n "$ffmpeg_pid" ]] && kill -0 "$ffmpeg_pid" 2>/dev/null; then
    kill -TERM "$ffmpeg_pid" 2>/dev/null || true
  fi
}

trap handle_shutdown INT TERM

attempt=1
while (( attempt <= MAX_RETRIES )); do
  echo
  echo "Attempt ${attempt}/${MAX_RETRIES}"

  set +e
  ffmpeg "${FFMPEG_ARGS[@]}" &
  ffmpeg_pid=$!

  startup_elapsed=0
  startup_announced=0
  while (( startup_elapsed < STARTUP_CHECK_SECONDS )); do
    if (( shutdown_requested )); then
      break
    fi
    if ! kill -0 "$ffmpeg_pid" 2>/dev/null; then
      break
    fi
    sleep 1
    startup_elapsed=$((startup_elapsed + 1))
  done

  if [[ "$startup_elapsed" -ge "$STARTUP_CHECK_SECONDS" ]] && kill -0 "$ffmpeg_pid" 2>/dev/null; then
    print_stream_started "$STREAM_KEY"
    startup_announced=1
  fi

  wait "$ffmpeg_pid"
  exit_code=$?
  set -e
  ffmpeg_pid=""

  if (( shutdown_requested )); then
    echo
    echo "Streaming stopped by user."
    exit 0
  fi

  if [[ "$exit_code" -eq 0 ]]; then
    echo
    if (( ! startup_announced )); then
      print_stream_started "$STREAM_KEY"
    fi
    echo "FFmpeg exited cleanly."
    exit 0
  fi

  if (( attempt == MAX_RETRIES )); then
    echo
    echo "FFmpeg exited with status ${exit_code}. Reached retry limit." >&2
    exit "$exit_code"
  fi

  echo "FFmpeg exited with status ${exit_code}. Retrying in ${RETRY_DELAY_SECONDS}s..." >&2
  sleep "$RETRY_DELAY_SECONDS"
  attempt=$((attempt + 1))
done

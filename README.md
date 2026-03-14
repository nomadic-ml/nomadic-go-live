# Cloudflare Go Live

This repo is for hackathon participants who need to stream a laptop webcam to Cloudflare Stream.

It includes one script:

- `cloudflare_go_live.sh`

## What You Need

- A macOS or Linux laptop
- `ffmpeg`
- A Cloudflare `STREAM_KEY`
- Optionally, your Cloudflare `HLS Manifest URL`

Need a stream key or HLS URL? Contact the Nomadic team at `nomadicml.com`.

## Quick Start

Install `ffmpeg`:

```bash
# macOS
brew install ffmpeg

# Ubuntu / Debian
sudo apt-get update
sudo apt-get install -y ffmpeg
```

Start streaming with your stream key:

```bash
./cloudflare_go_live.sh YOUR_STREAM_KEY
```

If you already have your Cloudflare HLS URL, pass it in so the script prints it back clearly:

```bash
CF_HLS_URL="https://customer-<CODE>.cloudflarestream.com/<UID>/manifest/video.m3u8" \
./cloudflare_go_live.sh YOUR_STREAM_KEY
```

The script sends video to Cloudflare over RTMPS. Cloudflare then provides the HLS playback URL.

## How To Get The HLS Link

Use one of these:

1. Ask the Nomadic team to send it to you directly.
2. In Cloudflare, open your live input and copy `Connection Info -> HLS Manifest URL`.

The HLS URL looks like this:

```text
https://customer-<CODE>.cloudflarestream.com/<UID>/manifest/video.m3u8
```

## Choosing A Camera

### macOS

List available cameras:

```bash
ffmpeg -f avfoundation -list_devices true -i ""
```

Common pattern:

- `0:none` is often the built-in camera
- `1:none` or higher is often a USB camera

Use a specific camera by number:

```bash
./cloudflare_go_live.sh YOUR_STREAM_KEY 1
```

Or set the full device string:

```bash
MAC_CAMERA_DEVICE="1:none" ./cloudflare_go_live.sh YOUR_STREAM_KEY
```

### Linux

List camera devices:

```bash
ls /dev/video*
```

If `v4l-utils` is installed, this is more descriptive:

```bash
v4l2-ctl --list-devices
```

Use a specific camera by number:

```bash
./cloudflare_go_live.sh YOUR_STREAM_KEY 1
```

Or set the full device path:

```bash
LINUX_CAMERA_DEVICE=/dev/video2 ./cloudflare_go_live.sh YOUR_STREAM_KEY
```

If you do not specify a Linux camera, the script will try `/dev/video0`, `/dev/video1`, and `/dev/video2`.

## USB Camera Tips

- Plug the USB camera in before starting the script.
- On macOS, run the `avfoundation` device list command again after plugging it in.
- On Linux, check whether a new `/dev/videoX` device appeared.
- If the wrong camera opens, pass a different device number.

## Useful Options

Default profile:

- `VIDEO_SIZE=426x240`
- `FPS=5`
- `VIDEO_BITRATE=180k`

If you want slightly better quality:

```bash
VIDEO_SIZE=480x270 FPS=6 VIDEO_BITRATE=250k GOP_SIZE=6 BUF_SIZE=125k \
./cloudflare_go_live.sh YOUR_STREAM_KEY
```

If you need a different macOS capture size:

```bash
MAC_INPUT_FPS=30 MAC_CAPTURE_SIZE=640x480 \
./cloudflare_go_live.sh YOUR_STREAM_KEY
```

## Windows

This script supports macOS and Linux only.

If you are on Windows, use OBS or `ffmpeg` manually with:

- RTMPS server: `rtmps://live.cloudflare.com:443/live/`
- Stream key: your `STREAM_KEY`

## Stopping The Stream

Press `Ctrl+C`.

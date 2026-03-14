# Nomadic Go Live

Welcome to the hackathon! This script streams your laptop webcam to Cloudflare Stream so your team can broadcast live.

## Setup

Install `ffmpeg` if you don't have it:

```bash
# macOS
brew install ffmpeg

# Ubuntu / Debian
sudo apt-get update && sudo apt-get install -y ffmpeg
```

## Go Live

You'll receive a **Stream Key** and an **HLS URL** from the Nomadic team. Run:

```bash
CF_HLS_URL="https://customer-XXXX.cloudflarestream.com/STREAM_ID/manifest/video.m3u8" \
./cloudflare_go_live.sh "YOUR_STREAM_KEY"
```

That's it — your webcam is now streaming. The script will print your HLS playback URL so viewers can tune in.

Press `Ctrl+C` to stop.

## Choosing a Camera

By default the script uses your built-in webcam. If you have a USB camera plugged in, pass its index as the second argument:

```bash
CF_HLS_URL="https://customer-XXXX.cloudflarestream.com/STREAM_ID/manifest/video.m3u8" \
./cloudflare_go_live.sh "YOUR_STREAM_KEY" 1
```

To see which cameras are available:

```bash
# macOS
ffmpeg -f avfoundation -list_devices true -i ""

# Linux
ls /dev/video*
```

## Windows

This script supports macOS and Linux. On Windows, use OBS with:

- Server: `rtmps://live.cloudflare.com:443/live/`
- Stream key: your `STREAM_KEY`

## Need Help?

For your Stream Key and HLS URL, or any questions, email yunus@nomadicml.com.

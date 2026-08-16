#!/bin/bash

# 1. Clean up existing virtual sinks and loopbacks
pkill -f "Headphones_Cap" 2>/dev/null
pkill -f "MusicStream_Cap" 2>/dev/null
pkill -f "VoiceStream_Cap" 2>/dev/null
pkill -f pw-loopback 2>/dev/null

pactl list short modules | grep "module-null-sink" | awk '{print $1}' | while read -r id; do
    pactl unload-module "$id" 2>/dev/null || true
done

# 2. Detect USB Headphones (Sink 79) and Microphone
HEADPHONE_HW=$(pactl list sinks short | grep -E "usb|headphone|analog-stereo" | grep -v -E "GeneralSound|VirtMic|easyeffects" | awk '{print $2}' | head -n 1)
[ -z "$HEADPHONE_HW" ] && HEADPHONE_HW=$(pactl list sinks short | grep -v -E "GeneralSound|VirtMic|easyeffects" | awk '{print $2}' | head -n 1)

RAW_MIC=$(pactl list sources short | grep -v "\.monitor" | grep -E "usb|input" | grep -v -E "VirtMic|easyeffects|GeneralSound" | awk '{print $2}' | head -n 1)
[ -z "$RAW_MIC" ] && RAW_MIC=$(pactl list sources short | grep -v "\.monitor" | grep -v -E "VirtMic|easyeffects|GeneralSound" | awk '{print $2}' | head -n 1)

# 3. Detect EasyEffects targets
if pactl list sinks short | grep -q "easyeffects_sink"; then
    echo "EasyEffects Output detected -> using easyeffects_sink"
    HEADPHONE_TARGET="easyeffects_sink"
else
    echo "EasyEffects Output not running -> using $HEADPHONE_HW"
    HEADPHONE_TARGET="$HEADPHONE_HW"
fi

if pactl list sources short | grep -q "easyeffects_source"; then
    echo "EasyEffects Input detected -> using easyeffects_source"
    MIC_SOURCE="easyeffects_source"
else
    echo "EasyEffects Input not running -> using $RAW_MIC"
    MIC_SOURCE="$RAW_MIC"
fi

# 4. Create Virtual Sinks
pactl load-module module-null-sink \
    sink_name=GeneralSound \
    sink_properties="device.description='Общий-Звук' session.suspend-timeout-seconds=0"

pactl load-module module-null-sink \
    sink_name=VirtMic \
    sink_properties="device.description='Вирт-Микро' session.suspend-timeout-seconds=0"

# Ensure sinks are unmuted and at 100%
pactl set-sink-mute GeneralSound false
pactl set-sink-volume GeneralSound 100%
pactl set-sink-mute VirtMic false
pactl set-sink-volume VirtMic 100%

# CRITICAL FIX: Unmute and set volume for the monitor of VirtMic (what Discord records)
pactl set-source-mute VirtMic.monitor false
pactl set-source-volume VirtMic.monitor 100%
pactl set-source-mute GeneralSound.monitor false
pactl set-source-volume GeneralSound.monitor 100%

# 5. Set defaults
pactl set-default-sink "$HEADPHONE_TARGET"
# Do NOT set VirtMic.monitor as default source to avoid conflicts
pactl set-default-source "$MIC_SOURCE"

# 6. Move Discord (and other recording apps) to VirtMic.monitor
pactl list short source-outputs | awk '{print $1}' | while read -r STREAM_ID; do
    pactl move-source-output "$STREAM_ID" VirtMic.monitor 2>/dev/null || true
done

sleep 0.5

# 7. Start Loopbacks
echo "Starting Native PipeWire Loopbacks..."

# Loopback A: Общий-Звук -> Headphones (so you can hear the music you send to stream)
nohup pw-loopback \
    --capture-props='{ target.object = "GeneralSound" stream.capture.sink = true node.name = "Headphones_Cap" node.description = "Мой Звук (Наушники)" }' \
    --playback-props='{ target.object = "'"$HEADPHONE_TARGET"'" node.name = "Headphones_Play" node.description = "Мой Звук (Наушники)" }' >/dev/null 2>&1 &

# Loopback B: Общий-Звук -> VirtMic (sends the music to your virtual mic)
nohup pw-loopback \
    --capture-props='{ target.object = "GeneralSound" stream.capture.sink = true node.name = "MusicStream_Cap" node.description = "Звук Музыки на Стрим" }' \
    --playback-props='{ target.object = "VirtMic" node.name = "MusicStream_Play" node.description = "Звук Музыки на Стрим" }' >/dev/null 2>&1 &

# Loopback C: Your Voice -> VirtMic (sends your microphone voice to your virtual mic)
nohup pw-loopback \
    --capture-props='{ target.object = "'"$MIC_SOURCE"'" node.name = "VoiceStream_Cap" node.description = "Мой Голос на Стрим" }' \
    --playback-props='{ target.object = "VirtMic" node.name = "VoiceStream_Play" node.description = "Мой Голос на Стрим" }' >/dev/null 2>&1 &

echo "Setup complete!"
echo "IMPORTANT: Open Discord Settings -> Voice & Video -> and manually set Input Device to 'Вирт-Микро'"

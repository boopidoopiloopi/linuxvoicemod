#!/bin/bash

# 1. Clean up existing virtual sinks and loopbacks
pkill -f pw-loopback 2>/dev/null
pactl unload-module module-loopback 2>/dev/null
pactl unload-module module-null-sink 2>/dev/null

# 2. Detect physical hardware output & microphone (excluding virtual sinks)
REAL_OUTPUT=$(pactl list sinks short | grep -v "GeneralSound" | grep -v "VirtMic" | grep -v "easyeffects" | awk '{print $2}' | head -n 1)
RAW_MIC=$(pactl list sources short | grep -v "VirtMic" | grep -v "easyeffects" | grep -v "GeneralSound" | awk '{print $2}' | head -n 1)

# 3. Detect EasyEffects status for both mic and headphone output
if pactl list sources short | grep -q "easyeffects_source"; then
    echo "Easy Effects input detected! Using noise-suppressed mic audio."
    MIC_SOURCE="easyeffects_source"
else
    echo "Easy Effects input not running. Using raw physical mic."
    MIC_SOURCE="$RAW_MIC"
fi

if pactl list sinks short | grep -q "easyeffects_sink"; then
    echo "Easy Effects output detected! Routing personal headphones through Easy Effects."
    HEADPHONE_TARGET="easyeffects_sink"
else
    HEADPHONE_TARGET="$REAL_OUTPUT"
fi

echo "Physical Output: $REAL_OUTPUT"
echo "Headphones Target: $HEADPHONE_TARGET"
echo "Microphone Target: $MIC_SOURCE"

# 4. Create Virtual Sinks
pactl load-module module-null-sink \
    sink_name=GeneralSound \
    media.class=Audio/Sink \
    sink_properties="device.description='Общий-Звук' session.suspend-timeout-seconds=0"

pactl load-module module-null-sink \
    sink_name=VirtMic \
    media.class=Audio/Sink \
    sink_properties="device.description='Вирт-Микро' session.suspend-timeout-seconds=0"

# Small delay to allow PipeWire node registration
sleep 0.5

# 5. Set GeneralSound as Default Sink & Move Active Playing Apps into it
pactl set-default-sink GeneralSound

pactl list short sink-inputs | awk '{print $1}' | while read -r STREAM_ID; do
    pactl move-sink-input "$STREAM_ID" GeneralSound 2>/dev/null || true
done

# 6. Create Native PipeWire Loopbacks using clean SPA Dict formatting!
echo "Creating Loopback A (Headphones)..."
pw-loopback \
    --capture-props='target.object="GeneralSound" stream.capture.sink=true node.name="Headphones_Cap" node.description="Мой Звук (Наушники)" media.name="Мой Звук (Наушники)" application.name="Мой Звук (Наушники)"' \
    --playback-props='target.object="'"$HEADPHONE_TARGET"'" node.name="Headphones_Play" node.description="Мой Звук (Наушники)" media.name="Мой Звук (Наушники)" application.name="Мой Звук (Наушники)"' &

echo "Creating Loopback B (Music to Stream)..."
pw-loopback \
    --capture-props='target.object="GeneralSound" stream.capture.sink=true node.name="MusicStream_Cap" node.description="Звук Музыки на Стрим" media.name="Звук Музыки на Стрим" application.name="Звук Музыки на Стрим"' \
    --playback-props='target.object="VirtMic" node.name="MusicStream_Play" node.description="Звук Музыки на Стрим" media.name="Звук Музыки на Стрим" application.name="Звук Музыки на Стрим"' &

echo "Creating Loopback C (Voice to Stream)..."
pw-loopback \
    --capture-props='target.object="'"$MIC_SOURCE"'" node.name="VoiceStream_Cap" node.description="Мой Голос на Стрим" media.name="Мой Голос на Стрим" application.name="Мой Голос на Стрим"' \
    --playback-props='target.object="VirtMic" node.name="VoiceStream_Play" node.description="Мой Голос на Стрим" media.name="Мой Голос на Стрим" application.name="Мой Голос на Стрим"' &

# Small delay to allow loopback registration
sleep 0.5

# 7. Set VirtMic.monitor as default recording input
pactl set-default-source VirtMic.monitor

# Move active recording apps to Virtual Mic
pactl list short source-outputs | awk '{print $1}' | while read -r STREAM_ID; do
    pactl move-source-output "$STREAM_ID" VirtMic.monitor 2>/dev/null || true
done

echo "Setup complete!"

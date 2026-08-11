
> [!WARNING]
> **Prerequisite Warning:**
> **EasyEffects must be installed and running** before executing this script if you want your microphone voice to pass through noise suppression (RNNoise / DeepFilterNet) and your headphones to use your custom EQ. If EasyEffects is not running, the script will fall back to using your raw hardware mic and direct speaker output.
### How it works
To create this, we will be making 2 virtual audio nodes and 3 native PipeWire loopbacks:
1. **Общий-Звук** (Virtual Sink) - the sink into which all playback audio streams (e.g. music apps, browser) will be routed by default.
2. **Вирт-Микро** (Virtual Source) - a virtual microphone sink whose monitor (`VirtMic.monitor`) will be routed into your voice apps/OBS/Discord as the default input.

After creating the nodes, connect them using background `pw-loopback` instances:
* **Stream** $\rightarrow$ `GeneralSound` $\rightarrow$ `[pw-loopback: Мой Звук]` $\rightarrow$ `easyeffects_sink` (or Headphones Output)
* **Stream** $\rightarrow$ `GeneralSound` $\rightarrow$ `[pw-loopback: Звук Музыки]` $\rightarrow$ `VirtMic`
* `easyeffects_source` (or Physical Mic) $\rightarrow$ `[pw-loopback: Мой Голос]` $\rightarrow$ `VirtMic` $\rightarrow$ Default Mic Input (`VirtMic.monitor`)

Set `GeneralSound` as the default output sink and `VirtMic.monitor` as the default input source, then automatically migrate any currently active playback and recording streams.

Individual stream volumes can be adjusted in **pwvucontrol** (or **pavucontrol**) under the **Playback** tab:
* **"Мой Звук (Наушники)"** – controls music/browser volume in your headphones.
* **"Звук Музыки на Стрим"** – controls music volume sent to the virtual microphone.
* **"Мой Голос на Стрим"** – controls microphone volume sent to the virtual microphone.

---

### Easy Effects Setup (Required)

Before running the script for the first time, perform this one-time configuration in Easy Effects to prevent audio feedback loops:

1. Launch **Easy Effects**. 
```
sudo pacman -S easyeffects --needed
easyeffects
```
1. Open **Preferences** (the gear icon or menu in the top bar) $\rightarrow$ **PipeWire Settings**.
2. Under **Input Device**, change the selection from *"Default Input Device"* to your **actual hardware microphone** (e.g. `USB PnP Audio Device`).
3. Keep Easy Effects running in the background (or enabled as a startup service).

*(This ensures Easy Effects processes your real microphone and doesn't accidentally try to capture `VirtMic.monitor` when it becomes default).*

### Script installation
#### Automated
```bash
bash -c "$(curl -sSL https://raw.githubusercontent.com/boopidoopiloopi/linuxvoicemod/main/installer.sh)"
```

#### Manual

1. Create a `.desktop` file in `~/.local/share/applications/GabuMusic/GabuMusic.desktop`

```ini
[Desktop Entry]
Version=1.0
Type=Application
Name=GabuMusic
GenericName=VoiceGab
Comment=Слава богу что ВойсМода нету на Линукс
Exec=$HOME/.local/share/applications/GabuMusic/Daddy.sh
Icon=steam_icon_413150
Terminal=false
Categories=Audio;Music;Gabu;
```

2. Create `VoiceModLOL.sh` in `~/.local/share/applications/GabuMusic/VoiceModLOL.sh`
This script executes the routing logic using native `pw-loopback` streams.
```bash
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
```
3. Create `Daddy.sh` in `~/.local/share/applications/GabuMusic/Daddy.sh`
This launcher script invokes `VoiceModLOL.sh` and opens your target applications.
```bash
#!/bin/bash
"$HOME/.local/share/applications/GabuMusic/VoiceModLOL.sh"

# Subshells used to launch applications independently without hogging the console
("/opt/yandex-music/yandexmusic" --gtk-version=3 > /dev/null 2>&1 &)
(pwvucontrol -t 4 > /dev/null 2>&1 &)

notify-send "MMpgghhh~" "I did it Minor... are you proud of me?"
```
4. Make scripts executable
Run this command in terminal to set execution permissions:
```bash
chmod +x ~/.local/share/applications/GabuMusic/Daddy.sh
chmod +x ~/.local/share/applications/GabuMusic/VoiceModLOL.sh
```

5. Reset Command
To manually kill and unload the audio routing configuration without restarting PipeWire, run:

```bash
pkill -f pw-loopback; pactl unload-module module-null-sink; pactl unload-module module-loopback
```

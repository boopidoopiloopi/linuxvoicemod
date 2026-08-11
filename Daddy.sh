#!/bin/bash
"$HOME/.local/share/applications/GabuMusic/VoiceModLOL.sh"

# Subshells used to launch applications independently without hogging the console
("/opt/yandex-music/yandexmusic" --gtk-version=3 > /dev/null 2>&1 &)
(pwvucontrol -t 4 > /dev/null 2>&1 &)

notify-send "MMpgghhh~" "I did it Minor... are you proud of me?"

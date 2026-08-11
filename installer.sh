#!/bin/bash
set -e

echo "=== GabuMusic Installer ==="

# 1. Define required dependencies (Excluding yandex-music)
# - git: to clone the repo
# - easyeffects: core requirement for EQ/Noise suppression
# - pipewire & pipewire-pulse: core audio components (pactl)
# - pipewire-audio: provides pw-loopback
# - pwvucontrol: needed for Daddy.sh
# - libnotify: provides notify-send for Daddy.sh
# - glow: provides markdown terminal rendering for the README
DEPS=(git easyeffects pipewire pipewire-pulse pipewire-audio pwvucontrol libnotify glow)

echo "Checking dependencies..."
# pacman -T returns only the packages that are NOT installed
MISSING=$(pacman -T "${DEPS[@]}" || true)

if [ -n "$MISSING" ]; then
    echo "Missing dependencies found. Requesting sudo permissions to install:"
    echo "$MISSING"
    # shellcheck disable=SC2086
    sudo pacman -S --needed --noconfirm $MISSING
else
    echo "All dependencies are satisfied."
fi

# 2. Clone the repository
TARGET_DIR="$HOME/.local/share/applications/GabuMusic"

if [ -d "$TARGET_DIR" ]; then
    echo "Target directory already exists. Cleaning it up for a fresh install..."
    rm -rf "$TARGET_DIR"
fi

echo "Cloning https://github.com/boopidoopiloopi/linuxvoicemod.git..."
git clone https://github.com/boopidoopiloopi/linuxvoicemod.git "$TARGET_DIR"

# 3. Remove installer.sh from the cloned local repo
if [ -f "$TARGET_DIR/installer.sh" ]; then
    echo "Removing installer.sh from the destination folder..."
    rm "$TARGET_DIR/installer.sh"
fi

# 4. Make the runtime scripts executable
echo "Setting execution permissions..."
chmod +x "$TARGET_DIR/Daddy.sh" 2>/dev/null || true
chmod +x "$TARGET_DIR/VoiceModLOL.sh" 2>/dev/null || true

# 5. Link the .desktop file to the parent applications folder
# (Desktop environments often ignore .desktop files hidden inside subfolders.
# Creating a symlink here ensures "GabuMusic" actually appears in your app launcher)
if [ -f "$TARGET_DIR/GabuMusic.desktop" ]; then
    ln -sf "$TARGET_DIR/GabuMusic.desktop" "$HOME/.local/share/applications/GabuMusic.desktop"
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

echo "=== Installation Complete! ==="
echo "Please ensure EasyEffects is running and properly configured for your hardware mic!"
echo ""

# 6. Restore terminal input
# This disconnects stdin from the curl pipe and reconnects it to the user's actual 
# keyboard. Without this, 'read' would swallow script characters and 'glow' would 
# crash because the pager needs a real terminal to read arrow keys/quit commands.
exec < /dev/tty

# Prompt the user to read the README
read -p "Would you like to read the README instructions now? [Y/n] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    # -p opens it in a pager so they can scroll up and down (like 'less')
    glow -p "$TARGET_DIR/README.md"
else
    echo "You can read it later by running: glow $TARGET_DIR/README.md"
fi

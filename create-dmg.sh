#!/bin/bash
set -e

# create-dmg.sh - Creates a distributable DMG for macOS apps
# Usage: ./create-dmg.sh <app_path> <dmg_name> <volume_name>
#
# Example: ./create-dmg.sh build/Release/NextcloudDeck.app NextcloudDeck-1.0.0.dmg 'Nextcloud Deck 1.0.0'

APP_PATH="$1"
DMG_NAME="$2"
VOLUME_NAME="$3"

if [ -z "$APP_PATH" ] || [ -z "$DMG_NAME" ] || [ -z "$VOLUME_NAME" ]; then
  echo "Usage: $0 <app_path> <dmg_name> <volume_name>"
  echo "Example: $0 build/Release/NextcloudDeck.app NextcloudDeck-1.0.0.dmg 'Nextcloud Deck 1.0.0'"
  exit 1
fi

if [ ! -d "$APP_PATH" ]; then
  echo "Error: App not found at $APP_PATH"
  exit 1
fi

APP_NAME=$(basename "$APP_PATH")

echo "Creating DMG for: $APP_PATH"
echo "Output DMG: $DMG_NAME"
echo "Volume name: $VOLUME_NAME"

# Create temporary directory for DMG contents
TEMP_DIR=$(mktemp -d)
echo "Using temp directory: $TEMP_DIR"

# Copy app to temp directory
echo "Copying app to temp directory..."
cp -R "$APP_PATH" "$TEMP_DIR/"

# Create Applications symlink for easy installation
echo "Creating Applications symlink..."
ln -s /Applications "$TEMP_DIR/Applications"

# Calculate size needed (app size + 10MB buffer)
APP_SIZE=$(du -sm "$APP_PATH" | cut -f1)
DMG_SIZE=$((APP_SIZE + 10))
echo "App size: ${APP_SIZE}MB, DMG size: ${DMG_SIZE}MB"

# Create temporary DMG
TEMP_DMG="temp_$DMG_NAME"
echo "Creating temporary DMG..."
hdiutil create -srcfolder "$TEMP_DIR" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -fsargs "-c c=64,a=16,e=16" \
  -format UDRW \
  -size ${DMG_SIZE}m \
  "$TEMP_DMG"

# Mount the temporary DMG
echo "Mounting temporary DMG..."
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" | grep '/Volumes/' | sed 's/.*\t//')
echo "Mounted at: $MOUNT_DIR"

if [ -z "$MOUNT_DIR" ]; then
  echo "Error: Failed to mount DMG or extract mount point"
  rm -rf "$TEMP_DIR"
  rm -f "$TEMP_DMG"
  exit 1
fi

# Set DMG icon positions and appearance (AppleScript uses app name from variable)
echo "Configuring DMG appearance..."
cat > /tmp/dmg-setup.applescript << EOF
on run argv
  set volumeName to item 1 of argv
  set appName to item 2 of argv
  tell application "Finder"
    tell disk volumeName
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {100, 100, 600, 400}
      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 72
      set position of item appName of container window to {150, 150}
      set position of item "Applications" of container window to {350, 150}
      close
      open
      update without registering applications
      delay 2
    end tell
  end tell
end run
EOF

osascript /tmp/dmg-setup.applescript "$VOLUME_NAME" "$APP_NAME" 2>/dev/null || echo "Note: Could not set DMG appearance (non-critical)"
rm -f /tmp/dmg-setup.applescript

# Ensure changes are written
sync

# Unmount the DMG
echo "Unmounting temporary DMG..."
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed, read-only DMG
echo "Compressing final DMG..."
hdiutil convert "$TEMP_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_NAME"

# Clean up
echo "Cleaning up..."
rm -rf "$TEMP_DIR"
rm -f "$TEMP_DMG"

echo ""
echo "✅ DMG created successfully: $DMG_NAME"
ls -lh "$DMG_NAME"

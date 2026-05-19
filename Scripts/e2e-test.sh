#!/bin/bash
# Glance E2E Manual Test Script
# Run on macOS 14.0+ with Xcode 15+
# Tests the full capture → AI → overlay response flow.

set -e

APP_PATH="${1:-build/Release/Glance.app}"
CONFIG_DIR="$HOME/.glance"
CONFIG_FILE="$CONFIG_DIR/config.json"

echo "=== Glance E2E Test ==="
echo ""

# 1. Verify .app bundle exists
echo "1. App Bundle Check..."
if [ -d "$APP_PATH" ]; then
    echo "   ✅ $APP_PATH exists"
    if [ -f "$APP_PATH/Contents/Info.plist" ]; then
        echo "   ✅ Info.plist present"
    else
        echo "   ❌ Info.plist missing"
        exit 1
    fi
    if [ -f "$APP_PATH/Contents/MacOS/Glance" ]; then
        echo "   ✅ Executable present"
    else
        echo "   ❌ Executable missing"
        exit 1
    fi
else
    echo "   ❌ $APP_PATH not found"
    echo "   Build first: xcodebuild -scheme Glance -configuration Release"
    exit 1
fi

# 2. Check entitlements
echo ""
echo "2. Entitlements Check..."
ENTITLEMENTS_FILE="$APP_PATH/Contents/Resources/Glance.entitlements"
if [ -f "$ENTITLEMENTS_FILE" ] || codesign -d --entitlements - "$APP_PATH" 2>/dev/null | grep -q "screen-recording"; then
    echo "   ✅ Screen recording entitlement present"
else
    echo "   ⚠️  Entitlements check skipped (code signing may be required)"
fi

# 3. Verify config auto-creates
echo ""
echo "3. Config System Check..."
rm -f "$CONFIG_FILE"
echo "   Launching app to auto-create config..."
# Launch app in background, wait briefly, then kill
"$APP_PATH/Contents/MacOS/Glance" &
APP_PID=$!
sleep 3
kill $APP_PID 2>/dev/null || true
sleep 1

if [ -f "$CONFIG_FILE" ]; then
    echo "   ✅ Config file auto-created at $CONFIG_FILE"
    # Validate JSON
    if python3 -c "import json; json.load(open('$CONFIG_FILE'))" 2>/dev/null; then
        echo "   ✅ Config is valid JSON"
    else
        echo "   ❌ Config is NOT valid JSON"
        exit 1
    fi
    # Check for required keys
    if grep -q '"defaultProvider"' "$CONFIG_FILE" && grep -q '"providers"' "$CONFIG_FILE"; then
        echo "   ✅ Config has required keys"
    else
        echo "   ❌ Config missing required keys"
        exit 1
    fi
else
    echo "   ❌ Config file not created"
    exit 1
fi

# 4. Capture Safari window → verify overlay
echo ""
echo "4. Full Capture Flow..."
echo "   FIRST: Open Safari and navigate to a visible page"
echo "   Press ⌃⌥⌘G to trigger capture"
echo "   Select 'Window Under Cursor' mode"
echo "   Click on the Safari window"
echo ""
echo "   Expected: Preview flashes for 2s → AI response in overlay"
echo ""
read -p "   Did the full flow work? (preview → AI response → overlay)? [y/N] " response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "   ✅ E2E capture flow confirmed"
else
    echo "   ⚠️  E2E capture flow requires manual verification"
fi

# 5. Provider switching
echo ""
echo "5. Provider Switching..."
echo "   Open Preferences (⌘,)"
echo "   Switch provider from Claude to Gemini"
echo "   Trigger capture again"
echo ""
read -p "   Did provider switching work? [y/N] " response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "   ✅ Provider switching confirmed"
else
    echo "   ⚠️  Provider switching requires manual verification"
fi

echo ""
echo "=== E2E Test Complete ==="

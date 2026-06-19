#!/usr/bin/env bash
#
# Build, install, and launch Pocket Casts on a chosen iPhone or simulator.
#
# Lists all available physical iPhones and booted simulators. If more than one
# is available, prompts you to pick one. Override the prompt by setting:
#   TARGET_NAME="iPhone 17"         # pick a sim or device by name
#   TARGET_INDEX=2                  # pick by menu number (1-based)
#
# Unlock physical iPhones before launching — iOS won't open apps on a locked
# device.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

BUNDLE_ID="com.colemanoei.comppodcast"
SCHEME="pocketcasts"

# Collect targets. Each line: "KIND|NAME|XCODE_DEST|DEVICE_ID"
#   KIND          = "device" (physical) or "sim" (simulator)
#   NAME          = display name
#   XCODE_DEST    = xcodebuild -destination value
#   DEVICE_ID     = id passed to devicectl/simctl for install/launch
TARGETS=()

echo "→ Scanning targets..."

# Physical iPhones (any state except "unavailable")
while IFS= read -r line; do
    name="$(echo "$line" | sed -E 's/^[[:space:]]+//' | awk -F'   +' '{print $1}')"
    device_id="$(echo "$line" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1)"
    [ -z "$device_id" ] && continue
    # xcodebuild can target physical devices by name
    TARGETS+=("device|$name|platform=iOS,name=$name|$device_id")
done < <(xcrun devicectl list devices 2>&1 | grep -E "iPhone " | grep -v "unavailable")

# Booted iOS simulators
while IFS= read -r line; do
    name="$(echo "$line" | sed -E 's/^[[:space:]]+//' | sed -E 's/ \([0-9A-F-]+\) \(Booted\).*$//')"
    sim_id="$(echo "$line" | grep -oE "[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}" | head -1)"
    [ -z "$sim_id" ] && continue
    TARGETS+=("sim|$name (booted)|platform=iOS Simulator,id=$sim_id|$sim_id")
done < <(xcrun simctl list devices booted 2>&1 | grep -E "^\s+\w" | grep "(Booted)")

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "✗ No available iPhones or booted simulators."
    echo "  Plug in your iPhone, or boot a simulator with:"
    echo "    xcrun simctl boot 'iPhone 17'"
    exit 1
fi

# Pick a target
echo ""
echo "Available targets:"
i=1
for t in "${TARGETS[@]}"; do
    name="$(echo "$t" | awk -F'|' '{print $2}')"
    kind="$(echo "$t" | awk -F'|' '{print $1}')"
    echo "  $i) [$kind] $name"
    i=$((i + 1))
done
echo ""

CHOICE=""
if [ -n "${TARGET_INDEX:-}" ]; then
    CHOICE="$TARGET_INDEX"
elif [ -n "${TARGET_NAME:-}" ]; then
    i=1
    for t in "${TARGETS[@]}"; do
        name="$(echo "$t" | awk -F'|' '{print $2}')"
        if [[ "$name" == *"$TARGET_NAME"* ]]; then
            CHOICE="$i"
            break
        fi
        i=$((i + 1))
    done
    if [ -z "$CHOICE" ]; then
        echo "✗ No target matched TARGET_NAME='$TARGET_NAME'"
        exit 1
    fi
elif [ ${#TARGETS[@]} -eq 1 ]; then
    CHOICE=1
else
    read -r -p "Select target [1]: " CHOICE
    CHOICE="${CHOICE:-1}"
fi

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#TARGETS[@]} ]; then
    echo "✗ Invalid selection: $CHOICE"
    exit 1
fi

TARGET="${TARGETS[$((CHOICE - 1))]}"
KIND="$(echo "$TARGET" | awk -F'|' '{print $1}')"
NAME="$(echo "$TARGET" | awk -F'|' '{print $2}')"
DEST="$(echo "$TARGET" | awk -F'|' '{print $3}')"
DEVICE_ID="$(echo "$TARGET" | awk -F'|' '{print $4}')"

echo "✓ Target: [$KIND] $NAME"
echo "  Destination: $DEST"

echo ""
echo "→ Building $SCHEME..."
xcodebuild \
    -project podcasts.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "$DEST" \
    build

APP_PATH="$(xcodebuild \
    -project podcasts.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "$DEST" \
    -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR / { print $2; exit }')/podcasts.app"

if [ ! -d "$APP_PATH" ]; then
    echo "✗ Built .app not found at $APP_PATH"
    exit 1
fi

echo ""
echo "→ Installing $APP_PATH"
if [ "$KIND" = "device" ]; then
    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
    echo ""
    echo "→ Launching $BUNDLE_ID"
    xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"
else
    xcrun simctl install "$DEVICE_ID" "$APP_PATH"
    echo ""
    echo "→ Launching $BUNDLE_ID"
    xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
fi

echo ""
echo "✓ Done."

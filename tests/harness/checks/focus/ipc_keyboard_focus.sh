#!/usr/bin/env bash
# Activation and remembered focus must not masquerade as keyboard focus while
# overview or a layer owns the keyboard, including overview's closing animation.
set -euo pipefail
source "$UMBRIEL_HARNESS_LIB"

readonly POINTER="${UMBRIEL_POINTER_CLIENT:-./build-debug/tests/pointer-client}"
readonly OBSERVER="${UMBRIEL_SEAT_LOG_CLIENT:-./build-debug/tests/seat-log-client}"
readonly LAYER="${UMBRIEL_LAYER_CLIENT:-./build-debug/tests/layer-client}"
readonly WINDOW_LOG="$UMBRIEL_RUNTIME_DIR/ipc-keyboard-window.log"
readonly LAYER_LOG="$UMBRIEL_RUNTIME_DIR/ipc-keyboard-layer.log"
readonly EVENTS="$UMBRIEL_RUNTIME_DIR/ipc-keyboard-events.log"

assert_keyboard_focus() {
  local expected=$1
  "$UMBRIEL" windows --json | jq -e --argjson expected "$expected" '
    length == 1
    and (.[0].keyboard_focused | type == "boolean")
    and .[0].keyboard_focused == $expected
  ' > /dev/null
  for _ in $(seq 40); do
    if jq -s -e --argjson expected "$expected" '
      map(select(.event == "windows")) | last | .data
      | length == 1 and .[0].keyboard_focused == $expected
    ' "$EVENTS" > /dev/null; then
      return 0
    fi
    sleep 0.05
  done
  echo "windows subscription did not report keyboard_focused=$expected"
  return 1
}

cat >> "$UMBRIEL_CONFIG" <<'EOF'

[animation.overview]
duration_ms = 500
curve = "linear"
EOF
"$UMBRIEL" msg config-reload > /dev/null
"$POINTER" 1280 720 mod none pause 60000 > /dev/null 2>&1 &
"$OBSERVER" ipc-keyboard-window > "$WINDOW_LOG" 2>&1 &
await_events "$WINDOW_LOG" keyboard-enter 1 "the window"
"$UMBRIEL" settle
"$UMBRIEL" subscribe windows > "$EVENTS" &
for _ in $(seq 40); do
  [[ -s $EVENTS ]] && break
  sleep 0.05
done
assert_keyboard_focus true
window_id=$("$UMBRIEL" windows --json | jq -r '.[0].id')

"$UMBRIEL" clock-freeze
"$UMBRIEL" msg overview-open > /dev/null
"$UMBRIEL" clock-advance 1000
await_events "$WINDOW_LOG" keyboard-leave 1 "the window in overview"
assert_keyboard_focus false
"$UMBRIEL" msg "window-focus:$window_id" > /dev/null
assert_keyboard_focus false
"$UMBRIEL" windows --json | jq -e '.[0].active == true' > /dev/null
"$UMBRIEL" msg overview-close > /dev/null
"$UMBRIEL" clock-advance 250
assert_keyboard_focus false
"$UMBRIEL" clock-advance 1000
await_events "$WINDOW_LOG" keyboard-enter 2 "the window after overview"
assert_keyboard_focus true
"$UMBRIEL" clock-resume

"$LAYER" HEADLESS-1 40 keyboard=on-demand > "$LAYER_LOG" 2>&1 &
await_events "$LAYER_LOG" keyboard-enter 1 "the layer"
assert_keyboard_focus false
"$UMBRIEL" msg "window-focus:$window_id" > /dev/null
await_events "$WINDOW_LOG" keyboard-enter 3 "the refocused window"
assert_keyboard_focus true

echo "keyboard_focused and windows events follow the seat rather than activation"

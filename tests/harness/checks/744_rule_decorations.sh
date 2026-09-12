#!/usr/bin/env bash
# The floating selector suppresses borders and restores them on retiling.
# Shadows and corner clipping follow the same rule. Reloading must restore
# decorations without remapping the client.
set -euo pipefail

cat >> "$UMBRIEL_CONFIG" <<'EOF'

[animation]
enabled = false
[colors]
backdrop = "#000000FF"
shadow = "#00FF00FF"
[colors.border]
focused = "#FF0000"
unfocused = "#FF0000"
[appearance]
border_width = 20
outer_border_width = 0
corner_radius = 40
[appearance.shadow]
enabled = true
softness = 24
offset_x = 0
offset_y = 0
[[window_rule]]
match.title = "^decoration-rule$"
match.is_floating = true
decorations = false
EOF
"$UMBRIEL" msg config-reload >/dev/null
"$UMBRIEL_UNMAP_CLIENT" decoration-rule 300 300 >"$UMBRIEL_RUNTIME_DIR/client.log" 2>&1 &
for _ in $(seq 80); do
  window=$("$UMBRIEL" windows --json | jq -c '.[] | select(.title == "decoration-rule")')
  [[ -n $window ]] && break
  sleep 0.025
done
[[ -n $window ]]

assert_border() {
  local expected=$1 x y red green blue
  "$UMBRIEL" settle
  window=$("$UMBRIEL" windows --json | jq -c '.[] | select(.title == "decoration-rule")')
  read -r x y < <(jq -r '"\(.x + (.w / 2 | floor)) \(.y - 8)"' <<<"$window")
  grim "$UMBRIEL_RUNTIME_DIR/decorations.png"
  read -r red green < <(magick "$UMBRIEL_RUNTIME_DIR/decorations.png" -crop "4x4+$x+$y" -format '%[fx:round(mean.r*255)] %[fx:round(mean.g*255)]\n' info:)
  if [[ $expected == visible ]]; then
    ((red > 220))
  else
    ((red < 20 && green < 20))
  fi || { echo "expected border $expected, red=$red green=$green"; exit 1; }
  read -r x y < <(jq -r '"\(.x + 1) \(.y + 1)"' <<<"$window")
  blue=$(magick "$UMBRIEL_RUNTIME_DIR/decorations.png" -crop "2x2+$x+$y" -format '%[fx:round(mean.b*255)]' info:)
  if [[ $expected == visible ]]; then
    ((blue < 20))
  else
    ((blue > 150))
  fi || { echo "unexpected corner clipping with border $expected, blue=$blue"; exit 1; }
}

assert_border visible
"$UMBRIEL" msg window-toggle-floating >/dev/null
assert_border hidden
"$UMBRIEL" msg window-toggle-fullscreen >/dev/null
"$UMBRIEL" msg window-toggle-fullscreen >/dev/null
assert_border hidden
"$UMBRIEL" msg window-toggle-floating >/dev/null
assert_border visible
"$UMBRIEL" msg window-toggle-floating >/dev/null
assert_border hidden
sed -i 's/decorations = false/decorations = true/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload >/dev/null
assert_border visible
sed -i 's/decorations = true/decorations = false/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload >/dev/null
assert_border hidden
echo "decoration rules follow floating state, fullscreen exit, and reload"

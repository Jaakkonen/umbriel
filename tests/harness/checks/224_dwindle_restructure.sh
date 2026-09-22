#!/usr/bin/env bash
# harness: outputs=2
# Keyboard split changes stay local until the tree boundary, then retain output/workspace traversal.
set -euo pipefail

cat >> "$UMBRIEL_CONFIG" <<'CONFIG'

[layout]
mode = "dwindle"
[layout.dwindle]
directional_move = "restructure"
[animation]
enabled = false
[keybinds]
"Mod+Down" = "window-move-or-output-down"
[output.HEADLESS-1]
mode = "3600x1200"
position = [0, 0]
workspaces = ["ONE", "TWO"]
[output.HEADLESS-2]
mode = "3600x1200"
position = [0, 1200]
workspaces = ["LOWER"]
CONFIG
"$UMBRIEL" msg config-reload > /dev/null
"$UMBRIEL" msg workspace-switch:ONE/HEADLESS-1 > /dev/null

windows() { "$UMBRIEL" windows --json | jq 'sort_by(.title)'; }
await_windows() {
  local predicate=$1 snapshot=
  for _ in $(seq 60); do
    snapshot=$(windows)
    jq -e "$predicate" <<< "$snapshot" > /dev/null && return 0
    sleep 0.05
  done
  echo "expected $predicate, got $snapshot"
  return 1
}

for title in a b c; do
  "$UMBRIEL_UNMAP_CLIENT" "$title" 300 200 > "$UMBRIEL_RUNTIME_DIR/$title.log" 2>&1 &
  await_windows "any(.[]; .title == \"$title\")"
done
readonly ROW='length == 3 and .[0].y == .[1].y and .[1].y == .[2].y and .[0].x < .[1].x and .[1].x < .[2].x'
await_windows "$ROW"
c_id=$(windows | jq -r '.[2].id')
one_id=$(windows | jq -r '.[2].workspace')
"$UMBRIEL" msg "window-focus:$c_id" > /dev/null

# Presentation states use the legacy path, without restructuring the hidden tree.
for state in fullscreen maximize maximize-to-edges; do
  "$UMBRIEL" msg "window-toggle-$state" > /dev/null
  "$UMBRIEL" msg window-move-down > /dev/null
  "$UMBRIEL" msg "window-toggle-$state" > /dev/null
  await_windows "$ROW"
done

# Slice the right-hand pair, then escape it. Both moves retain the output and focus.
"$UMBRIEL" msg window-move-or-output-down > /dev/null
await_windows '.[1].x == .[2].x and .[1].y < .[2].y and .[2].workspace == .[0].workspace and .[2].focused'
"$UMBRIEL" msg window-move-or-workspace-down > /dev/null
await_windows '.[2].x == .[0].x and .[2].y > .[0].y and .[2].y > .[1].y and .[2].workspace == .[0].workspace and .[2].focused'
"$UMBRIEL" msg window-move-or-output-down > /dev/null
await_windows '.[2].y >= 1200 and .[2].workspace != .[0].workspace and .[2].focused'

# Explicit output movement remains immediate. Reloading the mode leaves the current tree intact.
"$UMBRIEL" msg window-move-to-output-up > /dev/null
await_windows "$ROW"
before=$(windows | jq 'map({id,x,y,w,h,workspace})')
sed -i 's/directional_move = "restructure"/directional_move = "swap"/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload > /dev/null
"$UMBRIEL" msg window-move-down > /dev/null
[[ $(windows | jq 'map({id,x,y,w,h,workspace})') == "$before" ]]
sed -i 's/directional_move = "swap"/directional_move = "restructure"/' "$UMBRIEL_CONFIG"
"$UMBRIEL" msg config-reload > /dev/null
[[ $(windows | jq 'map({id,x,y,w,h,workspace})') == "$before" ]]

# The workspace composite performs the same two local steps before leaving workspace ONE.
for _ in 1 2 3; do
  "$UMBRIEL" msg window-move-or-workspace-down > /dev/null
done
await_windows '.[2].workspace != .[0].workspace and .[2].y < 1200 and .[2].focused'
"$UMBRIEL" msg window-move-to-workspace:ONE/HEADLESS-1 > /dev/null
await_windows "$ROW"

# A held key must traverse the same sequence. Virtual keyboards keep wlroots'
# repeat settings (600 ms initial delay), independent of input.keyboard config.
"$UMBRIEL_POINTER_CLIENT" 3600 2400 mod logo key-press 108 pause 1000 key-release 108 mod none
await_windows '.[2].y >= 1200 and .[2].focused'

# Floating focus retains the existing single-window output-transfer path.
"$UMBRIEL" msg window-toggle-floating > /dev/null
"$UMBRIEL" msg window-move-or-output-up > /dev/null
await_windows ".[2].workspace == \"$one_id\" and .[2].floating and .[2].focused"
# Ordinary vertical movement must retain keyboard focus when another tile fills
# the old location under a stationary pointer.
"$UMBRIEL" msg window-toggle-floating > /dev/null
await_windows "$ROW"
cat >> "$UMBRIEL_CONFIG" <<'CONFIG'
[input.focus]
follows_mouse = true
CONFIG
"$UMBRIEL" msg config-reload > /dev/null
read -r x y < <(windows | jq -r '.[2] | "\(.x + 10) \(.y + 10)"')
"$UMBRIEL_POINTER_CLIENT" 3600 2400 move "$x" "$y"
"$UMBRIEL" msg window-move-down > /dev/null
await_windows '.[1].y < .[2].y and .[2].focused'
echo "Dwindle restructuring creates splits, escapes groups, and preserves composite transfers"

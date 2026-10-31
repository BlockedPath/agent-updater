#!/bin/bash
# Capture the REAL app window (glass, toolbar, live rendering) into review/live/.
# Needs Screen Recording permission for Rex (granted). Uses fixture data unless "live".
#   ./review/live.sh            light/dark x compact/regular x All/Behind/Discover at 660x760
#   ./review/live.sh states     560-wide, failed first load, nothing installed, forced row phases
#   ./review/live.sh live       core set with real update-agents data
# Each capture launches the app, waits for it to settle, grabs the window, and quits it.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh --bundle-only >/dev/null
app="$PWD/.build/app/Agent Updater.app"
fixture="$PWD/review/fixture-script.sh"
mkdir -p review/live

cap() {  # cap NAME APPEARANCE COMPACT TAB [VAR=VALUE ...]
  local name=$1 appearance=$2 compact=$3 tab=$4; shift 4
  pkill -f "$app/Contents/MacOS/AgentUpdater" 2>/dev/null || true
  # Don't inherit the 560 pt frame autosaved by a previous state/interaction capture.
  # Explicit state arguments in "$@" can override this default.
  env AGENT_UPDATER_SCRIPT="${SCRIPT:-$fixture}" AGENT_UPDATER_TAB="$tab" AGENT_UPDATER_WINDOW=660x760 "$@" \
    "$app/Contents/MacOS/AgentUpdater" -appearance "$appearance" -compact "$compact" \
    -NSQuitAlwaysKeepsWindows NO >/dev/null 2>&1 &
  local pid=$! id=0 i
  for i in $(seq 1 40); do
    sleep 0.25
    id=$(swift review/winid.swift 2>/dev/null || echo 0)
    [[ $id != 0 ]] && break
  done
  sleep "${SETTLE:-4}"   # let the check, icons and animations finish
  if [[ $id != 0 ]] && screencapture -x -o -l "$id" "review/live/$name.png"; then
    echo "review/live/$name.png"
  else
    echo "FAILED to capture $name" >&2
  fi
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
}

# capseq PREFIX "T1 T2 …" [VAR=VALUE …]: launch once, capture at several times (seconds).
capseq() {
  local prefix=$1 times=$2; shift 2
  pkill -f "$app/Contents/MacOS/AgentUpdater" 2>/dev/null || true
  env AGENT_UPDATER_SCRIPT="$fixture" AGENT_UPDATER_WINDOW="${AGENT_UPDATER_WINDOW:-660x760}" "$@" \
    "$app/Contents/MacOS/AgentUpdater" -appearance light -compact 1 -NSQuitAlwaysKeepsWindows NO >/dev/null 2>&1 &
  local pid=$! id=0 t prev=0 i
  for i in $(seq 1 40); do sleep 0.25; id=$(swift review/winid.swift 2>/dev/null || echo 0); [[ $id != 0 ]] && break; done
  for t in $times; do
    sleep "$(echo "$t - $prev" | bc)"; prev=$t
    screencapture -x -o -l "$id" "review/live/$prefix-${t}s.png" && echo "review/live/$prefix-${t}s.png"
  done
  kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
}

case ${1:-core} in
  lifecycle)
    # Update All (amp fails), then install OpenCode and uninstall herdr, against a stateful fixture.
    st=$(mktemp -t agent-updater-fixture); rm -f "$st"
    capseq lifecycle "2 7 14 22" AGENT_UPDATER_FIXTURE_STATE="$st" AGENT_UPDATER_FAIL=amp \
      AGENT_UPDATER_ACTIONS="updateall;install:opencode;uninstall:herdr"
    rm -f "$st" ;;
  core | live)
    [[ ${1:-} == live ]] && SCRIPT="$HOME/.local/bin/update-agents" SETTLE=12
    for a in light dark; do for c in 1 0; do for t in All Updates Discover; do
      cap "$a-$([[ $c == 1 ]] && echo compact || echo regular)-$t" $a $c $t
    done; done; done ;;
  states)
    cap state-560-compact light 1 All AGENT_UPDATER_WINDOW=560x760
    cap state-560-regular dark 0 All AGENT_UPDATER_WINDOW=560x760
    cap state-failed light 1 All AGENT_UPDATER_SCENARIO=failed
    cap state-empty dark 1 All AGENT_UPDATER_SCENARIO=empty
    cap state-phases-compact light 1 All AGENT_UPDATER_PHASES="codex=updating,amp=failed,herdr=staged,droid=queued,claude=updated"
    cap state-phases-regular dark 0 All AGENT_UPDATER_PHASES="codex=updating,amp=failed,herdr=staged,droid=queued,claude=updated" ;;
esac

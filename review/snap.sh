#!/bin/bash
# Render the app offscreen into review/shots/.
#   ./review/snap.sh             core set: light/dark x compact/regular x All/Updates/Discover at 660 pt
#   ./review/snap.sh states      state set: 560 pt widths, failed first load, nothing installed,
#                                everything hidden, and forced row phases (queued/updating/failed/staged/updated)
#   ./review/snap.sh live        core set with real update-agents data
# Every shot uses fixture data (3 updates available, droid "couldn't check") unless "live".
# Limits: ImageRenderer can't draw Liquid Glass, toolbars/window chrome, the segmented picker
# (yellow placeholder), menus, sheets or Settings. Judge those from code or live captures.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh --bundle-only >/dev/null  # notifications need a real app bundle
bin="$PWD/.build/app/Agent Updater.app/Contents/MacOS/AgentUpdater"
fixture="$PWD/review/fixture-script.sh"
mkdir -p review/shots

# shot NAME APPEARANCE COMPACT TAB [VAR=VALUE ...]: one render.
shot() {
  local name=$1 appearance=$2 compact=$3 tab=$4; shift 4
  env AGENT_UPDATER_SCRIPT="${SCRIPT:-$fixture}" AGENT_UPDATER_TAB="$tab" \
    AGENT_UPDATER_SNAPSHOT="$PWD/review/shots/$name.png" "$@" \
    timeout 60 "$bin" -appearance "$appearance" -compact "$compact" >/dev/null 2>&1 || true
  echo "review/shots/$name.png"
}

case ${1:-core} in
  core | live)
    [[ ${1:-} == live ]] && SCRIPT="$HOME/.local/bin/update-agents"
    for a in light dark; do for c in 1 0; do for t in All Updates Discover; do
      shot "$a-$([[ $c == 1 ]] && echo compact || echo regular)-$t" $a $c $t
    done; done; done ;;
  states)
    shot state-560-compact light 1 All AGENT_UPDATER_SNAPSHOT_WIDTH=560
    shot state-560-regular dark 0 All AGENT_UPDATER_SNAPSHOT_WIDTH=560
    shot state-failed light 1 All AGENT_UPDATER_SCENARIO=failed
    shot state-empty light 1 All AGENT_UPDATER_SCENARIO=empty
    env AGENT_UPDATER_SCRIPT="$fixture" AGENT_UPDATER_TAB=All AGENT_UPDATER_SNAPSHOT="$PWD/review/shots/state-allhidden.png" \
      timeout 60 "$bin" -appearance dark -compact 1 -hidden '(amp,codex,agy,claude,cursor-agent,droid,grok,muse,pi,herdr,t3,"Grok Bot",Muse,"Claude Duet")' >/dev/null 2>&1 || true
    shot state-phases-compact light 1 All AGENT_UPDATER_PHASES="codex=updating,amp=failed,herdr=staged,droid=queued,claude=updated"
    shot state-phases-regular dark 0 All AGENT_UPDATER_PHASES="codex=updating,amp=failed,herdr=staged,droid=queued,claude=updated" ;;
esac

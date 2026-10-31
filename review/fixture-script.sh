#!/bin/bash
# Stand-in for update-agents used by the review renders.
#   AGENT_UPDATER_SCENARIO=normal (default) | failed | empty
#   AGENT_UPDATER_FIXTURE_STATE=/path/state.json  makes it stateful: --yes NAME marks NAME
#       current, --install moves a catalog entry into the installed list, --uninstall removes it.
#   AGENT_UPDATER_FAIL=amp,opencode  makes those names' update/install/uninstall fail.
# Every mutation sleeps a moment so in-progress states are visible.
dir=$(cd "$(dirname "$0")" && pwd)
state=${AGENT_UPDATER_FIXTURE_STATE:-}
if [[ -n $state && ! -f $state ]]; then cp "$dir/fixture.json" "$state"; fi
data=${state:-$dir/fixture.json}
name=${*: -1}
fails() { [[ ",${AGENT_UPDATER_FAIL:-}," == *",$name,"* ]]; }
save() { [[ -n $state ]] && jq "$1" --arg n "$name" "$state" > "$state.tmp" && mv "$state.tmp" "$state"; }

case " $* " in
  *" --json "*)
    case ${AGENT_UPDATER_SCENARIO:-normal} in
      failed) echo "curl: (6) Could not resolve host: registry.npmjs.org" >&2; exit 1 ;;
      empty) jq '.agents = [] | .systems = []' "$data" ;;
      *) cat "$data" ;;
    esac ;;
  *" --dry-run "*) echo "path:$HOME/.local/bin/$name" ;;
  *" --install "*)
    sleep 3
    if fails; then echo "npm ERR! 404 Not Found - GET https://registry.npmjs.org/$name"; exit 1; fi
    save '(.available[] | select(.name == $n)) as $c
      | .agents += [{name: $n, kind: ($c.kind // "agent"), installed: $c.latest, latest: $c.latest, status: "current",
                     updater: $c.install, bin: ("/opt/homebrew/bin/" + $n), install_path: ("/opt/homebrew/lib/node_modules/" + $n),
                     last_updated: (now | todate), app: null, icon_url: $c.icon_url}]
      | .available |= map(select(.name != $n))'
    echo "added 1 package in 3s" ;;
  *" --uninstall "*)
    sleep 2
    if fails; then echo "mv: rename $HOME/.local/bin/$name: Operation not permitted"; exit 1; fi
    save '.agents |= map(select(.name != $n)) | .systems |= map(select(.name != $n))'
    echo "uninstalled $name" ;;
  *)
    sleep 3
    if fails; then echo "error: download failed: connection reset by peer"; exit 1; fi
    save '.agents |= map(if .name == $n then .installed = (.latest // .installed) | .status = "current" | .last_updated = (now | todate) else . end)'
    echo "updated $name" ;;
esac

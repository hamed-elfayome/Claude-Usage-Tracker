#!/usr/bin/env bash
# Manual test driver for the Claude Code notch HUD hook server.
# Usage: run the app with the HUD enabled, then:  bash test_notch.sh [movie|abuse]
# The token is read from the app's UserDefaults (notchHUDPathToken).

set -u
PORT=19847
TOKEN=$(defaults read HamedElfayome.Claude-Usage notchHUDPathToken 2>/dev/null)
if [ -z "${TOKEN}" ]; then echo "no notchHUDPathToken in defaults — enable the HUD once first"; exit 1; fi
BASE="http://127.0.0.1:${PORT}/hook/${TOKEN}"
SESSION="movie-$$"
CWD="$HOME/projects/demo-app"

post() { # url json
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$1" \
    -H "Content-Type: application/json" --data "$2")
  echo "  $1 -> HTTP $code"
}

movie() {
  echo "▶ full session movie (watch the notch)"
  post "$BASE/session-start"       "{\"session_id\":\"$SESSION\",\"cwd\":\"$CWD\"}"
  sleep 1.5
  post "$BASE/user-prompt-submit"  "{\"session_id\":\"$SESSION\",\"prompt\":\"add dark mode to the settings screen\"}"
  sleep 1.5
  post "$BASE/pre-tool-use"        "{\"session_id\":\"$SESSION\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$CWD/Settings.swift\"}}"
  sleep 2
  post "$BASE/post-tool-use"       "{\"session_id\":\"$SESSION\"}"
  post "$BASE/pre-tool-use"        "{\"session_id\":\"$SESSION\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$CWD/Settings.swift\"}}"
  sleep 2
  post "$BASE/post-tool-use"       "{\"session_id\":\"$SESSION\"}"
  post "$BASE/pre-tool-use"        "{\"session_id\":\"$SESSION\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"swift build && swift test\"}}"
  sleep 2.5
  post "$BASE/post-tool-use-failure" "{\"session_id\":\"$SESSION\"}"
  sleep 2
  post "$BASE/notification"        "{\"session_id\":\"$SESSION\",\"message\":\"Claude needs your permission to use Bash\"}"
  echo "  (needs-attention pulse — 6s)"
  sleep 6
  post "$BASE/pre-tool-use"        "{\"session_id\":\"$SESSION\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"swift test\"}}"
  sleep 2
  post "$BASE/stop"                "{\"session_id\":\"$SESSION\"}"
  echo "  (idle — HUD should auto-hide after ~5s if enabled)"
  sleep 7
  post "$BASE/session-end"         "{\"session_id\":\"$SESSION\"}"
  echo "✓ movie done"
}

abuse() {
  echo "▶ abuse cases (expect 404/405/413/200)"
  post "http://127.0.0.1:${PORT}/hook/session-start" '{"session_id":"legacy"}'           # tokenless legacy -> 404
  post "http://127.0.0.1:${PORT}/hook/wrongtoken/stop" '{"session_id":"spoof"}'          # bad token -> 404
  post "$BASE/permission-request" '{"session_id":"x"}'                                    # not in allowlist -> 404
  echo -n "  GET  $BASE/stop -> "; curl -s -o /dev/null -w "HTTP %{http_code}\n" "$BASE/stop"   # GET -> 405
  post "$BASE/stop" "{\"session_id\":\"pad\",\"junk\":\"$(head -c 100000 /dev/zero | tr '\0' 'a')\"}"  # >64KB -> 413
  post "$BASE/stop" '{not json'                                                           # malformed -> 200 (dropped)
  echo "✓ abuse done"
}

case "${1:-movie}" in
  movie) movie ;;
  abuse) abuse ;;
  *) echo "usage: $0 [movie|abuse]"; exit 1 ;;
esac

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# Même session et mêmes vues, avec une entrée de test et un historique temporaire.
python3 - "$work/MeetinOS.swift" <<'PY'
from pathlib import Path
import sys
source = Path("mac/MeetinOS.swift").read_text()
assert source.count("@main\n") == 1
assert source.count("let store = MeetingStore()") == 1
assert source.count("private static let stopLimit: TimeInterval = 30") == 1
source = source.replace("@main\n", "", 1).replace(
    "let store = MeetingStore()",
    'let store = MeetingStore(folder: URL(fileURLWithPath: ProcessInfo.processInfo.environment["MEETIN_SMOKE_FOLDER"]!))'
)
source = source.replace("private static let stopLimit: TimeInterval = 30", "private static let stopLimit: TimeInterval = 0.1")
Path(sys.argv[1]).write_text(source)
PY
sources=()
for source in mac/*.swift; do
  case "$source" in
    mac/MeetinOS.swift|mac/GladiaKeyStore.swift|mac/TaskNotifications.swift|mac/LiveAlerts.swift) ;;
    *) sources+=("$source") ;;
  esac
done
swiftc -parse-as-library -target "$(uname -m)-apple-macos15.0" \
  "${sources[@]}" "$work/MeetinOS.swift" brand/MeetinTheme.swift brand/MeetinComponents.swift \
  mac/tests/MeetingFlowSmoke.swift -o "$work/flow-smoke"
MEETIN_SMOKE_FOLDER="$work/history" GLADIA_API_KEY="" "$work/flow-smoke"

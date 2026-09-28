# Shared helpers for the Stage 2 walkthrough scripts.
# Every script prints each step with a plain-English explanation, runs it,
# checks the result, and saves a colour-free transcript under logs/.
# Written for macOS bash 3.2+ (no bash-4-only features).

set -o pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$ROOT/infra/walkthrough/logs"
mkdir -p "$LOG_DIR"

start_transcript() { # start_transcript <name>
  LOG="$LOG_DIR/$1-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee >(sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g' >> "$LOG")) 2>&1
  printf 'Transcript: %s\nStarted:    %s\n' "$LOG" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
}

PASS=0; FAIL=0; RC=0

step()    { printf '\n\033[1m━━━ %s ━━━\033[0m\n' "$1"; }
explain() { printf '%s\n' "$1" | fold -s -w 110 | sed 's/^/  │ /'; }
run()     { printf '\n\033[36m$ %s\033[0m\n' "$1"; eval "$1"; RC=$?; return 0; }
ok()      { PASS=$((PASS+1)); printf '  \033[32m✔ %s\033[0m\n' "$1"; }
bad()     { FAIL=$((FAIL+1)); printf '  \033[31m✘ %s\033[0m\n' "$1"; }

expect_rc() { # expect_rc <expected-exit-code> <label>
  if [ "$RC" = "$1" ]; then ok "$2 (exit $RC)"; else bad "$2 (exit $RC, expected $1)"; fi
}
check() { # check <label> <shell test>
  # pipefail is switched off inside checks: in "cmd | grep -q x" the verdict is grep's,
  # even when cmd itself exits non-zero (e.g. a plan that is meant to fail).
  if (set +o pipefail; eval "$2") >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi
}
must_pass() { # stop the script if anything has failed so far
  if [ "$FAIL" -gt 0 ]; then
    printf '\n\033[31mStopping here: %s check(s) failed above. Nothing after this point was run.\033[0m\n' "$FAIL"
    summary; exit 1
  fi
}
summary() {
  printf '\n\033[1m━━━ Summary ━━━\033[0m\n  %s passed, %s failed\n  Finished: %s\n  Transcript: %s\n' \
    "$PASS" "$FAIL" "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$LOG"
  sleep 1
}

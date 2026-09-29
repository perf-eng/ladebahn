#!/usr/bin/env bash
# Writes the "Results page" of a Load test run: k6's table plus a Grafana link
# to the exact time window of the run.  Usage: load-summary.sh <server|ci>
set -uo pipefail
env_name="${1:?server or ci}"
end_ms=$(date +%s%3N)

{
  if [ -f k6-summary.md ]; then
    cat k6-summary.md
  else
    echo "### k6 result — $env_name"
    echo
    echo "k6 did not finish, so there is no summary. Check the **Run k6** step."
  fi
  echo
  if [ -n "${GRAFANA_URL:-}" ] && [ -n "${START_MS:-}" ] && [ "${TELEMETRY:-true}" = "true" ]; then
    # Metrics reach Grafana once a minute and p95 uses a 5-minute window: widen the view.
    from=$(( START_MS - 60000 ))
    to=$(( end_ms + 180000 ))
    echo "📈 **See this run in Grafana:** [Ladebahn — $env_name](${GRAFANA_URL%/}/d/ladebahn-$env_name?from=$from&to=$to)"
    echo
    echo "_Metrics arrive once a minute — if the right-hand edge looks empty, refresh in a couple of minutes._"
  elif [ -z "${GRAFANA_URL:-}" ]; then
    echo "_Set the repository variable \`GRAFANA_URL\` to get a Grafana link here (README → One-time setup)._"
  fi
} >> "$GITHUB_STEP_SUMMARY"

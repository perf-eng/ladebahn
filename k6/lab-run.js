// Ladebahn — load run with a timed lab switch.
// Used by the "Load test (k6)" GitHub Action, and runnable by hand:
//
//   BASE_URL=http://localhost:8080 VUS=5 DURATION=5m \
//   LAB=slow_response LAB_PARAM=250 SWITCH_ON_AT=2m SWITCH_OFF_AT=4m \
//   k6 run k6/lab-run.js
//
// Every request is tagged with the phase it ran in (warmup / before / lab / after,
// or warmup / steady when no lab is used), so the summary shows p95 per phase:
// "p95 before the switch 45 ms, while it was on 280 ms, after 40 ms".
//
// The switch is flipped by virtual user 1 inside the normal traffic, so the run
// never uses more users than VUS. teardown() switches the lab off again, and the
// GitHub Action switches it off once more afterwards, even if the run is cancelled.

import http from 'k6/http';
import exec from 'k6/execution';
import { check, sleep } from 'k6';

const BASE = (__ENV.BASE_URL || 'http://localhost:8080').replace(/\/$/, '');
const TARGET = __ENV.TARGET || 'local';          // local | server | ci — only used for labels and the cap
const LAB = __ENV.LAB || 'none';                  // none | slow_response | n_plus_one | drop_index
const LAB_PARAM = __ENV.LAB_PARAM || '';          // e.g. 250 (ms) for slow_response; empty = app default
const LAB_TOKEN = __ENV.LAB_TOKEN || 'local-dev-token';
const VUS = parseInt(__ENV.VUS || '5', 10);
const DURATION = __ENV.DURATION || '5m';
const WARMUP = __ENV.WARMUP || '30s';
const SWITCH_ON_AT = __ENV.SWITCH_ON_AT || '2m';
const SWITCH_OFF_AT = __ENV.SWITCH_OFF_AT || '4m';
const SERVER_MAX_VUS = 5;                         // the demo server is shared: never more than this

function seconds(text) {
  const m = /^(\d+)(s|m)$/.exec(String(text).trim());
  if (!m) throw new Error(`bad duration "${text}" — use e.g. 90s or 5m`);
  return parseInt(m[1], 10) * (m[2] === 'm' ? 60 : 1);
}

const DURATION_S = seconds(DURATION);
const WARMUP_S = Math.min(seconds(WARMUP), DURATION_S);
const ON_S = seconds(SWITCH_ON_AT);
const OFF_S = seconds(SWITCH_OFF_AT);
const USE_LAB = LAB !== 'none';

if (TARGET === 'server' && VUS > SERVER_MAX_VUS) {
  throw new Error(`the demo server is capped at ${SERVER_MAX_VUS} virtual users (asked for ${VUS})`);
}
if (USE_LAB && !(ON_S < OFF_S && OFF_S <= DURATION_S)) {
  throw new Error(`switch times must satisfy on < off <= duration (on ${ON_S}s, off ${OFF_S}s, duration ${DURATION_S}s)`);
}

const PHASES = USE_LAB ? ['warmup', 'before', 'lab', 'after'] : ['warmup', 'steady'];

// Thresholds that always pass, declared only so the summary reports each phase separately.
const perPhase = {};
for (const p of PHASES) perPhase[`http_req_duration{phase:${p}}`] = ['max>=0'];

export const options = {
  scenarios: {
    traffic: { executor: 'constant-vus', vus: VUS, duration: DURATION, gracefulStop: '10s' },
  },
  thresholds: Object.assign({ http_req_failed: ['rate<0.10'] }, perPhase),
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// Weighted toward the dense cities, like the seeder and k6/nearby.js
const ORIGINS = [
  { lat: 52.5219, lon: 13.4132 }, // Berlin
  { lat: 53.5511, lon: 9.9937 },  // Hamburg
  { lat: 48.1351, lon: 11.582 },  // München
];

function phaseAt(elapsedS) {
  if (elapsedS < WARMUP_S) return 'warmup';
  if (!USE_LAB) return 'steady';
  if (elapsedS < ON_S) return 'before';
  if (elapsedS < OFF_S) return 'lab';
  return 'after';
}

function flip(on) {
  const query = on && LAB_PARAM !== '' ? `?param=${encodeURIComponent(LAB_PARAM)}` : '';
  const res = http.post(`${BASE}/labs/${LAB}/${on ? 'enable' : 'disable'}${query}`, null, {
    headers: { 'X-Lab-Token': LAB_TOKEN },
    tags: { phase: 'switch' },
  });
  console.log(`${on ? 'ENABLE ' : 'DISABLE'} ${LAB}${query} -> HTTP ${res.status}`);
  return res.status === 200;
}

export function setup() {
  const health = http.get(`${BASE}/actuator/health`, { tags: { phase: 'setup' } });
  if (health.status !== 200) throw new Error(`${BASE} is not healthy (HTTP ${health.status})`);
  if (USE_LAB) {
    // Start from a known state: the lab off.
    flip(false);
    if (ON_S === 0) flip(true);
  }
  console.log(`target=${TARGET} base=${BASE} vus=${VUS} duration=${DURATION} lab=${LAB} on=${ON_S}s off=${OFF_S}s`);
  return { startedAt: Date.now() };
}

let switchedOn = false;
let switchedOff = false;

export default function () {
  const elapsedS = (Date.now() - exec.scenario.startTime) / 1000;

  // Virtual user 1 is the one hand on the switch.
  if (USE_LAB && exec.vu.idInTest === 1) {
    if (!switchedOn && ON_S > 0 && elapsedS >= ON_S) { flip(true); switchedOn = true; }
    if (!switchedOff && elapsedS >= OFF_S) { flip(false); switchedOff = true; }
  }

  const o = ORIGINS[Math.floor(Math.random() * ORIGINS.length)];
  const res = http.get(`${BASE}/api/v1/sites/nearby?lat=${o.lat}&lon=${o.lon}&radiusKm=5&size=20`, {
    tags: { phase: phaseAt(elapsedS), name: 'nearby' },
  });
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}

export function teardown() {
  if (USE_LAB) flip(false);
}

// ---- Summary: plain text for the log, Markdown for the GitHub job page, JSON as an artifact
function ms(v) { return v === undefined || v === null ? '–' : `${Math.round(v)} ms`; }
function pct(v) { return v === undefined || v === null ? '–' : `${(v * 100).toFixed(2)} %`; }

export function handleSummary(data) {
  const m = data.metrics;
  const rows = PHASES.map((p) => {
    const t = m[`http_req_duration{phase:${p}}`];
    const v = t ? t.values : {};
    return { phase: p, med: v.med, p95: v['p(95)'], p99: v['p(99)'], max: v.max };
  });
  const reqs = m.http_reqs ? m.http_reqs.values : {};
  const failed = m.http_req_failed ? m.http_req_failed.values.rate : undefined;
  const checks = m.checks ? m.checks.values.rate : undefined;

  const labLine = USE_LAB
    ? `\`${LAB}\`${LAB_PARAM ? ` (param ${LAB_PARAM})` : ''} on at ${SWITCH_ON_AT}, off at ${SWITCH_OFF_AT}`
    : 'none';
  const md = [
    `### k6 result — ${TARGET}`,
    '',
    `| Setting | Value |`,
    `|---|---|`,
    `| Target | ${BASE} |`,
    `| Virtual users | ${VUS} |`,
    `| Duration | ${DURATION} (first ${WARMUP} = warm-up, reported separately) |`,
    `| Lab switch | ${labLine} |`,
    `| Requests | ${reqs.count ?? '–'} (${reqs.rate ? reqs.rate.toFixed(1) : '–'} /s) |`,
    `| Failed requests | ${pct(failed)} |`,
    `| Checks passed | ${pct(checks)} |`,
    '',
    '| Phase | median | p95 | p99 | max |',
    '|---|---|---|---|---|',
    ...rows.map((r) => `| ${r.phase} | ${ms(r.med)} | ${ms(r.p95)} | ${ms(r.p99)} | ${ms(r.max)} |`),
    '',
    'Client-side numbers, measured by k6. Server-side p95 in Grafana comes from histogram buckets and reads higher (see the lab book).',
    '',
  ].join('\n');

  const text = md.replace(/\|/g, ' ').replace(/`/g, '').replace(/^###\s*/gm, '');
  return {
    stdout: `\n${text}\n`,
    'k6-summary.md': md,
    'k6-summary.json': JSON.stringify(data, null, 2),
  };
}

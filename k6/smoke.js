import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';
const SLEEP_MS = __ENV.SLEEP_MS || 50;

export const options = {
  scenarios: {
    warmup: {
      executor: 'constant-vus',
      vus: 2,
      duration: '30s',
      tags: { phase: 'warmup' },
    },
    measure: {
      executor: 'constant-vus',
      vus: 5,
      duration: '60s',
      startTime: '30s',
      tags: { phase: 'measure' },
    },
  },
  thresholds: {
    'http_req_failed': ['rate<0.01'],
    'http_req_duration{phase:measure}': ['p(95)<500'],
  },
};

export default function () {
  const res = http.get(`${BASE}/health/slow?ms=${SLEEP_MS}`);
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(0.5);
}
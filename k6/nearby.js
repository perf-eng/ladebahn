import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';

// Weighted toward dense cities, mirroring the seeder's clustering.
const ORIGINS = [
  { name: 'Berlin',    lat: 52.5219, lon: 13.4132 },
  { name: 'Hamburg',   lat: 53.5511, lon:  9.9937 },
  { name: 'München',   lat: 48.1351, lon: 11.5820 },
  { name: 'Frankfurt', lat: 50.1109, lon:  8.6821 },
  { name: 'Leipzig',   lat: 51.3397, lon: 12.3731 },
];

export const options = {
  scenarios: {
    warmup:  { executor: 'constant-vus', vus: 2, duration: '30s', tags: { phase: 'warmup' } },
    measure: { executor: 'constant-vus', vus: 5, duration: '60s', startTime: '30s', tags: { phase: 'measure' } },
  },
  thresholds: {
    'http_req_failed': ['rate<0.01'],
    'http_req_duration{phase:measure}': ['p(95)<800'],
  },
};

export default function () {
  const o = ORIGINS[Math.floor(Math.random() * ORIGINS.length)];
  const radius = [2, 5, 10][Math.floor(Math.random() * 3)];

  const res = http.get(
    `${BASE}/api/v1/sites/nearby?lat=${o.lat}&lon=${o.lon}&radiusKm=${radius}&size=20`,
    { tags: { name: 'nearby' } }
  );

  check(res, {
    'status 200': (r) => r.status === 200,
    'has sites':  (r) => r.json('sites') !== undefined,
  });

  sleep(1);
}
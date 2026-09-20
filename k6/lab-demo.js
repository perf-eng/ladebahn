import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE  = __ENV.BASE_URL || 'http://localhost:8080';
const TOKEN = __ENV.LAB_TOKEN || 'local-dev-token';
const LAB   = __ENV.LAB || 'drop_index';

export const options = {
  scenarios: {
    traffic: {
      executor: 'constant-vus',
      vus: 5,
      duration: '5m',
    },
    enable_lab: {
      executor: 'shared-iterations',
      vus: 1, iterations: 1, startTime: '2m',
      exec: 'enableLab',
    },
    disable_lab: {
      executor: 'shared-iterations',
      vus: 1, iterations: 1, startTime: '4m',
      exec: 'disableLab',
    },
  },
};

const ORIGINS = [
  { lat: 52.5219, lon: 13.4132 },
  { lat: 53.5511, lon:  9.9937 },
  { lat: 48.1351, lon: 11.5820 },
];

export default function () {
  const o = ORIGINS[Math.floor(Math.random() * ORIGINS.length)];
  const res = http.get(
    `${BASE}/api/v1/sites/nearby?lat=${o.lat}&lon=${o.lon}&radiusKm=5&size=20`);
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(1);
}

export function enableLab() {
  const res = http.post(`${BASE}/labs/${LAB}/enable`, null,
    { headers: { 'X-Lab-Token': TOKEN } });
  console.log(`ENABLE ${LAB} -> ${res.status}`);
}

export function disableLab() {
  const res = http.post(`${BASE}/labs/${LAB}/disable`, null,
    { headers: { 'X-Lab-Token': TOKEN } });
  console.log(`DISABLE ${LAB} -> ${res.status}`);
}
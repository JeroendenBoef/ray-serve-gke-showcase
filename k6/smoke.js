import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 1,           // 1 req/sec to start
      timeUnit: '1s',
      preAllocatedVUs: 20,    // k6 will scale VUs up to hit the rate
      maxVUs: 200,
      stages: [
        { duration: '2m', target: 10 },  // up to 10 rps
        { duration: '2m', target: 30 },  // up to 30 rps
        { duration: '2m', target: 60 },  // up to 60 rps
      ],
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],      // <1% errors
    http_req_duration: ['p(95)<800'],    // 95% under 800ms (tune for your env)
  },
};

const URL = __ENV.INFER_URL || 'http://localhost:8000/infer';
const headers = { 'Content-Type': 'application/json' };
const candidates = [
  "this is great", "this is awful", "i love it", "i hate this",
  "fantastic work", "terrible idea", "pretty good", "not good",
];

export default function () {
  // small random batch per request to simulate variety
  const payload = JSON.stringify({
    inputs: [
      candidates[Math.floor(Math.random() * candidates.length)],
      candidates[Math.floor(Math.random() * candidates.length)],
    ],
  });

  const res = http.post(URL, payload, { headers });

  check(res, {
    'status is 200': (r) => r.status === 200,
    'looks like json': (r) => r.headers['Content-Type']?.includes('application/json'),
  });

  // tiny breathing room; keep small to maintain arrival rate accuracy
  sleep(0.01);
}

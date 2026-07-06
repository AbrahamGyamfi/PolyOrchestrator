import { describe, it, expect, vi } from 'vitest';
import request from 'supertest';

// Mock http-proxy-middleware to avoid real proxy connections
vi.mock('http-proxy-middleware', () => ({
  createProxyMiddleware: vi.fn(() => (_req: any, _res: any, next: any) => next()),
}));

const { app } = await import('../index.js');

describe('gateway health', () => {
  it('GET /health returns 200 with status ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.service).toBe('gateway');
  });

  it('GET /health includes uptime and timestamp', async () => {
    const res = await request(app).get('/health');
    expect(res.body).toHaveProperty('uptime');
    expect(res.body).toHaveProperty('timestamp');
  });

  it('GET /unknown-route returns 404', async () => {
    const res = await request(app).get('/unknown-route-xyz');
    expect(res.status).toBe(404);
  });
});

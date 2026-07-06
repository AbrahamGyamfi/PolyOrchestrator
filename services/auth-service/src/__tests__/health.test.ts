import { describe, it, expect, vi } from 'vitest';
import request from 'supertest';

// Mock database before importing app
vi.mock('../db/index.js', () => ({
  pool: { query: vi.fn(), end: vi.fn() },
}));

// Mock better-auth to avoid real DB connections
vi.mock('better-auth', () => ({
  betterAuth: vi.fn(() => ({
    handler: vi.fn((req: any, res: any) => res.status(200).json({ ok: true })),
    api: {},
  })),
}));

const { app } = await import('../index.js');

describe('auth-service health', () => {
  it('GET /health returns 200 with status ok', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.service).toBe('auth-service');
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

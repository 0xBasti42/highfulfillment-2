import 'dotenv/config';

function required(name: string): string {
  const value = process.env[name];
  if (!value || value.trim() === '') {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value.trim();
}

function int(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const n = Number.parseInt(raw, 10);
  if (!Number.isFinite(n) || n < 0) {
    throw new Error(`Invalid integer for ${name}: ${raw}`);
  }
  return n;
}

function csv(value: string): string[] {
  return value
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => s.length > 0);
}

const apiKey = required('RELAY_API_KEY');
if (apiKey.length < 32) {
  throw new Error('RELAY_API_KEY must be at least 32 characters.');
}

export const config = {
  host: process.env['HOST']?.trim() || '0.0.0.0',
  port: int('PORT', 3000),
  logLevel: process.env['LOG_LEVEL']?.trim() || 'info',
  apiKey,
  allowedHosts: csv(required('ALLOWED_HOSTS')),
  maxBodyBytes: int('MAX_BODY_BYTES', 1_048_576),
  upstreamTimeoutMs: int('UPSTREAM_TIMEOUT_MS', 15_000),
  maxRedirects: int('MAX_REDIRECTS', 0),
  rateLimitMax: int('RATE_LIMIT_MAX', 120),
  rateLimitWindowMs: int('RATE_LIMIT_WINDOW_MS', 60_000),
  version: process.env['RELAY_VERSION']?.trim() || 'dev',
} as const;

export type Config = typeof config;

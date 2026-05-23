import { request as undiciRequest } from 'undici';
import { config } from './config.js';

const ALLOWED_METHODS = new Set([
  'GET',
  'HEAD',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'OPTIONS',
]);

const HOP_BY_HOP = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  'host',
  'content-length',
]);

const FORBIDDEN_INBOUND_HEADERS = new Set(['authorization', 'cookie', 'host']);

const TEXTUAL_CONTENT_TYPES = [
  /^text\//i,
  /^application\/json/i,
  /^application\/[a-z0-9.+-]*\+json/i,
  /^application\/xml/i,
  /^application\/[a-z0-9.+-]*\+xml/i,
  /^application\/x-www-form-urlencoded/i,
];

export interface RelayRequest {
  url: URL;
  method: string;
  headers: Record<string, string>;
  body: string | null;
}

export interface RelayResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
  bodyEncoding: 'utf8' | 'base64';
}

export type RelayInputResult =
  | { ok: true; request: Omit<RelayRequest, 'url'> }
  | { ok: false; reason: string };

export function buildRelayInput(payload: unknown): RelayInputResult {
  if (typeof payload !== 'object' || payload === null) {
    return { ok: false, reason: 'request body must be a JSON object' };
  }
  const obj = payload as Record<string, unknown>;

  const method = typeof obj['method'] === 'string' ? obj['method'].toUpperCase() : 'GET';
  if (!ALLOWED_METHODS.has(method)) {
    return { ok: false, reason: `method ${method} is not permitted` };
  }

  const headersResult = sanitizeHeaders(obj['headers']);
  if (!headersResult.ok) return headersResult;

  const bodyResult = normalizeBody(obj['body'], method);
  if (!bodyResult.ok) return bodyResult;

  return {
    ok: true,
    request: {
      method,
      headers: headersResult.headers,
      body: bodyResult.body,
    },
  };
}

function sanitizeHeaders(
  raw: unknown,
):
  | { ok: true; headers: Record<string, string> }
  | { ok: false; reason: string } {
  if (raw === undefined || raw === null) return { ok: true, headers: {} };
  if (typeof raw !== 'object') {
    return { ok: false, reason: 'headers must be an object' };
  }

  const out: Record<string, string> = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    const lower = key.toLowerCase();
    if (FORBIDDEN_INBOUND_HEADERS.has(lower)) continue;
    if (HOP_BY_HOP.has(lower)) continue;
    if (typeof value !== 'string') {
      return { ok: false, reason: `header ${key} must be a string` };
    }
    if (/[\r\n]/.test(value)) {
      return { ok: false, reason: `header ${key} contains illegal characters` };
    }
    out[lower] = value;
  }
  return { ok: true, headers: out };
}

function normalizeBody(
  raw: unknown,
  method: string,
): { ok: true; body: string | null } | { ok: false; reason: string } {
  if (raw === undefined || raw === null) return { ok: true, body: null };
  if (method === 'GET' || method === 'HEAD') {
    return { ok: false, reason: `body is not permitted for ${method} requests` };
  }
  if (typeof raw === 'string') return { ok: true, body: raw };
  try {
    return { ok: true, body: JSON.stringify(raw) };
  } catch {
    return { ok: false, reason: 'body could not be serialized to JSON' };
  }
}

export async function forward(input: RelayRequest): Promise<RelayResponse> {
  const headers = { ...input.headers };
  if (input.body !== null && headers['content-type'] === undefined) {
    headers['content-type'] = 'application/json';
  }

  const requestOptions: Parameters<typeof undiciRequest>[1] = {
    method: input.method as never,
    headers,
    bodyTimeout: config.upstreamTimeoutMs,
    headersTimeout: config.upstreamTimeoutMs,
    maxRedirections: config.maxRedirects,
  };
  if (input.body !== null) {
    requestOptions.body = input.body;
  }

  const response = await undiciRequest(input.url, requestOptions);

  const buffer = await readBoundedBody(response.body, config.maxBodyBytes);

  const responseHeaders: Record<string, string> = {};
  for (const [key, value] of Object.entries(response.headers)) {
    if (HOP_BY_HOP.has(key.toLowerCase())) continue;
    if (Array.isArray(value)) {
      responseHeaders[key] = value.join(', ');
    } else if (typeof value === 'string') {
      responseHeaders[key] = value;
    }
  }

  const contentType = responseHeaders['content-type'] ?? '';
  const isText = TEXTUAL_CONTENT_TYPES.some((re) => re.test(contentType));
  const bodyEncoding: 'utf8' | 'base64' = isText ? 'utf8' : 'base64';
  const body = isText ? buffer.toString('utf8') : buffer.toString('base64');

  return {
    status: response.statusCode,
    headers: responseHeaders,
    body,
    bodyEncoding,
  };
}

async function readBoundedBody(
  stream: AsyncIterable<Buffer | Uint8Array>,
  maxBytes: number,
): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of stream) {
    const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += buf.length;
    if (total > maxBytes) {
      throw new UpstreamBodyTooLargeError(
        `upstream response exceeded ${maxBytes} bytes`,
      );
    }
    chunks.push(buf);
  }
  return Buffer.concat(chunks, total);
}

export class UpstreamBodyTooLargeError extends Error {
  override readonly name = 'UpstreamBodyTooLargeError';
}

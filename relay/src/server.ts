import Fastify, { type FastifyError } from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { config } from './config.js';
import { loggerOptions } from './logger.js';
import { requireApiKey } from './auth.js';
import { validateUpstreamUrl } from './allowlist.js';
import {
  buildRelayInput,
  forward,
  UpstreamBodyTooLargeError,
} from './proxy.js';

async function buildApp() {
  const app = Fastify({
    logger: loggerOptions,
    bodyLimit: config.maxBodyBytes,
    disableRequestLogging: false,
    trustProxy: true,
  });

  await app.register(rateLimit, {
    max: config.rateLimitMax,
    timeWindow: config.rateLimitWindowMs,
    keyGenerator: (req) => {
      const auth = req.headers['authorization'];
      if (typeof auth === 'string') return `auth:${auth}`;
      return req.ip;
    },
  });

  app.get('/v1/health', async () => ({
    ok: true,
    version: config.version,
  }));

  app.post('/v1/relay', async (req, reply) => {
    await requireApiKey(req, reply);
    if (reply.sent) return reply;

    const validatedUrl = await validateUpstreamUrl(
      (req.body as { url?: unknown } | null)?.url,
    );
    if (!validatedUrl.ok) {
      return reply.code(400).send({ error: validatedUrl.reason });
    }

    const input = buildRelayInput(req.body);
    if (!input.ok) {
      return reply.code(400).send({ error: input.reason });
    }

    try {
      const response = await forward({
        url: validatedUrl.url,
        ...input.request,
      });
      return reply.code(200).send(response);
    } catch (error: unknown) {
      if (error instanceof UpstreamBodyTooLargeError) {
        return reply.code(502).send({ error: 'upstream response too large' });
      }
      const code =
        typeof error === 'object' && error !== null && 'code' in error
          ? (error as { code?: unknown }).code
          : undefined;
      if (
        code === 'UND_ERR_HEADERS_TIMEOUT' ||
        code === 'UND_ERR_BODY_TIMEOUT' ||
        code === 'UND_ERR_CONNECT_TIMEOUT'
      ) {
        return reply.code(504).send({ error: 'upstream timeout' });
      }
      req.log.error({ err: error }, 'upstream request failed');
      return reply.code(502).send({ error: 'upstream request failed' });
    }
  });

  app.setNotFoundHandler((_req, reply) => {
    reply.code(404).send({ error: 'not found' });
  });

  app.setErrorHandler((error: FastifyError, req, reply) => {
    if (error.statusCode === 413) {
      return reply.code(413).send({ error: 'request body too large' });
    }
    if (error.statusCode === 429) {
      return reply.code(429).send({ error: 'rate limit exceeded' });
    }
    req.log.error({ err: error }, 'unhandled error');
    reply.code(500).send({ error: 'internal error' });
  });

  return app;
}

async function main() {
  const app = await buildApp();
  try {
    await app.listen({ host: config.host, port: config.port });
  } catch (err) {
    app.log.fatal({ err }, 'failed to start server');
    process.exit(1);
  }

  for (const signal of ['SIGINT', 'SIGTERM'] as const) {
    process.on(signal, async () => {
      app.log.info({ signal }, 'shutting down');
      await app.close();
      process.exit(0);
    });
  }
}

void main();

import crypto from 'node:crypto';
import type { FastifyRequest, FastifyReply } from 'fastify';
import { config } from './config.js';

const expectedKey = Buffer.from(config.apiKey, 'utf8');

export async function requireApiKey(
  req: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
  const presented = extractBearer(req.headers['authorization']);
  if (presented === null) {
    await reply.code(401).send({ error: 'missing or malformed Authorization header' });
    return;
  }

  const presentedBuf = Buffer.from(presented, 'utf8');
  if (
    presentedBuf.length !== expectedKey.length ||
    !crypto.timingSafeEqual(presentedBuf, expectedKey)
  ) {
    await reply.code(401).send({ error: 'invalid API key' });
    return;
  }
}

function extractBearer(header: string | string[] | undefined): string | null {
  if (typeof header !== 'string') return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  if (!match || !match[1]) return null;
  const token = match[1].trim();
  return token.length > 0 ? token : null;
}

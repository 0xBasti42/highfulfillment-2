import dns from 'node:dns/promises';
import type { LookupAddress } from 'node:dns';
import net from 'node:net';
import { config } from './config.js';

export type ValidationResult =
  | { ok: true; url: URL }
  | { ok: false; reason: string };

export async function validateUpstreamUrl(input: unknown): Promise<ValidationResult> {
  if (typeof input !== 'string' || input.length === 0) {
    return { ok: false, reason: 'url must be a non-empty string' };
  }

  let url: URL;
  try {
    url = new URL(input);
  } catch {
    return { ok: false, reason: 'url is not a valid URL' };
  }

  if (url.protocol !== 'https:') {
    return { ok: false, reason: 'only https URLs are permitted' };
  }

  if (url.username !== '' || url.password !== '') {
    return { ok: false, reason: 'URLs must not contain credentials' };
  }

  const hostname = url.hostname.toLowerCase();
  if (!isHostAllowed(hostname)) {
    return { ok: false, reason: 'host is not on the allowlist' };
  }

  const ipCheck = await resolvesToPublicAddress(hostname);
  if (!ipCheck.ok) return ipCheck;

  return { ok: true, url };
}

function isHostAllowed(hostname: string): boolean {
  for (const entry of config.allowedHosts) {
    if (entry.startsWith('.')) {
      const suffix = entry.slice(1);
      if (hostname === suffix || hostname.endsWith(`.${suffix}`)) return true;
    } else if (hostname === entry) {
      return true;
    }
  }
  return false;
}

async function resolvesToPublicAddress(
  hostname: string,
): Promise<ValidationResult> {
  if (net.isIP(hostname) !== 0) {
    return isPrivateAddress(hostname)
      ? { ok: false, reason: 'host resolves to a private address' }
      : { ok: true, url: new URL(`https://${hostname}`) };
  }

  let addresses: LookupAddress[];
  try {
    addresses = await dns.lookup(hostname, { all: true, verbatim: true });
  } catch {
    return { ok: false, reason: 'host could not be resolved' };
  }

  if (addresses.length === 0) {
    return { ok: false, reason: 'host has no DNS records' };
  }

  for (const { address } of addresses) {
    if (isPrivateAddress(address)) {
      return { ok: false, reason: 'host resolves to a private address' };
    }
  }

  return { ok: true, url: new URL(`https://${hostname}`) };
}

export function isPrivateAddress(ip: string): boolean {
  const family = net.isIP(ip);
  if (family === 4) return isPrivateIPv4(ip);
  if (family === 6) return isPrivateIPv6(ip.toLowerCase());
  return true;
}

function isPrivateIPv4(ip: string): boolean {
  const parts = ip.split('.').map((p) => Number.parseInt(p, 10));
  if (parts.length !== 4 || parts.some((n) => !Number.isFinite(n))) return true;
  const [a, b] = parts as [number, number, number, number];

  if (a === 10) return true;
  if (a === 127) return true;
  if (a === 0) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 192 && b === 0) return true;
  if (a === 198 && (b === 18 || b === 19)) return true;
  if (a === 100 && b >= 64 && b <= 127) return true;
  if (a >= 224) return true;
  return false;
}

function isPrivateIPv6(ip: string): boolean {
  if (ip === '::' || ip === '::1') return true;
  if (ip.startsWith('fc') || ip.startsWith('fd')) return true;
  if (ip.startsWith('fe80')) return true;
  if (ip.startsWith('ff')) return true;

  if (ip.startsWith('::ffff:')) {
    const tail = ip.slice('::ffff:'.length);
    if (net.isIP(tail) === 4) return isPrivateIPv4(tail);
  }
  if (ip.startsWith('64:ff9b::')) {
    const tail = ip.slice('64:ff9b::'.length);
    if (net.isIP(tail) === 4) return isPrivateIPv4(tail);
  }
  return false;
}

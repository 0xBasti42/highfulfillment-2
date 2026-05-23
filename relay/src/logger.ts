import { config } from './config.js';

export const loggerOptions = {
  level: config.logLevel,
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      'req.headers["x-api-key"]',
      'res.headers["set-cookie"]',
    ] as string[],
    censor: '[redacted]',
  },
};

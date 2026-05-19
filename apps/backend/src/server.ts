import Fastify from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { loadConfig } from './config.js';
import { registerActivationRoutes } from './routes/activation.js';
import { registerWebhookRoutes } from './routes/webhooks.js';

async function build() {
  const config = loadConfig();

  const app = Fastify({
    logger: {
      level: config.LOG_LEVEL,
      transport: config.NODE_ENV === 'development'
        ? { target: 'pino-pretty', options: { translateTime: 'SYS:HH:MM:ss.l' } }
        : undefined,
    },
    trustProxy: true,
  });

  await app.register(cors, {
    origin: ['https://dikto.itbeaver.co', 'http://localhost:8000'],
    methods: ['GET', 'POST'],
  });

  await app.register(rateLimit, {
    global: false,
  });

  app.get('/healthz', async () => ({ status: 'ok', uptime: process.uptime() }));

  await registerActivationRoutes(app);
  await registerWebhookRoutes(app);

  return { app, config };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { app, config } = await build();
  try {
    await app.listen({ port: config.PORT, host: '0.0.0.0' });
  } catch (err) {
    app.log.fatal(err, 'server failed to start');
    process.exit(1);
  }
}

export { build };

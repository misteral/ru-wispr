import type { FastifyInstance } from 'fastify';
import crypto from 'node:crypto';

/**
 * Веб-хуки PSP. Реализация в Sprint 1; здесь — каркас с проверкой подписи
 * и идемпотентностью на уровне приёма (далее идёт в очередь / БД).
 */
export async function registerWebhookRoutes(app: FastifyInstance) {
  app.post('/webhooks/lava', async (req, reply) => {
    const secret = process.env.LAVA_WEBHOOK_SECRET;
    if (!secret) {
      req.log.error('LAVA_WEBHOOK_SECRET not configured');
      return reply.code(500).send({ error: 'config' });
    }

    const signature = req.headers['x-api-signature'];
    if (typeof signature !== 'string') {
      return reply.code(401).send({ error: 'missing_signature' });
    }

    const rawBody = JSON.stringify(req.body);
    const expected = crypto.createHmac('sha256', secret).update(rawBody).digest('hex');
    if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected))) {
      req.log.warn('Lava webhook: signature mismatch');
      return reply.code(401).send({ error: 'invalid_signature' });
    }

    // TODO Sprint 1:
    //   1) INSERT INTO webhook_events (raw_headers, raw_body, ...)
    //   2) ON CONFLICT (provider, provider_event_id) DO NOTHING
    //   3) Enqueue async job: issue license + send email + telegram
    req.log.info({ event: req.body }, 'Lava webhook received (stub)');
    return reply.code(202).send({ accepted: true });
  });

  app.post('/webhooks/yookassa', async (req, reply) => {
    // TODO Sprint 3: backup PSP — IP whitelist + Idempotence-Key dedup
    req.log.info({ event: req.body }, 'ЮKassa webhook received (stub)');
    return reply.code(501).send({ error: 'not_implemented' });
  });
}

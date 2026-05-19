import type { FastifyInstance } from 'fastify';
import { z } from 'zod';

const ActivateBody = z.object({
  licenseKey: z.string().min(1),
  fingerprint: z.string().regex(/^[a-f0-9]{64}$/),
  deviceId: z.string().uuid(),
  appVersion: z.string(),
  os: z.string(),
});

const ValidateQuery = z.object({
  deviceId: z.string().uuid(),
});

/**
 * Эндпоинты активации лицензии. Stubs возвращают фиктивные ответы —
 * полноценная реализация делается в Sprint 1 (см. docs/product-specs/backend-prd.md).
 */
export async function registerActivationRoutes(app: FastifyInstance) {
  app.post('/v1/activate', {
    config: {
      rateLimit: { max: 5, timeWindow: '1 minute' },
    },
  }, async (req, reply) => {
    const parsed = ActivateBody.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation', issues: parsed.error.flatten() });
    }

    // TODO Sprint 1:
    //   1) SELECT licenses WHERE license_key = ? AND refunded_at IS NULL AND revoked_at IS NULL
    //   2) Check device_limit vs COUNT(DISTINCT fingerprint) for this license
    //   3) UPSERT activations(license_key, fingerprint, device_id, token_hash, ...)
    //   4) Return { token, plan, expiresAt, deviceId }
    req.log.warn({ licenseKey: maskKey(parsed.data.licenseKey) }, 'activate: stub response');
    return reply.code(501).send({
      error: 'not_implemented',
      message: 'Activation endpoint stub — реализуем в Sprint 1 backend',
    });
  });

  app.get('/v1/validate', async (req, reply) => {
    const auth = req.headers.authorization;
    if (!auth?.startsWith('Bearer ')) {
      return reply.code(401).send({ valid: false, reason: 'missing_token' });
    }
    const parsed = ValidateQuery.safeParse(req.query);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'validation', issues: parsed.error.flatten() });
    }

    // TODO Sprint 1:
    //   1) SELECT activations WHERE token_hash = ? AND token_expires_at > NOW()
    //   2) Check license refunded_at / revoked_at / expires_at
    //   3) UPDATE last_validated_at = NOW()
    //   4) Return { valid, expiresAt, reason }
    req.log.warn('validate: stub response');
    return reply.code(501).send({
      error: 'not_implemented',
      message: 'Validate endpoint stub — реализуем в Sprint 1 backend',
    });
  });
}

function maskKey(key: string): string {
  if (key.length < 9) return '****';
  return `${key.slice(0, 4)}-****-****-${key.slice(-4)}`;
}

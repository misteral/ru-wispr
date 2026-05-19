import { pgTable, bigserial, text, integer, timestamp, jsonb, uniqueIndex } from 'drizzle-orm/pg-core';

// Полная схема — см. docs/SERVER_API.md → "Схема БД".
// Здесь — минимальный набор для Sprint 1.

export const licenses = pgTable('licenses', {
  licenseKey: text('license_key').primaryKey(),
  email: text('email').notNull(),
  plan: text('plan').notNull(),
  deviceLimit: integer('device_limit').notNull().default(2),
  expiresAt: timestamp('expires_at', { withTimezone: true }),
  refundedAt: timestamp('refunded_at', { withTimezone: true }),
  revokedAt: timestamp('revoked_at', { withTimezone: true }),
  paymentId: text('payment_id'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

export const activations = pgTable('activations', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  licenseKey: text('license_key').notNull().references(() => licenses.licenseKey),
  fingerprint: text('fingerprint').notNull(),
  deviceId: text('device_id').notNull(),
  tokenHash: text('token_hash').notNull().unique(),
  tokenExpiresAt: timestamp('token_expires_at', { withTimezone: true }).notNull(),
  lastValidatedAt: timestamp('last_validated_at', { withTimezone: true }).notNull().defaultNow(),
  appVersion: text('app_version'),
  os: text('os'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => ({
  fingerprintIdx: uniqueIndex('uniq_license_fingerprint').on(table.licenseKey, table.fingerprint),
}));

export const payments = pgTable('payments', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  provider: text('provider').notNull(),
  providerPaymentId: text('provider_payment_id').notNull(),
  licenseKey: text('license_key').references(() => licenses.licenseKey),
  amountKopecks: integer('amount_kopecks').notNull(),
  currency: text('currency').notNull().default('RUB'),
  status: text('status').notNull(),
  email: text('email').notNull(),
  receiptUuid: text('receipt_uuid'),
  receiptUrl: text('receipt_url'),
  receiptStatus: text('receipt_status').notNull().default('pending'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => ({
  providerIdx: uniqueIndex('uniq_provider_payment').on(table.provider, table.providerPaymentId),
}));

export const webhookEvents = pgTable('webhook_events', {
  id: bigserial('id', { mode: 'bigint' }).primaryKey(),
  provider: text('provider').notNull(),
  providerEventId: text('provider_event_id'),
  rawHeaders: jsonb('raw_headers').notNull(),
  rawBody: jsonb('raw_body').notNull(),
  processedAt: timestamp('processed_at', { withTimezone: true }),
  status: text('status').notNull().default('received'),
  errorMessage: text('error_message'),
  receivedAt: timestamp('received_at', { withTimezone: true }).notNull().defaultNow(),
});

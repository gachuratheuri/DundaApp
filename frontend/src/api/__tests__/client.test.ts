import { api, ApiError, newIdempotencyKey } from '../client';

function jsonResponse(status: number, body: unknown): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as unknown as Response;
}

describe('newIdempotencyKey', () => {
  it('returns a non-empty string', () => {
    const key = newIdempotencyKey();
    expect(typeof key).toBe('string');
    expect(key.length).toBeGreaterThan(0);
  });

  it('never returns the same value twice across many calls', () => {
    const keys = new Set(Array.from({ length: 200 }, () => newIdempotencyKey()));
    expect(keys.size).toBe(200);
  });

  it('prefers crypto.randomUUID when available', () => {
    const original = globalThis.crypto;
    const randomUUID = jest.fn(() => 'fixed-uuid-value');
    // @ts-expect-error partial mock is sufficient for this code path
    globalThis.crypto = { randomUUID };

    try {
      expect(newIdempotencyKey()).toBe('fixed-uuid-value');
      expect(randomUUID).toHaveBeenCalled();
    } finally {
      globalThis.crypto = original;
    }
  });
});

describe('ApiError', () => {
  it('defaults retriable to true for network-shaped errors (no status)', () => {
    const err = new ApiError('boom');
    expect(err.retriable).toBe(true);
  });

  it('defaults retriable to true for 5xx', () => {
    const err = new ApiError('boom', { status: 503 });
    expect(err.retriable).toBe(true);
  });

  it('defaults retriable to false for 4xx', () => {
    const err = new ApiError('boom', { status: 422 });
    expect(err.retriable).toBe(false);
  });

  it('respects an explicit retriable override', () => {
    const err = new ApiError('boom', { status: 422, retriable: true });
    expect(err.retriable).toBe(true);
  });
});

describe('ApiClient.createCheckout', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  it('sends only quote_id and phone in the body — never amount, price, or user_id (Phase 10 client-authority hardening)', async () => {
    const fetchMock = jest.fn().mockResolvedValue(
      jsonResponse(200, {
        data: { payment_intent_id: 'pi_123', state: 'inventory_reserved', amount_cents: 1000, currency: 'KES' },
      }),
    );
    global.fetch = fetchMock as unknown as typeof fetch;

    await api.createCheckout({ quoteId: 'quote_1', phone: '254712345678', idempotencyKey: 'idem_1' });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(String(url)).toContain('/checkout');

    const sentBody = JSON.parse(init.body as string);
    expect(sentBody).toEqual({ quote_id: 'quote_1', phone: '254712345678' });
    expect(sentBody.amount).toBeUndefined();
    expect(sentBody.amount_cents).toBeUndefined();
    expect(sentBody.user_id).toBeUndefined();
    expect(sentBody.price).toBeUndefined();
  });

  it('propagates the Idempotency-Key header', async () => {
    const fetchMock = jest.fn().mockResolvedValue(
      jsonResponse(200, { data: { payment_intent_id: 'pi_1', state: 'inventory_reserved', amount_cents: 1000, currency: 'KES' } }),
    );
    global.fetch = fetchMock as unknown as typeof fetch;

    await api.createCheckout({ quoteId: 'quote_1', phone: '254712345678', idempotencyKey: 'idem_specific_value' });

    const [, init] = fetchMock.mock.calls[0];
    const headers = init.headers as Headers;
    expect(headers.get('Idempotency-Key')).toBe('idem_specific_value');
  });

  it('throws a non-retriable ApiError with the server-provided code on 4xx', async () => {
    const fetchMock = jest.fn().mockResolvedValue(
      jsonResponse(422, { error: { code: 'quote_tampered', message: 'Quote has been tampered with' } }),
    );
    global.fetch = fetchMock as unknown as typeof fetch;

    await expect(api.createCheckout({ quoteId: 'quote_1', phone: '254712345678', idempotencyKey: 'idem_1' })).rejects.toMatchObject({
      code: 'quote_tampered',
      status: 422,
      retriable: false,
    });
  });

  it('throws when the server response is missing required fields, rather than returning a malformed object', async () => {
    const fetchMock = jest.fn().mockResolvedValue(jsonResponse(200, { data: { amount_cents: 1000 } }));
    global.fetch = fetchMock as unknown as typeof fetch;

    await expect(api.createCheckout({ quoteId: 'quote_1', phone: '254712345678', idempotencyKey: 'idem_1' })).rejects.toThrow(ApiError);
  });
});

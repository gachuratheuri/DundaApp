import AsyncStorage from '@react-native-async-storage/async-storage';
import { secureGet, secureSet, secureDelete } from './secureStorage';
import { API_BASE_URL } from '@/constants/config';

const ACCESS_TOKEN_KEY = 'dunda_access_token';
const REFRESH_TOKEN_KEY = 'dunda_refresh_token';
const USER_KEY = '@dunda_user';
const DEFAULT_TIMEOUT_MS = 20_000;

export class ApiError extends Error {
  readonly status?: number;
  readonly code?: string;
  readonly retriable: boolean;

  constructor(message: string, options: { status?: number; code?: string; retriable?: boolean } = {}) {
    super(message);
    this.name = 'ApiError';
    this.status = options.status;
    this.code = options.code;
    this.retriable = options.retriable ?? (!options.status || options.status >= 500);
  }
}

type RequestOptions = RequestInit & {
  timeoutMs?: number;
  skipRefresh?: boolean;
};

function isRecord(value: unknown): value is Record<string, any> {
  return typeof value === 'object' && value !== null;
}

function errorDetails(payload: unknown, status: number): { message: string; code?: string } {
  if (isRecord(payload)) {
    const error = payload.error;
    if (typeof error === 'string') return { message: error };
    if (isRecord(error)) {
      return {
        message: typeof error.message === 'string' ? error.message : typeof error.code === 'string' ? error.code : `API error (${status})`,
        code: typeof error.code === 'string' ? error.code : undefined,
      };
    }
    if (typeof payload.message === 'string') return { message: payload.message };
  }
  return { message: `API error (${status})` };
}

function requireRecord(value: unknown, label: string): Record<string, any> {
  if (!isRecord(value)) throw new ApiError(`Invalid ${label} response`, { retriable: false });
  return value;
}

class ApiClient {
  private refreshPromise: Promise<boolean> | null = null;
  private sessionListeners = new Set<() => void>();

  async getToken(): Promise<string | null> {
    return secureGet(ACCESS_TOKEN_KEY);
  }

  /** Compatibility helper for callers that only receive an access token. */
  async setToken(token: string): Promise<void> {
    await secureSet(ACCESS_TOKEN_KEY, token);
  }

  async setSession(accessToken: string, refreshToken?: string | null): Promise<void> {
    await secureSet(ACCESS_TOKEN_KEY, accessToken);
    if (refreshToken) await secureSet(REFRESH_TOKEN_KEY, refreshToken);
  }

  async removeToken(): Promise<void> {
    await Promise.all([secureDelete(ACCESS_TOKEN_KEY), secureDelete(REFRESH_TOKEN_KEY)]);
  }

  async logout(allDevices = false): Promise<void> {
    const refreshToken = await secureGet(REFRESH_TOKEN_KEY);
    try {
      await this.post(
        '/auth/logout',
        { refresh_token: refreshToken, all_devices: allDevices },
        {},
        { skipRefresh: true },
      );
    } finally {
      await this.removeToken();
    }
  }

  async getUser(): Promise<Record<string, any> | null> {
    const userJson = await AsyncStorage.getItem(USER_KEY);
    if (!userJson) return null;
    try {
      const user = JSON.parse(userJson);
      return isRecord(user) ? user : null;
    } catch {
      await AsyncStorage.removeItem(USER_KEY);
      return null;
    }
  }

  async setUser(user: Record<string, any>): Promise<void> {
    await AsyncStorage.setItem(USER_KEY, JSON.stringify(user));
  }

  async removeUser(): Promise<void> {
    await AsyncStorage.removeItem(USER_KEY);
  }

  onSessionExpired(listener: () => void): () => void {
    this.sessionListeners.add(listener);
    return () => this.sessionListeners.delete(listener);
  }

  private notifySessionExpired(): void {
    this.sessionListeners.forEach((listener) => listener());
  }

  private async refreshAccessToken(): Promise<boolean> {
    if (this.refreshPromise) return this.refreshPromise;

    this.refreshPromise = (async () => {
      const refreshToken = await secureGet(REFRESH_TOKEN_KEY);
      if (!refreshToken) return false;

      const timeout = this.timeout(DEFAULT_TIMEOUT_MS);
      try {
        const response = await fetch(`${API_BASE_URL}/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refresh_token: refreshToken }),
          signal: timeout.signal,
        });
        const payload: unknown = await response.json().catch(() => ({}));
        if (!response.ok) return false;
        const body = requireRecord(payload, 'refresh');
        const accessToken = body.access_token ?? body.token;
        const rotatedRefreshToken = body.refresh_token;
        if (typeof accessToken !== 'string' || accessToken.length < 16) return false;
        await this.setSession(accessToken, typeof rotatedRefreshToken === 'string' ? rotatedRefreshToken : refreshToken);
        return true;
      } catch {
        return false;
      } finally {
        timeout.cancel();
      }
    })().finally(() => {
      this.refreshPromise = null;
    });

    return this.refreshPromise;
  }

  private timeout(timeoutMs: number): { signal: AbortSignal; cancel: () => void } {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    return { signal: controller.signal, cancel: () => clearTimeout(timer) };
  }

  async request(endpoint: string, options: RequestOptions = {}): Promise<any> {
    const path = endpoint.startsWith('/') ? endpoint : `/${endpoint}`;
    const url = `${API_BASE_URL}${path}`;
    const token = await this.getToken();
    const headers = new Headers(options.headers || {});
    if (options.body !== undefined && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');
    headers.set('Accept', 'application/json');
    if (token) headers.set('Authorization', `Bearer ${token}`);

    const { timeoutMs = DEFAULT_TIMEOUT_MS, skipRefresh, ...fetchOptions } = options;
    const timeout = this.timeout(timeoutMs);
    let response: Response;
    try {
      response = await fetch(url, { ...fetchOptions, headers, signal: timeout.signal });
    } catch (error) {
      if (typeof error === 'object' && error !== null && (error as { name?: string }).name === 'AbortError') {
        throw new ApiError('The request timed out. Check your connection and try again.', { retriable: true });
      }
      throw new ApiError('Unable to reach the service. Check your connection and try again.', { retriable: true });
    } finally {
      timeout.cancel();
    }

    const payload: unknown = await response.json().catch(() => ({}));

    if (response.status === 401 && !skipRefresh) {
      const refreshed = await this.refreshAccessToken();
      if (refreshed) return this.request(endpoint, { ...options, skipRefresh: true });
      await this.removeToken();
      this.notifySessionExpired();
      throw new ApiError('Your session has expired. Please sign in again.', { status: 401, code: 'session_expired', retriable: false });
    }

    if (!response.ok) {
      const details = errorDetails(payload, response.status);
      throw new ApiError(details.message, { status: response.status, code: details.code });
    }

    return payload;
  }

  get(endpoint: string, options: RequestOptions = {}) {
    return this.request(endpoint, { ...options, method: 'GET' });
  }

  post(endpoint: string, body: unknown, extraHeaders: Record<string, string> = {}, options: RequestOptions = {}) {
    return this.request(endpoint, {
      ...options,
      method: 'POST',
      headers: { ...extraHeaders, ...(options.headers as Record<string, string> | undefined) },
      body: JSON.stringify(body),
    });
  }

  async createQuote(input: { eventId: string; tierId?: string; quantity: number }) {
    const payload = requireRecord(await this.post('/quotes', {
      event_id: input.eventId,
      ...(input.tierId ? { tier_id: input.tierId } : {}),
      quantity: input.quantity,
    }), 'quote');
    const data = requireRecord(payload.data, 'quote');
    if (typeof data.quote_id !== 'string' || typeof data.expires_at !== 'string') throw new ApiError('The server returned an incomplete quote.', { retriable: false });
    return data as { quote_id: string; signature: string; quantity: number; unit_price_cents: number; total_cents: number; currency: string; expires_at: string };
  }

  async createCheckout(input: { quoteId: string; phone: string; idempotencyKey: string }) {
    const payload = requireRecord(await this.post('/checkout', {
      quote_id: input.quoteId,
      phone: input.phone,
    }, { 'Idempotency-Key': input.idempotencyKey }), 'checkout');
    const data = requireRecord(payload.data, 'checkout');
    if (typeof data.payment_intent_id !== 'string' || typeof data.state !== 'string') throw new ApiError('The server returned an incomplete payment intent.', { retriable: false });
    return data as { payment_intent_id: string; state: string; amount_cents: number; currency: string; redirect_url?: string | null };
  }

  async checkoutStatus(paymentIntentId: string) {
    const payload = requireRecord(await this.get(`/checkout/${encodeURIComponent(paymentIntentId)}/status`), 'checkout status');
    const data = requireRecord(payload.data, 'checkout status');
    if (typeof data.state !== 'string') throw new ApiError('The server returned an invalid payment state.', { retriable: false });
    return data as { payment_intent_id: string; state: string; amount_cents: number; currency: string; provider_checkout_id?: string | null };
  }
}

let idempotencyCounter = 0;
export function newIdempotencyKey(): string {
  const cryptoApi = (globalThis as any).crypto;
  if (cryptoApi?.randomUUID) return cryptoApi.randomUUID();
  if (cryptoApi?.getRandomValues) {
    const bytes = new Uint8Array(18);
    cryptoApi.getRandomValues(bytes);
    return Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  }
  idempotencyCounter += 1;
  return `client-${Date.now().toString(36)}-${idempotencyCounter.toString(36)}`;
}

export const api = new ApiClient();
export const fetchEvents = async () => {
  const payload = requireRecord(await api.get('/events'), 'events');
  return Array.isArray(payload.data) ? payload.data : [];
};
export const fetchTickets = async () => {
  const payload = requireRecord(await api.get('/tickets'), 'tickets');
  return Array.isArray(payload.data) ? payload.data : [];
};

// src/constants/config.ts
// Centralised runtime configuration for network endpoints.
//
// Production builds MUST NOT ship hardcoded emulator/localhost hosts. The API
// origin is resolved in this order:
//   1. `EXPO_PUBLIC_API_URL`         — inlined at build time (set per EAS profile
//                                       in eas.json `env`, or via a local .env).
//   2. `expoConfig.extra.apiUrl`     — baked into app.json for a given build.
//   3. Dev fallback                  — only used in `__DEV__`; Android emulators
//                                       map the host loopback to 10.0.2.2.
//
// Both the REST base URL and the Phoenix WebSocket URL are derived from a single
// origin so they can never drift out of sync.

import Constants from 'expo-constants';
import { Platform } from 'react-native';

type Extra = { apiUrl?: string };

const extra = (Constants.expoConfig?.extra ?? {}) as Extra;

const devOrigin = Platform.OS === 'android' ? 'http://10.0.2.2:4000' : 'http://localhost:4000';

function resolveOrigin(): string {
  const fromEnv = process.env.EXPO_PUBLIC_API_URL;
  const fromExtra = extra.apiUrl;
  const resolved = fromEnv || fromExtra || (__DEV__ ? devOrigin : undefined);

  if (!resolved) {
    throw new Error(
      'API origin is not configured. Set EXPO_PUBLIC_API_URL (eas.json env) ' +
        'or expo.extra.apiUrl (app.json) for non-development builds.',
    );
  }

  const origin = resolved.replace(/\/+$/, '');

  let parsed: URL;
  try {
    parsed = new URL(origin);
  } catch {
    throw new Error(`Invalid API origin: ${origin}`);
  }

  if (!['http:', 'https:'].includes(parsed.protocol) || parsed.username || parsed.password || parsed.pathname !== '/' || parsed.search || parsed.hash) {
    throw new Error('API origin must be an absolute HTTP(S) origin without credentials or a path.');
  }

  if (!__DEV__ && parsed.protocol !== 'https:') {
    throw new Error('Production builds require an HTTPS API origin.');
  }

  return origin;
}

/** Scheme + host (+ port) with no trailing slash, e.g. `https://api.tiketa.ke`. */
export const API_ORIGIN = resolveOrigin();

/** REST base, e.g. `https://api.tiketa.ke/api`. */
export const API_BASE_URL = `${API_ORIGIN}/api`;

/** Phoenix socket URL, e.g. `wss://api.tiketa.ke/socket`. */
export const WS_URL = `${API_ORIGIN.replace(/^http/, 'ws')}/socket`;

/** Demo data is intentionally restricted to local development builds. */
export const DEMO_DATA_ENABLED = __DEV__ && process.env.EXPO_PUBLIC_ENABLE_DEMO_DATA !== 'false';

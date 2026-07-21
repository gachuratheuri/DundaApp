// src/api/secureStorage.ts
// Hardware-backed credential storage (QA §4 — expo-secure-store).
//
// The auth token is a bearer credential and must never sit in plaintext
// AsyncStorage. On native we use expo-secure-store (Keychain / Keystore). On
// Web has no hardware-backed equivalent. We therefore keep credentials only
// in memory and require re-authentication after a page reload; a bearer token
// must never be persisted in localStorage, IndexedDB, or AsyncStorage.

import * as SecureStore from 'expo-secure-store';
import { Platform } from 'react-native';

const isWeb = Platform.OS === 'web';
const webMemory = new Map<string, string>();

export async function secureGet(key: string): Promise<string | null> {
  if (isWeb) {
    return webMemory.get(key) ?? null;
  }
  return SecureStore.getItemAsync(key);
}

export async function secureSet(key: string, value: string): Promise<void> {
  if (isWeb) {
    webMemory.set(key, value);
    return;
  }
  await SecureStore.setItemAsync(key, value, {
    keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
  });
}

export async function secureDelete(key: string): Promise<void> {
  if (isWeb) {
    webMemory.delete(key);
    return;
  }
  await SecureStore.deleteItemAsync(key);
}

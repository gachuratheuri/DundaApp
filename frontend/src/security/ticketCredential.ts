import { encode as base64Encode, decode as base64Decode } from 'base-64';

/** Protocol-v2 ticket proof primitives shared by the wallet and scanner. */
export const TICKET_PROTOCOL_VERSION = 2;
export const TICKET_PROOF_PERIOD_SECONDS = 30;

export interface TicketProofInput {
  ticketId: string;
  eventId: string;
  timeStep: number;
  nonce: Uint8Array;
  credentialPublicKey: Uint8Array;
}

export interface DeviceSigner {
  publicKey(): Promise<Uint8Array>;
  sign(payload: Uint8Array): Promise<Uint8Array>;
}

export function canonicalProof(input: TicketProofInput): Uint8Array {
  const text = [
    'dunda-ticket-proof',
    'v=2',
    `ticket_id=${input.ticketId}`,
    `event_id=${input.eventId}`,
    `time_step=${input.timeStep}`,
    `nonce=${base64Url(input.nonce)}`,
    `credential_public_key=${base64Url(input.credentialPublicKey)}`,
  ].join('\n');
  return new TextEncoder().encode(text);
}

export function canonicalBinding(ticketId: string, userId: string, challenge: string): Uint8Array {
  return new TextEncoder().encode(['dunda-ticket-device-binding', 'v=2', `ticket_id=${ticketId}`, `user_id=${userId}`, `challenge=${base64Url(new TextEncoder().encode(challenge))}`].join('\n'));
}

export function canonicalScannerRequest(deviceId: string, eventId: string, admissionId: string, proofNonce: Uint8Array, requestNonce: Uint8Array): Uint8Array {
  return new TextEncoder().encode(['dunda-scanner-admission', 'v=2', `device_id=${deviceId}`, `event_id=${eventId}`, `admission_id=${admissionId}`, `proof_nonce=${base64Url(proofNonce)}`, `request_nonce=${base64Url(requestNonce)}`].join('\n'));
}

export function randomNonce(length = 16): Uint8Array {
  if (length < 16 || length > 64) throw new Error('nonce length must be 16–64 bytes');
  const bytes = new Uint8Array(length);
  const cryptoApi = globalThis.crypto;
  if (!cryptoApi?.getRandomValues) throw new Error('cryptographically secure random source unavailable');
  cryptoApi.getRandomValues(bytes);
  return bytes;
}

export async function createDynamicProof(input: Omit<TicketProofInput, 'credentialPublicKey'> & { credentialPublicKey: Uint8Array }, signer: DeviceSigner): Promise<string> {
  const signerKey = await signer.publicKey();
  if (!constantTimeEqual(signerKey, input.credentialPublicKey)) throw new Error('device key does not match ticket credential');
  const signature = await signer.sign(canonicalProof(input));
  return JSON.stringify({
    v: TICKET_PROTOCOL_VERSION,
    ticket_id: input.ticketId,
    event_id: input.eventId,
    time_step: input.timeStep,
    nonce: base64Url(input.nonce),
    credential_public_key: base64Url(input.credentialPublicKey),
    signature: base64Url(signature),
  });
}

export function base64Url(value: Uint8Array): string {
  let binary = '';
  value.forEach(byte => { binary += String.fromCharCode(byte); });
  return base64Encode(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export function fromBase64Url(value: string): Uint8Array {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (value.length % 4)) % 4);
  const binary = base64Decode(padded);
  return Uint8Array.from(binary, char => char.charCodeAt(0));
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let different = 0;
  for (let i = 0; i < a.length; i += 1) different |= a[i] ^ b[i];
  return different === 0;
}

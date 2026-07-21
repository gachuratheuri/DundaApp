import * as fs from 'fs';
import * as path from 'path';
import {
  base64Url,
  canonicalProof,
  fromBase64Url,
  randomNonce,
  TICKET_PROOF_PERIOD_SECONDS,
  TICKET_PROTOCOL_VERSION,
} from '../ticketCredential';

// Read at runtime (not a compile-time `import ... from '.json'`) so this
// stays outside TypeScript's project rootDir/include resolution — the
// vector file deliberately lives at the repo root (`docs/vectors/`), shared
// across the Elixir/TypeScript/Kotlin/Swift implementations, not inside any
// one package.
const vectorPath = path.resolve(__dirname, '../../../../docs/vectors/ticket_proof_v2.json');
const vector = JSON.parse(fs.readFileSync(vectorPath, 'utf8')) as {
  ticket_id: string;
  event_id: string;
  time_step: number;
  nonce: string;
  credential_public_key: string;
  signature: string;
  canonical: string;
};

describe('base64Url / fromBase64Url round-trip', () => {
  it('is a proper inverse pair for arbitrary byte sequences', () => {
    const original = new Uint8Array([0, 1, 2, 253, 254, 255, 16, 32, 64, 128]);
    expect(fromBase64Url(base64Url(original))).toEqual(original);
  });

  it('produces no padding characters and no unsafe URL characters', () => {
    const encoded = base64Url(new Uint8Array([255, 255, 255, 255, 255]));
    expect(encoded).not.toMatch(/[+/=]/);
  });
});

describe('canonicalProof — cross-language test vector (docs/vectors/ticket_proof_v2.json)', () => {
  it('matches the canonical byte string exactly, proving byte-for-byte agreement with the Elixir/Kotlin/Swift implementations', () => {
    const nonce = fromBase64Url(vector.nonce);
    const credentialPublicKey = fromBase64Url(vector.credential_public_key);

    const proofBytes = canonicalProof({
      ticketId: vector.ticket_id,
      eventId: vector.event_id,
      timeStep: vector.time_step,
      nonce,
      credentialPublicKey,
    });

    const proofText = new TextDecoder().decode(proofBytes);
    expect(proofText).toBe(vector.canonical);
  });

  it('re-encoding the vector nonce/key round-trips to the same base64url strings the vector specifies', () => {
    expect(base64Url(fromBase64Url(vector.nonce))).toBe(vector.nonce);
    expect(base64Url(fromBase64Url(vector.credential_public_key))).toBe(vector.credential_public_key);
  });
});

describe('randomNonce', () => {
  it('rejects lengths outside the 16-64 byte protocol bound', () => {
    expect(() => randomNonce(15)).toThrow();
    expect(() => randomNonce(65)).toThrow();
  });

  it('produces the requested length and is not trivially constant across calls', () => {
    const a = randomNonce(16);
    const b = randomNonce(16);
    expect(a.length).toBe(16);
    expect(b.length).toBe(16);
    expect(a).not.toEqual(b);
  });
});

describe('protocol constants', () => {
  it('matches the version and period the backend/scanner protocol declares', () => {
    expect(TICKET_PROTOCOL_VERSION).toBe(2);
    expect(TICKET_PROOF_PERIOD_SECONDS).toBe(30);
  });
});

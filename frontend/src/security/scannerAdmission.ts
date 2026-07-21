import { base64Url, canonicalScannerRequest, randomNonce, fromBase64Url, type DeviceSigner } from './ticketCredential';

export interface ScannerAdmissionEnvelope {
  ticket_id: string;
  event_id: string;
  admission_id: string;
  proof_nonce: string;
  proof_signature: string;
  request_nonce: string;
  request_signature: string;
  time_step: number;
  manifest_version: number;
}

/** Builds the signed coordinator envelope after local manifest verification. */
export async function buildScannerAdmission(proofPayload: string, deviceId: string, manifestVersion: number, signer: DeviceSigner): Promise<ScannerAdmissionEnvelope> {
  const proof = JSON.parse(proofPayload) as { ticket_id: string; event_id: string; time_step: number; nonce: string; signature: string };
  const admissionId = typeof crypto?.randomUUID === 'function' ? crypto.randomUUID() : base64Url(randomNonce(24));
  const requestNonce = randomNonce();
  const requestSignature = await signer.sign(canonicalScannerRequest(deviceId, proof.event_id, admissionId, fromBase64Url(proof.nonce), requestNonce));
  return { ticket_id: proof.ticket_id, event_id: proof.event_id, admission_id: admissionId, proof_nonce: proof.nonce, proof_signature: proof.signature, request_nonce: base64Url(requestNonce), request_signature: base64Url(requestSignature), time_step: proof.time_step, manifest_version: manifestVersion };
}

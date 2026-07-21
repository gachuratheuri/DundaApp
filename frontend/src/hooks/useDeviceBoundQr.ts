import { useEffect, useState } from 'react';
import { createDynamicProof, randomNonce, fromBase64Url, canonicalBinding, base64Url, type DeviceSigner } from '../security/ticketCredential';

export interface DeviceBoundTicket {
  id: string;
  event_id: string;
  jwt: string;
  credential_public_key?: string | null;
  credential_valid_until?: string | null;
  protocol_version?: number;
}

export async function bindTicketDevice(api: { post: (path: string, body: unknown) => Promise<any>; getUser?: () => Promise<any> }, ticketId: string, signer: DeviceSigner) {
  const user = api.getUser ? await api.getUser() : null;
  if (!user?.id) throw new Error('authenticated user is required for device binding');
  const challengeResponse = await api.post(`/tickets/${ticketId}/device-challenge`, {});
  const challenge = challengeResponse?.data?.challenge;
  const token = challengeResponse?.data?.token;
  if (typeof challenge !== 'string' || typeof token !== 'string') throw new Error('device challenge unavailable');
  const publicKey = await signer.publicKey();
  const signature = await signer.sign(canonicalBinding(ticketId, String(user.id), challenge));
  return api.post(`/tickets/${ticketId}/bind-device`, { token, public_key: base64Url(publicKey), signature: base64Url(signature) });
}

export function useDeviceBoundQr(ticket: DeviceBoundTicket | null) {
  const [qrPayload, setQrPayload] = useState<string | null>(null);
  const [secondsRemaining, setSecondsRemaining] = useState(0);
  const [reason, setReason] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const signer = (globalThis as typeof globalThis & { __DUNDA_DEVICE_SIGNER__?: DeviceSigner }).__DUNDA_DEVICE_SIGNER__;
    const credentialPublicKey = ticket?.credential_public_key;
    if (!ticket || ticket.protocol_version !== 2 || !credentialPublicKey || !ticket.jwt || !signer) {
      setQrPayload(null);
      setReason(!ticket ? null : !signer ? 'Secure device key is unavailable' : !ticket.jwt ? 'Credential entitlement is unavailable' : 'Bind this ticket to this device before admission');
      return;
    }

    const tick = async () => {
      const now = Math.floor(Date.now() / 1000);
      const timeStep = Math.floor(now / 30);
      setSecondsRemaining(30 - (now % 30));
      try {
        const payload = await createDynamicProof({ ticketId: ticket.id, eventId: ticket.event_id, timeStep, nonce: randomNonce(), credentialPublicKey: fromBase64Url(credentialPublicKey) }, signer);
        if (!cancelled) { setQrPayload(`${ticket.jwt}.${payload}`); setReason(null); }
      } catch (error) {
        if (!cancelled) { setQrPayload(null); setReason(error instanceof Error ? error.message : 'Unable to create secure proof'); }
      }
    };
    void tick();
    const timer = setInterval(() => { void tick(); }, 1000);
    return () => { cancelled = true; clearInterval(timer); };
  }, [ticket]);

  return { qrPayload, secondsRemaining, reason };
}

// src/api/settlementSocket.ts
// Live M-Pesa settlement telemetry over Phoenix Channels (QA FI-01).
//
// The client opens an authenticated WebSocket to the backend `/socket` and
// joins `settlement:<transaction_id>`. Settlement is pushed the instant the
// async Daraja callback resolves, so the UI no longer depends solely on HTTP
// status polling that can drop under callback-queue latency. Polling remains as
// a fallback in case the socket cannot connect.

import { Socket } from 'phoenix';
import { WS_URL } from '@/constants/config';

export type SettlementStatus = 'success' | 'failure' | 'pending';

export interface SettlementUpdate {
  status: SettlementStatus;
  receipt?: string | null;
}

/**
 * Subscribe to settlement updates for a checkout transaction.
 * Returns an unsubscribe function that tears down the channel + socket.
 */
export function subscribeSettlement(
  transactionId: string,
  token: string | null,
  onUpdate: (update: SettlementUpdate) => void,
): () => void {
  const socket = new Socket(WS_URL, {
    params: token ? { token } : {},
  });

  socket.connect();

  const channel = socket.channel(`settlement:${transactionId}`, {});

  channel
    .join()
    .receive('ok', (resp: { status?: SettlementStatus }) => {
      // Late-join re-sync: server replies with the current ledger state.
      if (resp?.status) onUpdate({ status: resp.status });
    })
    .receive('error', () => {
      // Join refused (e.g. bad token); caller's polling fallback covers this.
    });

  channel.on('settled', (payload: SettlementUpdate) => onUpdate(payload));

  return () => {
    try {
      channel.leave();
      socket.disconnect();
    } catch {
      // no-op on teardown races
    }
  };
}

/** Core domain models shared across Dunda screens. */

export interface DundaEvent {
  id: string;
  name: string;
  venue: string;
  /** Human-readable date label, e.g. "FRI 12 JUN · 22:00". */
  date: string;
  /** Lowest ticket price in KSh. */
  price: number;
  /** Remaining tickets across all tiers; drives the urgency state. */
  remaining: number;
  /** Total capacity, used to compute the sell-through bar. */
  capacity: number;
}

export interface DundaTicket {
  id: string;
  eventName: string;
  venue: string;
  date: string;
  tier: string;
  /** Versioned server-signed entitlement; protocol v2 adds device-bound proofs. */
  jwt: string;
  protocol_version?: number;
  credential_public_key?: string | null;
  credential_epoch?: number;
}

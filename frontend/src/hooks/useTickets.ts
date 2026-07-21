import { fetchTickets } from '@/api/client';
import { useResource, type ResourceState } from '@/hooks/useResource';
import type { DundaTicket } from '@/types/domain';

/** Active entitlements. Offline failure never fabricates a usable credential. */
export function useTickets(): ResourceState<DundaTicket[]> {
  return useResource(fetchTickets, []);
}

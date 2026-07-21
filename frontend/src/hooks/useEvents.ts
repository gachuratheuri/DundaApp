import { fetchEvents } from '@/api/client';
import { SAMPLE_EVENTS } from '@/data/sample';
import { DEMO_DATA_ENABLED } from '@/constants/config';
import { useResource, type ResourceState } from '@/hooks/useResource';
import type { DundaEvent } from '@/types/domain';

/** Live event feed, falling back to bundled sample data when the API is down. */
export function useEvents(): ResourceState<DundaEvent[]> {
  return useResource(fetchEvents, DEMO_DATA_ENABLED ? SAMPLE_EVENTS : []);
}

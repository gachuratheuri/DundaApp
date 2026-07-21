import { useCallback, useEffect, useState } from 'react';

export interface ResourceState<T> {
  data: T;
  loading: boolean;
  /** Populated when the fetch failed and the fallback value is being shown. */
  error: string | null;
  refetch: () => void;
}

/**
 * Generic data hook. Runs `fetcher` on mount, exposes loading/error state, and
 * falls back to `fallback` if the request fails. Production fallbacks should
 * be empty or explicitly labelled stale data; this hook never fabricates a
 * successful server response.
 */
export function useResource<T>(fetcher: () => Promise<T>, fallback: T): ResourceState<T> {
  const [data, setData] = useState<T>(fallback);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [nonce, setNonce] = useState(0);

  const refetch = useCallback(() => setNonce((n) => n + 1), []);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);

    fetcher()
      .then((result) => {
        if (!cancelled) setData(result);
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : 'Failed to load');
        setData(fallback); // graceful degradation
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [nonce]);

  return { data, loading, error, refetch };
}

import React from 'react';
import { ActivityIndicator, Text, View } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { MOCK_EVENTS } from '../../data/events';
import { EventDetailScreen } from '../../screens/EventDetailScreen';
import { DEMO_DATA_ENABLED } from '../../constants/config';
import { api } from '../../api/client';
import { Colors } from '../../theme/dunda';

export default function EventDetail() {
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id: string }>();

  const [event, setEvent] = React.useState<any>(null);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    let mounted = true;
    api.get(`/events/${encodeURIComponent(String(id))}`)
      .then((payload) => {
        if (mounted) setEvent(payload?.data ?? null);
      })
      .catch((reason: unknown) => {
        if (!mounted) return;
        const demo = DEMO_DATA_ENABLED ? MOCK_EVENTS.find((candidate) => candidate.id === id) : null;
        if (demo) setEvent(demo);
        else setError(reason instanceof Error ? reason.message : 'Event unavailable');
      });
    return () => { mounted = false; };
  }, [id]);

  if (error) return <View style={{ flex: 1, backgroundColor: Colors.void, alignItems: 'center', justifyContent: 'center', padding: 24 }}><Text style={{ color: Colors.white }}>{error}</Text></View>;
  if (!event) return <View style={{ flex: 1, backgroundColor: Colors.void, alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator color={Colors.teal} /></View>;

  return <EventDetailScreen event={event} onBack={() => router.back()} />;
}

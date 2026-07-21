import React from 'react';
import { ActivityIndicator, View } from 'react-native';
import { Redirect } from 'expo-router';
import { api } from '@/api/client';
import { Colors } from '@/theme/dunda';

/** Route-level guard for screens that expose private tickets or account data. */
export function RequireAuth({ children }: { children: React.ReactNode }) {
  const [state, setState] = React.useState<'checking' | 'authenticated' | 'anonymous'>('checking');

  React.useEffect(() => {
    let mounted = true;
    api.getToken().then((token) => {
      if (mounted) setState(token ? 'authenticated' : 'anonymous');
    }).catch(() => {
      if (mounted) setState('anonymous');
    });
    return () => { mounted = false; };
  }, []);

  if (state === 'checking') {
    return <View style={{ flex: 1, backgroundColor: Colors.void, alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator color={Colors.teal} /></View>;
  }
  if (state === 'anonymous') return <Redirect href="/auth" />;
  return <>{children}</>;
}

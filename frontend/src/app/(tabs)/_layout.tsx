import { Tabs } from 'expo-router';
import { View } from 'react-native';
import { DundaTabs, DundaTab } from '../../navigation/DundaTabs';
import { useRouter, usePathname } from 'expo-router';

export default function TabLayout() {
  const router = useRouter();
  const pathname = usePathname();

  // Extract active tab from pathname
  const activeTab: DundaTab = pathname.includes('tickets')
    ? 'tickets'
    : pathname.includes('profile')
    ? 'profile'
    : 'discover';

  return (
    <View style={{ flex: 1 }}>
      <Tabs screenOptions={{ headerShown: false }} tabBar={() => null}>
        <Tabs.Screen name="index" />
        <Tabs.Screen name="tickets" />
        <Tabs.Screen name="profile" />
      </Tabs>
      <DundaTabs
        active={activeTab}
        onChange={(tab) => {
          if (tab === 'discover') router.navigate('/');
          if (tab === 'tickets') router.navigate('/tickets');
          if (tab === 'profile') router.navigate('/profile');
        }}
      />
    </View>
  );
}

import { useRouter } from 'expo-router';
import { DiscoverScreen } from '../../screens/DiscoverScreen';
import { AstralEvent } from '../../components/AstralEventCard';

export default function Index() {
  const router = useRouter();

  const handleEventPress = (event: AstralEvent) => {
    router.push({ pathname: '/event/[id]', params: { id: event.id } });
  };

  return <DiscoverScreen onEventPress={handleEventPress} />;
}

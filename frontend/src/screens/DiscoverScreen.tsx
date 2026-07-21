// src/screens/DiscoverScreen.tsx
// Dunda "Astral Dark" Discover Feed
//
// Layout hierarchy (DICE-inspired, darkened):
//   1. Deep space gradient background — always void black
//   2. Sticky glass header with location + search pill
//   3. Hero event card (full-bleed, 460px, dominant)
//   4. Horizontal "Near You Tonight" rail
//   5. Full vertical event list with pull-to-refresh
//
// Performance: FlashList for the vertical feed, FlatList for rails.
// All heavy blur operations are on PrismGlassPanel (GPU texture offload).

import React, { useState, useCallback, useEffect, useMemo } from 'react';
import {
  View, Text, StyleSheet, FlatList, RefreshControl,
  Pressable, TextInput, StatusBar, Platform,
  Alert
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { BlurView } from 'expo-blur';
import Animated, {
  useSharedValue, useAnimatedScrollHandler, useAnimatedStyle,
  interpolate, Extrapolate, useAnimatedProps, withRepeat, withTiming, Easing as ReanimatedEasing
} from 'react-native-reanimated';
import { useRouter } from 'expo-router';
import { FlashList } from '@shopify/flash-list';
import { Ionicons } from '@expo/vector-icons';

const AnimatedFlashList = Animated.createAnimatedComponent(FlashList) as any;
import * as Haptics from 'expo-haptics';
import { triggerHaptic } from '../utils/haptics';
import { SafeAreaView } from 'react-native-safe-area-context';
import Svg, { Circle } from 'react-native-svg';
import { AstralEventCard, AstralEvent } from '../components/AstralEventCard';
import { HollowText } from '../components/HollowText';
import { TiketaLogo } from '../components/TiketaLogo';
import { SkeletonFeed, SkeletonBlock } from '../components/Skeleton';
import { api } from '../api/client';
import { MOCK_EVENTS } from '../data/events';
import { DEMO_DATA_ENABLED } from '../constants/config';
import { Colors, Font, Space, Radius, Screen, Z, Gradients } from '../theme/dunda';

const LocationGlow: React.FC = () => (
  <View
    style={{
      position: 'absolute',
      top: -120,
      left: Screen.width / 2 - 150,
      width: 300,
      height: 300,
      borderRadius: 150,
      backgroundColor: Colors.opticCyan,
      opacity: 0.15,
      ...Platform.select({
        web: {
          filter: 'blur(80px)',
        },
        default: {
          shadowColor: Colors.opticCyan,
          shadowOffset: { width: 0, height: 0 },
          shadowOpacity: 0.8,
          shadowRadius: 80,
        }
      })
    }}
    pointerEvents="none"
  />
);

const AnimatedCircle = Animated.createAnimatedComponent(Circle);

const FizzParticle = ({ p }: { p: any }) => {
  const progress = useSharedValue(0);
  useEffect(() => {
    progress.value = withRepeat(
      withTiming(1, { duration: p.duration, easing: ReanimatedEasing.linear }),
      -1,
      false
    );
  }, [p.duration, progress]);

  const animatedProps = useAnimatedProps(() => {
    return {
      cy: interpolate(progress.value, [0, 1], [400, -20]),
      opacity: interpolate(progress.value, [0, 0.8, 1], [0, p.opacity, 0]),
    };
  });

  return (
    <AnimatedCircle
      cx={p.x}
      r={p.r}
      fill={Colors.white}
      animatedProps={animatedProps}
    />
  );
};

const CityEnergyParticleField: React.FC = () => {
  const particles = useMemo(() => {
    return Array.from({ length: 40 }).map((_, i) => ({
      id: i,
      x: Math.random() * Screen.width,
      r: Math.random() * 2.5 + 0.8,
      opacity: Math.random() * 0.4 + 0.1,
      duration: Math.random() * 3000 + 3000,
    }));
  }, []);

  return (
    <View style={[StyleSheet.absoluteFillObject, { height: 400, overflow: 'hidden', zIndex: 0 }]} pointerEvents="none">
      <Svg style={StyleSheet.absoluteFillObject}>
        {particles.map((p) => (
          <FizzParticle key={p.id} p={p} />
        ))}
      </Svg>
    </View>
  );
};

const HERO_THRESHOLD = 60;

const CATEGORIES = ['All', 'Tonight', 'This Week', 'Festival', 'Club Night', 'Afrobeats', 'Jazz', 'Comedy', 'Art', 'Sports', 'Live Music', 'VIP'];

// ── Helpers ──────────────────────────────────────────────────────────────────
const DAY_MS = 86_400_000;

function filterByCategory(events: AstralEvent[], category: string): AstralEvent[] {
  if (category === 'All') return events;

  const now = Date.now();

  if (category === 'Tonight') {
    return events.filter((e) => {
      const t = new Date(e.starts_at).getTime();
      return t >= now && t <= now + DAY_MS;
    });
  }

  if (category === 'This Week') {
    return events.filter((e) => {
      const t = new Date(e.starts_at).getTime();
      return t >= now && t <= now + DAY_MS * 7;
    });
  }

  if (category === 'VIP') {
    return events.filter((e) => e.is_vip);
  }

  // Genre-tag match (case-insensitive)
  const lowerCat = category.toLowerCase();
  return events.filter((e) => e.genre_tag?.toLowerCase() === lowerCat);
}

function filterBySearch(events: AstralEvent[], query: string): AstralEvent[] {
  if (!query.trim()) return events;
  const q = query.toLowerCase();
  return events.filter(
    (e) =>
      e.name.toLowerCase().includes(q) ||
      e.venue.toLowerCase().includes(q),
  );
}

// ── Component ────────────────────────────────────────────────────────────────
export const DiscoverScreen: React.FC<{ onEventPress: (e: AstralEvent) => void }> = ({ onEventPress }) => {
  const router = useRouter();
  const [selected, setSelected] = useState('All');
  const [searchQuery, setSearchQuery] = useState('');
  const [isGridView, setIsGridView] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [events, setEvents] = useState<AstralEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [isSampleData, setIsSampleData] = useState(false);
  const scrollY = useSharedValue(0);

  const fetchEvents = async () => {
    try {
      const response = await api.get('/events');
      if (response.data && response.data.length > 0) {
        setEvents(response.data);
        setIsSampleData(false);
      } else {
        setEvents(DEMO_DATA_ENABLED ? MOCK_EVENTS : []);
        setIsSampleData(DEMO_DATA_ENABLED);
      }
    } catch {
      console.warn("Failed to fetch events from backend");
      setEvents(DEMO_DATA_ENABLED ? MOCK_EVENTS : []);
      setIsSampleData(DEMO_DATA_ENABLED);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    const timer = setTimeout(() => {
      fetchEvents();
    }, 150);
    return () => clearTimeout(timer);
  }, []);

  // Derived filtered list — recalculated when category, search, or events change
  const filteredEvents = useMemo(
    () => filterBySearch(filterByCategory(events, selected), searchQuery),
    [events, selected, searchQuery],
  );

  const scrollHandler = useAnimatedScrollHandler({ onScroll: (e) => { scrollY.value = e.contentOffset.y; } });

  const headerStyle = useAnimatedStyle(() => ({
    opacity:      interpolate(scrollY.value, [0, HERO_THRESHOLD], [0, 1], Extrapolate.CLAMP),
    borderBottomColor: `rgba(255,255,255,${interpolate(scrollY.value, [0, HERO_THRESHOLD], [0, 0.08], Extrapolate.CLAMP)})`,
  }));

  const heroCard = filteredEvents[0] || events[0] || null;

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    await fetchEvents();
    setRefreshing(false);
  }, []);

  const renderRailItem = useCallback(({ item }: { item: AstralEvent }) => (
    <View style={styles.railItem}>
      <AstralEventCard event={item} onPress={onEventPress} variant="compact" />
    </View>
  ), [onEventPress]);

  const renderEventItem = useCallback((info: any) => {
    const item: AstralEvent = info.item;
    if (isGridView) {
      return (
        <View style={{ width: (Screen.width - Space.base * 2 - Space.sm) / 2, paddingBottom: Space.sm }}>
          <AstralEventCard event={item} onPress={onEventPress} variant="grid" />
        </View>
      );
    }
    return (
      <View style={styles.section}>
        <AstralEventCard event={item} onPress={onEventPress} variant="card" />
      </View>
    );
  }, [isGridView, onEventPress]);

  const ListHeader = useCallback(() => (
    <View>
        <SafeAreaView edges={['top']} />

        <View style={styles.titleRow}>
          <View style={styles.titleStack} accessible accessibilityRole="header" accessibilityLabel="What's On in Nairobi">
            <Text style={styles.titleSub} importantForAccessibility="no-hide-descendants" accessibilityElementsHidden>NAIROBI</Text>
            <View style={styles.titleLayer} importantForAccessibility="no-hide-descendants" accessibilityElementsHidden>
              <HollowText size={58} style={styles.titleHollow}>What&apos;s On</HollowText>
              <Text style={styles.titleSolid}>What&apos;s On</Text>
            </View>
          </View>
          <Pressable style={styles.notifBtn} onPress={() => { triggerHaptic(Haptics.ImpactFeedbackStyle.Light); router.push('/notifications'); }} accessibilityRole="button" accessibilityLabel="View notifications">
            <Ionicons name="notifications-outline" size={22} color={Colors.white} />
            <View style={styles.notifBadge} accessibilityElementsHidden importantForAccessibility="no" />
          </Pressable>
        </View>

        {isSampleData && (
          <View style={styles.sampleBanner}>
            <Ionicons name="cloud-offline" size={14} color={Colors.goldPrestige || Colors.gold || '#F4F800'} style={{ marginRight: Space.xs }} />
            <Text style={styles.sampleText}>Offline Mode / Showing Demo Data</Text>
          </View>
        )}

        <View style={styles.searchRow}>
          <View style={styles.searchBar}>
            <Ionicons name="search" size={20} color={Colors.periwinkle} style={{ marginRight: Space.xs }} />
            <TextInput
              placeholder="Artists, venues, events..."
              placeholderTextColor={Colors.periwinkle}
              style={styles.searchInput}
              value={searchQuery}
              onChangeText={setSearchQuery}
            />
          </View>
          <Pressable style={styles.filterBtn} onPress={() => { triggerHaptic(Haptics.ImpactFeedbackStyle.Light); setIsGridView(v => !v); }} accessibilityRole="button" accessibilityLabel={isGridView ? 'Switch to list view' : 'Switch to grid view'}>
            <Ionicons name={isGridView ? 'list' : 'grid'} size={20} color={Colors.periwinkle} />
          </Pressable>
        </View>

        <FlatList
          data={CATEGORIES}
          horizontal
          showsHorizontalScrollIndicator={false}
          keyExtractor={(c) => c}
          contentContainerStyle={styles.catList}
          renderItem={({ item }) => (
            <Pressable
              onPress={() => setSelected(item)}
              style={[styles.catPill, item === selected && styles.catPillActive]}
              accessibilityRole="button"
              accessibilityState={{ selected: item === selected }}
              accessibilityLabel={`Filter events by ${item} category`}
            >
              <Text style={[styles.catText, item === selected && styles.catTextActive]}>{item}</Text>
            </Pressable>
          )}
        />

        {heroCard && (
          <View style={styles.section}>
            <AstralEventCard event={heroCard} onPress={onEventPress} variant="hero" />
          </View>
        )}

        <View style={styles.brandRow}>
           <Pressable style={styles.primaryCta} onPress={() => Alert.alert("Coming Soon", "Filter and browse features are coming soon!")}>
              <Text style={styles.primaryCtaText}>Browse Events</Text>
           </Pressable>
           <Pressable style={styles.secondaryCta} onPress={() => Alert.alert("Start Selling", "The Dunda Organiser Portal is available on web at dunda.app/portal")}>
              <Text style={styles.secondaryCtaText}>Start Selling</Text>
           </Pressable>
        </View>
        <View style={styles.trustMarkers}>
           <Text style={styles.trustMarker}>✓ M-Pesa Native</Text>
           <Text style={styles.trustMarker}>✓ Verified Organisers</Text>
           <Text style={styles.trustMarker}>✓ Secure ticket credentials</Text>
        </View>

        <View style={styles.sectionHeader}>
          <Text style={styles.sectionTitle}>Near You Tonight</Text>
          <Pressable><Text style={styles.seeAll}>See all →</Text></Pressable>
        </View>
        {loading ? (
          <View style={[styles.railList, { flexDirection: 'row', gap: Space.sm }]}>
            <SkeletonBlock width={260} height={200} radius={Radius.card} />
            <SkeletonBlock width={260} height={200} radius={Radius.card} />
          </View>
        ) : (
          <FlatList
            data={filteredEvents.slice(1, 4)}
            horizontal
            showsHorizontalScrollIndicator={false}
            keyExtractor={(e) => e.id + '_rail'}
            contentContainerStyle={styles.railList}
            renderItem={renderRailItem}
          />
        )}

        <View style={styles.sectionHeader}>
          <Text style={styles.sectionTitle}>Don't Miss</Text>
        </View>
    </View>
  ), [isGridView, loading, filteredEvents, heroCard, searchQuery, selected, isSampleData, renderRailItem, onEventPress, router]);

  const ListFooter = useCallback(() => (
    <View>
        {loading && <SkeletonFeed count={3} />}

        {!loading && filteredEvents.length === 0 && (
          <View style={styles.emptyState}>
            <Ionicons name="search-outline" size={48} color={Colors.white10} style={{ marginBottom: Space.base }} />
            <Text style={styles.emptyTitle}>No events found</Text>
            <Text style={styles.emptyBody}>{isSampleData ? 'Demo data is unavailable.' : 'Events are unavailable right now. Check your connection and try again.'}</Text>
          </View>
        )}

        <View style={styles.faqSection}>
          <Text style={styles.sectionTitle}>Frequently Asked Questions</Text>
          <Pressable style={styles.faqItem}><Text style={styles.faqText}>How do I access offline tickets?</Text></Pressable>
          <Pressable style={styles.faqItem}><Text style={styles.faqText}>Are M-Pesa payments instant?</Text></Pressable>
          <Pressable style={styles.faqItem}><Text style={styles.faqText}>How do I become a verified organiser?</Text></Pressable>
        </View>

        <View style={{ height: 120 }} />
    </View>
  ), [loading, filteredEvents.length, isSampleData]);

  return (
    <View style={styles.root}>
      <StatusBar barStyle="light-content" backgroundColor={Colors.void} />
      <LinearGradient colors={Gradients.deepSpace} style={StyleSheet.absoluteFillObject} locations={[0, 0.4, 1]} />

      {/* ── Glow & Particle Backgrounds ── */}
      <LocationGlow />
      <CityEnergyParticleField />

      {/* ── Sticky Glass Header ── */}
      <Animated.View style={[styles.headerWrapper, headerStyle]}>
        <BlurView intensity={60} tint="dark" style={styles.header}>
          <SafeAreaView edges={['top']} style={styles.headerInner}>
            <View style={styles.headerRow}>
              <View style={styles.locationPill}>
                <Ionicons name="location-sharp" size={12} color={Colors.teal} style={{ marginRight: 2 }} />
                <Text style={styles.locationText}>Nairobi</Text>
              </View>
              <View style={styles.brandRowHeader}>
                <TiketaLogo size={22} color={Colors.teal} label="Tiketa" />
                <Text style={styles.dunda}>TIKETA</Text>
              </View>
              <Pressable style={styles.profileBtn} accessibilityRole="button" accessibilityLabel="Open your profile">
                <Text style={styles.profileInitial} accessibilityElementsHidden importantForAccessibility="no">T</Text>
              </Pressable>
            </View>
          </SafeAreaView>
        </BlurView>
      </Animated.View>

      <AnimatedFlashList
        data={filteredEvents}
        keyExtractor={(e: any) => e.id}
        renderItem={renderEventItem}
        key={isGridView ? 'grid' : 'list'}
        numColumns={isGridView ? 2 : 1}
        estimatedItemSize={isGridView ? 240 : 320}
        ListHeaderComponent={ListHeader}
        ListFooterComponent={ListFooter}
        onScroll={scrollHandler}
        scrollEventThrottle={16}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={Colors.teal} />}
        contentContainerStyle={styles.scroll}
        showsVerticalScrollIndicator={false}
      />
    </View>
  );
};

const styles = StyleSheet.create({
  root:  { flex: 1, backgroundColor: Colors.void },
  scroll: { paddingHorizontal: Space.base },

  headerWrapper: {
    position: 'absolute', top: 0, left: 0, right: 0,
    zIndex: Z.header, borderBottomWidth: 1,
  },
  header: { width: '100%' },
  headerInner: { paddingHorizontal: Space.base, paddingBottom: Space.sm },
  headerRow:   { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  brandRowHeader: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  dunda:       { ...Font.h2, color: Colors.teal, letterSpacing: 3 },
  locationPill: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  locationDot:  { color: Colors.teal, fontSize: 12 },
  locationText: { ...Font.labelL, color: Colors.pureWhite },
  profileBtn:  {
    width: 34, height: 34, borderRadius: 17,
    backgroundColor: Colors.tealDark, alignItems: 'center', justifyContent: 'center',
  },
  profileInitial: { ...Font.labelL, color: Colors.white },

  titleRow:  { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-end', marginTop: Space.xl, marginBottom: Space.base },
  titleStack: { flex: 1 },
  titleSub:  { ...Font.labelS, color: Colors.teal, marginBottom: 2 },
  // Foreground/background layers share a row; hollow echo is absolutely
  // positioned so the solid title sits on top in the Z-stack.
  titleLayer: { position: 'relative', justifyContent: 'center', minHeight: 52 },
  titleHollow: {
    position: 'absolute',
    left: 0,
    textAlign: 'left',
    transform: [{ translateX: 5 }, { translateY: -4 }, { scale: 1.04 }],
  },
  titleSolid: {
    fontFamily: Platform.OS === 'web' ? 'Oswald, impact, sans-serif' : 'System',
    fontWeight: '900',
    fontSize: 48,
    lineHeight: 48,
    letterSpacing: -2,
    textTransform: 'uppercase',
    color: Colors.white,
    textShadowColor: 'rgba(2,2,2,0.9)',
    textShadowOffset: { width: 0, height: 6 },
    textShadowRadius: 18,
  },
  notifBtn:  { position: 'relative', padding: Space.sm },
  notifIcon: { fontSize: 22 },
  notifBadge: {
    position: 'absolute', top: 8, right: 8,
    width: 8, height: 8, borderRadius: 4, backgroundColor: Colors.magenta,
    borderWidth: 2, borderColor: Colors.void,
  },

  searchRow: { flexDirection: 'row', gap: Space.sm, marginBottom: Space.base },
  searchBar: {
    flex: 1, flexDirection: 'row', alignItems: 'center',
    backgroundColor: Colors.surface, borderRadius: Radius.pill,
    paddingHorizontal: Space.base, height: 48,
    borderWidth: 1, borderColor: Colors.white10,
  },
  searchIcon:  { fontSize: 20, color: Colors.periwinkle, marginRight: Space.xs },
  searchInput: { flex: 1, ...Font.bodyM, color: Colors.white },
  filterBtn: {
    width: 48, height: 48, borderRadius: Radius.md,
    backgroundColor: Colors.surface, borderWidth: 1, borderColor: Colors.white10,
    alignItems: 'center', justifyContent: 'center',
  },
  filterIcon: { fontSize: 20, color: Colors.periwinkle },

  catList: { paddingBottom: Space.base, gap: Space.sm },
  catPill: {
    paddingHorizontal: Space.base, paddingVertical: Space.sm,
    borderRadius: Radius.pill, backgroundColor: Colors.surface,
    borderWidth: 1, borderColor: Colors.white10,
  },
  catPillActive: { backgroundColor: Colors.teal, borderColor: Colors.teal },
  catText:       { ...Font.labelL, color: Colors.periwinkle },
  catTextActive: { color: Colors.void },

  section:       { },
  sectionHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: Space.sm, marginTop: Space.md },
  sectionTitle:  { ...Font.h3, color: Colors.white },
  seeAll:        { ...Font.labelM, color: Colors.teal },
  railList:      { gap: Space.sm, paddingBottom: Space.base },
  railItem:      { width: Screen.width * 0.65 },

  brandRow: { flexDirection: 'row', gap: Space.sm, marginTop: Space.base },
  primaryCta: { flex: 1, backgroundColor: Colors.magenta, borderRadius: Radius.pill, height: 50, alignItems: 'center', justifyContent: 'center' },
  primaryCtaText: { ...Font.labelL, color: Colors.white, textTransform: 'uppercase', letterSpacing: 1 },
  secondaryCta: { flex: 1, backgroundColor: 'transparent', borderRadius: Radius.pill, height: 50, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: Colors.white10 },
  secondaryCtaText: { ...Font.labelL, color: Colors.white, textTransform: 'uppercase', letterSpacing: 1 },
  trustMarkers: { flexDirection: 'row', justifyContent: 'space-around', marginTop: Space.base, marginBottom: Space.lg },
  trustMarker: { ...Font.labelS, color: Colors.periwinkle, fontSize: 10, letterSpacing: 0.5 },

  emptyState: { alignItems: 'center', paddingVertical: Space.xl * 2 },
  emptyIcon:  { fontSize: 48, marginBottom: Space.base },
  emptyTitle: { ...Font.h3, color: Colors.white, marginBottom: Space.xs },
  emptyBody:  { ...Font.bodyM, color: Colors.periwinkle },

  faqSection: { marginTop: Space.xl, paddingBottom: Space.xl },
  faqItem: { borderBottomWidth: 1, borderBottomColor: Colors.white10, paddingVertical: Space.base },
  faqText: { ...Font.bodyM, color: Colors.white },

  sampleBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(244, 248, 0, 0.1)',
    borderWidth: 1,
    borderColor: 'rgba(244, 248, 0, 0.3)',
    paddingVertical: Space.sm,
    paddingHorizontal: Space.base,
    marginHorizontal: Space.base,
    marginTop: Space.sm,
    marginBottom: Space.base,
  },
  sampleText: {
    ...Font.labelS,
    color: '#F4F800',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
});

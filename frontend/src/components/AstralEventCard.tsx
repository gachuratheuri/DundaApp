// src/components/AstralEventCard.tsx
// Dunda "Astral Dark" event card — the primary discovery unit.
//
// Design language:
//   - Full-bleed cover image with deep scrim (inspired by DICE card hierarchy)
//   - Prism glass chip for category (Image 3 crystal refraction)
//   - Gold glow for VIP tier (Image 2 staircase prestige)
//   - Teal glow for sold-out / low-stock pressure (Image 1 bioluminescent urgency)
//   - Spring press animation — tactile, never janky
//   - Accessibility: reduced-motion safe, a11y labels

import React from 'react';
import {
  View, Text, StyleSheet,
  ImageBackground,
} from 'react-native';
import Animated, {
  useSharedValue, useAnimatedStyle, withSpring, interpolate, runOnJS, withRepeat, withTiming, withSequence, Easing as ReanimatedEasing, useReducedMotion
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import { triggerHaptic } from '../utils/haptics';
import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import { Colors, Font, Space, Radius, Glow, Gradients, Easing } from '../theme/dunda';
import { Ionicons } from '@expo/vector-icons';

export interface EventTier {
  id?: string;
  label: string;
  price_cents: number;
  sold: number;
  total: number;
  remaining: number;
  vip?: boolean;
}

export interface AstralEvent {
  id: string;
  name: string;
  venue: string;
  starts_at: string;       // ISO 8601
  price_cents: number;
  tier_label: string;
  is_vip: boolean;
  remaining: number;
  sold_out: boolean;
  cover_uri?: string;
  genre_tag?: string;
  description?: string;
  tiers?: EventTier[];
}

interface Props {
  event: AstralEvent;
  onPress: (event: AstralEvent) => void;
  variant?: 'hero' | 'card' | 'compact' | 'grid';
}

const CARD_HEIGHT   = 320;
const HERO_HEIGHT   = 460;
const COMPACT_HEIGHT = 200;
const GRID_HEIGHT   = 240;

const PulsingUrgencyDot: React.FC = () => {
  const scale = useSharedValue(1);
  const opacity = useSharedValue(1);
  const reduceMotion = useReducedMotion();

  React.useEffect(() => {
    // WCAG 2.2 SC 2.3.3 — skip the continuous pulse when reduced motion is on.
    if (reduceMotion) return;
    scale.value = withRepeat(
      withSequence(
        withTiming(1.6, { duration: 1000 }),
        withTiming(1, { duration: 1000 })
      ),
      -1,
      true
    );
    opacity.value = withRepeat(
      withSequence(
        withTiming(0.4, { duration: 1000 }),
        withTiming(1, { duration: 1000 })
      ),
      -1,
      true
    );
  }, [reduceMotion, scale, opacity]);

  const pulseStyle = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
    opacity: opacity.value,
  }));

  return (
    <View style={{ width: 12, height: 12, alignItems: 'center', justifyContent: 'center', marginRight: Space.xs }}>
      <Animated.View style={[{
        width: 8, height: 8, borderRadius: 4,
        backgroundColor: Colors.hotPink,
      }, pulseStyle]} />
    </View>
  );
};

const AvailableDot: React.FC = () => (
  <View style={{ width: 12, height: 12, alignItems: 'center', justifyContent: 'center', marginRight: Space.xs }}>
    <View style={{
      width: 8, height: 8, borderRadius: 4,
      backgroundColor: Colors.opticCyan,
    }} />
  </View>
);

const SoldOutDot: React.FC = () => (
  <View style={{ width: 12, height: 12, alignItems: 'center', justifyContent: 'center', marginRight: Space.xs }}>
    <View style={{
      width: 8, height: 8, borderRadius: 4,
      backgroundColor: Colors.periwinkle,
      opacity: 0.4,
    }} />
  </View>
);

export const AstralEventCard: React.FC<Props> = ({ event, onPress, variant = 'card' }) => {
  const pressed   = useSharedValue(0);
  const interactX = useSharedValue(0);
  const interactY = useSharedValue(0);
  const ambientT  = useSharedValue(0);
  const reduceMotion = useReducedMotion();

  const [isHovered, setIsHovered] = React.useState(false);

  React.useEffect(() => {
    // Continuous ambient slow-axis rotation (Y and Z).
    // WCAG 2.2 SC 2.3.3 — disabled entirely under reduced-motion (QA AC-02).
    if (reduceMotion) {
      ambientT.value = 0;
      return;
    }
    ambientT.value = withRepeat(
      withTiming(2 * Math.PI, { duration: 12000, easing: ReanimatedEasing.linear }),
      -1, false
    );
  }, [reduceMotion, ambientT]);

  const height    = variant === 'hero' ? HERO_HEIGHT : variant === 'compact' ? COMPACT_HEIGHT : variant === 'grid' ? GRID_HEIGHT : CARD_HEIGHT;
  const isVip     = event.is_vip;
  const isLow     = !event.sold_out && event.remaining > 0 && event.remaining <= 20;
  const isSoldOut = event.sold_out || event.remaining === 0;

  const formattedDate = new Intl.DateTimeFormat('en-KE', {
    weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit',
  }).format(new Date(event.starts_at));

  const formattedPrice = isSoldOut
    ? 'SOLD OUT'
    : `KSh ${(event.price_cents / 100).toLocaleString('en-KE')}/=`;

  const handleHaptic = React.useCallback(() => {
    triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
  }, []);

  const onGestureBegin = (e: any) => {
    'worklet';
    runOnJS(handleHaptic)();
    pressed.value = withSpring(1, Easing.spring);
    interactX.value = withSpring(interpolate(e.y, [0, height], [2, -2], 'clamp'));
    interactY.value = withSpring(interpolate(e.x, [0, 350], [-2, 2], 'clamp'));
  };

  const onGestureUpdate = (e: any) => {
    'worklet';
    interactX.value = interpolate(e.y, [0, height], [2, -2], 'clamp');
    interactY.value = interpolate(e.x, [0, 350], [-2, 2], 'clamp');
  };

  const onGestureFinalize = () => {
    'worklet';
    pressed.value = withSpring(0, Easing.spring);
    interactX.value = withSpring(0);
    interactY.value = withSpring(0);
  };

  const pan = Gesture.Pan()
    .minDistance(0)
    .onBegin(onGestureBegin)
    .onUpdate(onGestureUpdate)
    .onFinalize(onGestureFinalize);

  const onTapEnd = React.useCallback(() => {
    runOnJS(onPress)(event);
  }, [onPress, event]);

  const tap = Gesture.Tap()
    .runOnJS(true)
    .onEnd(onTapEnd);

  const composed = Gesture.Simultaneous(pan, tap);

  const animStyle = useAnimatedStyle(() => {
      const ambX = Math.sin(ambientT.value) * 2;
      const ambY = Math.cos(ambientT.value) * 2;
      return {
        transform: [
          { scale:      interpolate(pressed.value, [0, 1], [1, 0.965]) },
          { translateY: interpolate(pressed.value, [0, 1], [0, 3]) },
          { perspective: 1000 },
          { rotateX: `${interactX.value || ambX}deg` },
          { rotateY: `${interactY.value || ambY}deg` },
        ],
      };
  });

  const glowStyle = isHovered ? Glow.hoverGlow : isVip ? Glow.goldSm : isLow ? Glow.tealSm : Glow.cardBase;
  const borderColor = isHovered ? Colors.teal : isVip ? Colors.gold : isLow ? Colors.teal : Colors.glassBorder;

  return (
    <GestureDetector gesture={composed}>
      <Animated.View
        {...{onHoverIn: () => setIsHovered(true), onHoverOut: () => setIsHovered(false)} as any}
        style={[styles.container, { height }, animStyle, glowStyle,
        { borderColor, borderWidth: 1 }]}
        accessible
        accessibilityRole="button"
        accessibilityLabel={`${event.name} at ${event.venue}, ${formattedDate}. ${formattedPrice}.${isSoldOut ? ' Sold out.' : isLow ? ` Only ${event.remaining} left.` : ''}`}
      >
        <ImageBackground
          source={{ uri: event.cover_uri?.replace('800/600', '1200/900') ?? 'https://picsum.photos/seed/' + event.id + '/1200/900' }}
          style={styles.image}
          imageStyle={styles.imageStyle}
          resizeMode="cover"
        >
          {/* Deep scrim — bottom 60% fade to void */}
          <LinearGradient
            colors={Gradients.heroBottom}
            locations={[0, 0.5, 1]}
            style={[StyleSheet.absoluteFillObject, { top: '20%' }]}
          />

          {/* Gloss overlay reflection */}
          <LinearGradient
            colors={['rgba(255,255,255,0.35)', 'transparent']}
            locations={[0, 0.4]}
            style={StyleSheet.absoluteFillObject}
          />

          {/* Top row: category chip + VIP badge */}
          <View style={styles.topRow}>
            {event.genre_tag && (
              <View style={styles.genreChip}>
                <Text style={styles.genreText}>{event.genre_tag.toUpperCase()}</Text>
              </View>
            )}
            {isVip && (
              <LinearGradient colors={Gradients.vipGold} style={styles.vipBadge} start={{x:0,y:0}} end={{x:1,y:0}}>
                <Text style={styles.vipText}><Ionicons name="sparkles" size={10} color={Colors.void} /> VIP</Text>
              </LinearGradient>
            )}
          </View>

          {/* Bottom metadata block */}
          <View style={styles.metaBlock}>
            <Text style={[styles.eventName, variant === 'grid' && { fontSize: 18, lineHeight: 22 }]} numberOfLines={variant === 'grid' ? 1 : 2}>{event.name}</Text>
            <Text style={styles.venue} numberOfLines={1}>📍 {event.venue}</Text>
            <View style={styles.bottomRow}>
              {variant !== 'grid' && (
                <View style={styles.dateChip}>
                  <Text style={styles.dateText}>{formattedDate}</Text>
                </View>
              )}
              <View style={[styles.priceChip, variant === 'grid' && { paddingHorizontal: Space.sm, paddingVertical: 4 },
                isSoldOut ? styles.soldOut : isVip ? styles.priceVip : styles.pricePrimary]}>
                <Text style={[styles.priceText, variant === 'grid' && { fontSize: 12 },
                  isSoldOut ? styles.priceTextGray : isVip ? styles.priceTextGold : {}]}>
                  {formattedPrice}
                </Text>
              </View>
            </View>

            {/* State indicators (inventory dots) */}
            {variant !== 'grid' && (
              <View style={styles.statusDotRow}>
                {isSoldOut ? (
                  <>
                    <SoldOutDot />
                    <Text style={styles.statusDotText}>SOLD OUT</Text>
                  </>
                ) : isLow ? (
                  <>
                    <PulsingUrgencyDot />
                    <Text style={[styles.statusDotText, { color: Colors.hotPink }]}>LAST {event.remaining} TICKETS</Text>
                  </>
                ) : (
                  <>
                    <AvailableDot />
                    <Text style={[styles.statusDotText, { color: Colors.opticCyan }]}>AVAILABLE</Text>
                  </>
                )}
              </View>
            )}
          </View>
        </ImageBackground>
      </Animated.View>
    </GestureDetector>
  );
};

const styles = StyleSheet.create({
  container: {
    borderRadius: Radius.card,
    overflow: 'hidden',
    marginBottom: Space.base,
    backgroundColor: Colors.abyss,
  },
  image: { flex: 1 },
  imageStyle: { borderRadius: Radius.card },

  topRow: {
    position: 'absolute', top: Space.base, left: Space.base, right: Space.base,
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
  },
  genreChip: {
    backgroundColor: Colors.glass,
    borderWidth: 1, borderColor: Colors.white10,
    paddingHorizontal: Space.sm, paddingVertical: 4,
    borderRadius: Radius.pill,
  },
  genreText: { ...Font.labelS, color: Colors.periwinkle },

  vipBadge: {
    paddingHorizontal: Space.sm + 2, paddingVertical: 5,
    borderRadius: Radius.pill,
  },
  vipText: { ...Font.labelS, color: Colors.void, letterSpacing: 1.2 },

  metaBlock: {
    position: 'absolute', bottom: 0, left: 0, right: 0,
    padding: Space.base,
  },
  eventName: {
    ...Font.h1, color: Colors.white,
    marginBottom: Space.xs,
    textShadowColor: 'rgba(0,0,0,0.8)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 6,
  },
  venue: {
    ...Font.bodyS, color: Colors.periwinkle,
    marginBottom: Space.sm,
  },
  bottomRow: {
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
  },
  dateChip: {
    backgroundColor: Colors.glassBright,
    borderWidth: 1, borderColor: Colors.white20,
    paddingHorizontal: Space.sm, paddingVertical: 5,
    borderRadius: Radius.sm,
    flex: 1, marginRight: Space.sm,
  },
  dateText: { ...Font.labelM, color: Colors.white },

  priceChip: {
    paddingHorizontal: Space.md, paddingVertical: 7,
    borderRadius: Radius.xs, // Sharper button radius
    shadowColor: Colors.void, shadowOffset: {width:0,height:2}, shadowOpacity:0.5, shadowRadius:4,
  },
  pricePrimary: { backgroundColor: Colors.magenta }, // Solid Acid Magenta
  priceVip:  { backgroundColor: Colors.goldMid },
  soldOut:   { backgroundColor: Colors.surface, borderWidth: 1, borderColor: Colors.white20 },
  priceText: { ...Font.labelL, color: Colors.white },
  priceTextGold: { color: Colors.void },
  priceTextGray: { color: Colors.periwinkle },

  urgencyRow: {
    flexDirection: 'row', alignItems: 'center', marginTop: Space.xs,
  },
  urgencyDot: {
    width: 6, height: 6, borderRadius: 3,
    backgroundColor: Colors.teal, marginRight: Space.xs,
  },
  urgencyText: { ...Font.labelM, color: Colors.teal },
  statusDotRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: Space.sm,
  },
  statusDotText: {
    ...Font.labelS,
    color: Colors.white60,
    textTransform: 'uppercase',
  },
});

// src/components/Skeleton.tsx
// Progressive-hydration skeletons (QA DC-03). Renders layout-matched
// placeholders during cold loads so the UI never shows a bare black frame.
// The shimmer respects the platform reduced-motion preference (QA AC-02).

import React, { useEffect } from 'react';
import { View, StyleSheet, type ViewStyle, type DimensionValue } from 'react-native';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withRepeat,
  withTiming,
  interpolate,
  Easing,
  useReducedMotion,
} from 'react-native-reanimated';
import { Colors, Radius, Space } from '../theme/dunda';

interface SkeletonBlockProps {
  width?: DimensionValue;
  height?: DimensionValue;
  radius?: number;
  style?: ViewStyle;
}

/** A single shimmering placeholder block. */
export const SkeletonBlock: React.FC<SkeletonBlockProps> = ({
  width = '100%',
  height = 16,
  radius = Radius.sm,
  style,
}) => {
  const t = useSharedValue(0);
  const reduceMotion = useReducedMotion();

  useEffect(() => {
    if (reduceMotion) return;
    t.value = withRepeat(withTiming(1, { duration: 1100, easing: Easing.inOut(Easing.ease) }), -1, true);
  }, [reduceMotion, t]);

  const shimmer = useAnimatedStyle(() => ({
    opacity: reduceMotion ? 0.5 : interpolate(t.value, [0, 1], [0.35, 0.7]),
  }));

  return (
    <Animated.View
      style={[{ width, height, borderRadius: radius, backgroundColor: Colors.white10 }, shimmer, style]}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    />
  );
};

/** Card-shaped skeleton matching AstralEventCard's footprint. */
export const SkeletonCard: React.FC<{ height?: number }> = ({ height = 320 }) => (
  <View
    style={styles.card}
    accessible
    accessibilityLabel="Loading events"
    accessibilityRole="progressbar"
  >
    <SkeletonBlock height={height} radius={Radius.card} />
    <View style={styles.metaRow}>
      <SkeletonBlock width="60%" height={18} />
      <SkeletonBlock width="30%" height={18} />
    </View>
    <SkeletonBlock width="45%" height={12} />
  </View>
);

/** Vertical list of card skeletons for a feed cold-load. */
export const SkeletonFeed: React.FC<{ count?: number; cardHeight?: number }> = ({
  count = 3,
  cardHeight = 320,
}) => (
  <View accessible accessibilityLabel="Loading events" accessibilityRole="progressbar">
    {Array.from({ length: count }).map((_, i) => (
      <SkeletonCard key={i} height={cardHeight} />
    ))}
  </View>
);

const styles = StyleSheet.create({
  card: { marginBottom: Space.lg, gap: Space.sm },
  metaRow: { flexDirection: 'row', justifyContent: 'space-between', marginTop: Space.xs },
});

export default SkeletonFeed;

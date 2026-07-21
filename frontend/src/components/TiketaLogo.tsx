// src/components/TiketaLogo.tsx
// Tiketa brand mark — an animated "walking ticket" mascot.
//
// The character is a perforated ticket body with two googly eyes, a waving
// arm, and two walking legs. Built with react-native-svg + reanimated so it
// runs on the UI thread. All looping motion is gated behind the platform
// reduced-motion preference (WCAG 2.2 SC 2.3.3 — see QA Test AC-02).

import React, { useEffect } from 'react';
import { Platform, View } from 'react-native';
import Svg, { G, Path, Ellipse, Circle } from 'react-native-svg';
import Animated, {
  useSharedValue,
  useAnimatedProps,
  withRepeat,
  withTiming,
  withSequence,
  Easing,
  useReducedMotion,
} from 'react-native-reanimated';

const AnimatedG = Animated.createAnimatedComponent(G);

export interface TiketaLogoProps {
  /** Rendered width/height in px. The mark keeps a 100:140 aspect ratio. */
  size?: number;
  /** Body fill colour. Defaults to true black to match the source mark. */
  color?: string;
  /** Disable looping motion regardless of the system setting. */
  animated?: boolean;
  /** Accessibility label for the whole mark. */
  label?: string;
}

const VB_W = 100;
const VB_H = 140;

/**
 * Ticket body outline with notched top/bottom edges (the perforated "stub"
 * silhouette from the brand illustration).
 */
const BODY_PATH =
  'M30 22 ' +
  'q3 0 3 -3 q0 -4 4 -4 q4 0 4 4 q0 3 3 3 ' + // top notches (left → right)
  'q3 0 3 -3 q0 -4 4 -4 q4 0 4 4 q0 3 3 3 ' +
  'q3 0 3 -3 q0 -4 4 -4 q4 0 4 4 q0 3 3 3 ' +
  'l4 0 q6 0 6 6 ' +
  'l0 60 q0 6 -6 6 ' + // right edge down
  'q-3 0 -3 3 q0 4 -4 4 q-4 0 -4 -4 q0 -3 -3 -3 ' + // bottom notches
  'q-3 0 -3 3 q0 4 -4 4 q-4 0 -4 -4 q0 -3 -3 -3 ' +
  'q-3 0 -3 3 q0 4 -4 4 q-4 0 -4 -4 q0 -3 -3 -3 ' +
  'l-4 0 q-6 0 -6 -6 ' +
  'l0 -60 q0 -6 6 -6 z';

export const TiketaLogo: React.FC<TiketaLogoProps> = ({
  size = 96,
  color = '#000000',
  animated = true,
  label = 'Tiketa',
}) => {
  const reduceMotion = useReducedMotion();
  const motionOn = animated && !reduceMotion;

  const wave = useSharedValue(0);   // waving arm rotation (deg)
  const legA = useSharedValue(0);   // front leg swing (deg)
  const legB = useSharedValue(0);   // back leg swing (deg)
  const bob = useSharedValue(0);    // vertical body bob (px)
  const pupil = useSharedValue(0);  // pupil drift (px)

  useEffect(() => {
    if (!motionOn) {
      // Static, friendly resting pose.
      wave.value = 12;
      legA.value = 8;
      legB.value = -8;
      bob.value = 0;
      pupil.value = 0;
      return;
    }

    const ease = Easing.inOut(Easing.quad);

    wave.value = -6;
    wave.value = withRepeat(
      withTiming(26, { duration: 420, easing: ease }),
      -1,
      true,
    );

    legA.value = -18;
    legA.value = withRepeat(withTiming(18, { duration: 360, easing: ease }), -1, true);

    legB.value = 18;
    legB.value = withRepeat(withTiming(-18, { duration: 360, easing: ease }), -1, true);

    bob.value = 0;
    bob.value = withRepeat(withTiming(-4, { duration: 360, easing: ease }), -1, true);

    pupil.value = withRepeat(
      withSequence(
        withTiming(2.5, { duration: 1400, easing: ease }),
        withTiming(-2.5, { duration: 1400, easing: ease }),
      ),
      -1,
      true,
    );
  }, [motionOn, bob, legA, legB, pupil, wave]);

  // Body + head bob.
  const bodyProps = useAnimatedProps(() => ({
    transform: [{ translateY: bob.value }],
  }));
  // Waving right arm, pivoting at the shoulder.
  const armProps = useAnimatedProps(() => ({
    transform: [{ translateX: 70 }, { translateY: 56 }, { rotate: `${wave.value}deg` }, { translateX: -70 }, { translateY: -56 }],
  }));
  const legAProps = useAnimatedProps(() => ({
    transform: [{ translateX: 42 }, { translateY: 96 }, { rotate: `${legA.value}deg` }, { translateX: -42 }, { translateY: -96 }],
  }));
  const legBProps = useAnimatedProps(() => ({
    transform: [{ translateX: 56 }, { translateY: 96 }, { rotate: `${legB.value}deg` }, { translateX: -56 }, { translateY: -96 }],
  }));
  const pupilProps = useAnimatedProps(() => ({
    transform: [{ translateX: pupil.value }],
  }));

  const stroke = { stroke: color, strokeWidth: 7, strokeLinecap: 'round' as const, fill: 'none' };

  return (
    <View
      accessible
      accessibilityRole="image"
      accessibilityLabel={label}
      {...(Platform.OS === 'web' ? {} : { importantForAccessibility: 'yes' as const })}
    >
      <Svg width={size} height={(size * VB_H) / VB_W} viewBox={`0 0 ${VB_W} ${VB_H}`}>
        {/* Legs (behind body) */}
        <AnimatedG animatedProps={legAProps}>
          <Path d="M42 96 L36 128 L30 132" {...stroke} />
        </AnimatedG>
        <AnimatedG animatedProps={legBProps}>
          <Path d="M56 96 L62 126 L70 130" {...stroke} />
        </AnimatedG>

        <AnimatedG animatedProps={bodyProps}>
          {/* Left (static) arm */}
          <Path d="M30 58 L14 64 L8 60" {...stroke} />

          {/* Ticket body */}
          <Path d={BODY_PATH} fill={color} />

          {/* Eyes */}
          <Ellipse cx={42} cy={52} rx={11} ry={13} fill="#FFFFFF" />
          <Ellipse cx={62} cy={52} rx={11} ry={13} fill="#FFFFFF" />
          <AnimatedG animatedProps={pupilProps}>
            <Circle cx={44} cy={54} r={5} fill={color} />
            <Circle cx={64} cy={54} r={5} fill={color} />
            <Circle cx={46} cy={52} r={1.6} fill="#FFFFFF" />
            <Circle cx={66} cy={52} r={1.6} fill="#FFFFFF" />
          </AnimatedG>
        </AnimatedG>

        {/* Waving right arm (on top) */}
        <AnimatedG animatedProps={armProps}>
          <Path d="M70 56 L86 44 L92 36" {...stroke} />
        </AnimatedG>
      </Svg>
    </View>
  );
};

export default TiketaLogo;

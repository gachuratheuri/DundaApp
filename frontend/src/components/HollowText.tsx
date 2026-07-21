// src/components/HollowText.tsx
// Cyber-Brutalist "Hollow / Stroke" display type — the spec's defining feature.
//
// A massive, heavily condensed, all-caps, tightly-kerned sans-serif rendered
// as an OUTLINE only (no fill). Layered behind solid text it acts as a
// typographical wireframe, pushing depth onto the Z-axis without adding
// visual mass.
//
//   - Web:    true outline via `-webkit-text-stroke` + transparent fill.
//   - Native: RN has no text-stroke primitive, so we approximate the wireframe
//             with a faint translucent fill (matches the Astral convention used
//             elsewhere) — legible as background structure, never as foreground.

import React from 'react';
import { Platform, StyleSheet, Text, type TextProps, type TextStyle } from 'react-native';

import { Colors } from '../theme/dunda';

const BRUTALIST_FONT = Platform.OS === 'web' ? 'Oswald, impact, sans-serif' : 'System';

export interface HollowTextProps extends TextProps {
  children: React.ReactNode;
  /** Display size in px. */
  size?: number;
  /** Outline width on web (px). */
  strokeWidth?: number;
  /** Outline / wireframe colour. */
  strokeColor?: string;
  style?: TextStyle | TextStyle[];
}

export const HollowText: React.FC<HollowTextProps> = ({
  children,
  size = 64,
  strokeWidth = 2,
  strokeColor = Colors.white20,
  style,
  ...rest
}) => {
  const outline =
    Platform.OS === 'web'
      ? ({
          WebkitTextStrokeWidth: strokeWidth,
          WebkitTextStrokeColor: strokeColor,
          color: 'transparent',
        } as unknown as TextStyle)
      : { color: strokeColor };

  return (
    <Text
      {...rest}
      style={[styles.base, { fontSize: size, lineHeight: size * 0.86 }, outline, style]}
    >
      {children}
    </Text>
  );
};

const styles = StyleSheet.create({
  base: {
    fontFamily: BRUTALIST_FONT,
    fontWeight: '900',
    textTransform: 'uppercase',
    letterSpacing: -2,
    textAlign: 'center',
  },
});

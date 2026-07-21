import React, { type PropsWithChildren } from 'react';
import { BlurView } from 'expo-blur';
import { LinearGradient } from 'expo-linear-gradient';
import { View, StyleSheet } from 'react-native';

// Performance rule: max 1-2 blur layers per screen
export const PrismGlassPanel = ({ children }: PropsWithChildren) => (
  <View style={styles.container} renderToHardwareTextureAndroid>
    <BlurView intensity={80} tint="dark" style={StyleSheet.absoluteFill} />
    <LinearGradient
      colors={['rgba(0,242,254,0.08)', 'rgba(255,62,108,0.08)']}
      start={{ x: 0, y: 0 }}
      end={{ x: 1, y: 1 }}
      style={StyleSheet.absoluteFill}
    />
    <View style={styles.border}>
      {children}
    </View>
  </View>
);

const styles = StyleSheet.create({
  container: { overflow: 'hidden', borderRadius: 4 },
  border: {
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.10)',
    padding: 20,
  },
});

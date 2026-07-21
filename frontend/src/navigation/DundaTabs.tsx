// src/navigation/DundaTabs.tsx
// Bottom tab navigator — glass floating pill style (DICE-inspired, darker)
// The tab bar floats above content; no harsh separator line.

import React from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { BlurView } from 'expo-blur';
import { triggerHaptic } from '../utils/haptics';
import * as Haptics from 'expo-haptics';
import { Colors, Font, Radius } from '../theme/dunda';
import { Ionicons } from '@expo/vector-icons';

export type DundaTab = 'discover' | 'tickets' | 'profile';

interface Props {
  active: DundaTab;
  onChange: (tab: DundaTab) => void;
}

const TABS: { key: DundaTab; icon: keyof typeof Ionicons.glyphMap; label: string }[] = [
  { key: 'discover', icon: 'sparkles', label: 'Discover' },
  { key: 'tickets', icon: 'ticket', label: 'Tickets' },
  { key: 'profile', icon: 'person', label: 'Profile' },
];

export const DundaTabs: React.FC<Props> = ({ active, onChange }) => (
  <View style={styles.wrapper}>
    <BlurView intensity={90} tint="dark" style={styles.bar}>
      {TABS.map((tab) => {
        const isActive = tab.key === active;
        return (
          <Pressable
            key={tab.key}
            style={styles.tab}
            onPress={() => {
              if (tab.key !== active) {
                triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
              }
              onChange(tab.key);
            }}
            accessibilityRole="tab"
            accessibilityState={{ selected: isActive }}
            accessibilityLabel={tab.label}
          >
            <Ionicons name={tab.icon} style={[styles.tabIcon, isActive && styles.tabIconActive]} />
            <Text style={[styles.tabLabel, isActive && styles.tabLabelActive]}>{tab.label}</Text>
            {isActive && <View style={styles.activeDot} />}
          </Pressable>
        );
      })}
    </BlurView>
  </View>
);

const styles = StyleSheet.create({
  wrapper: {
    position: 'absolute', bottom: 24, left: 24, right: 24, zIndex: 50,
  },
  bar: {
    flexDirection: 'row', borderRadius: Radius.xl, overflow: 'hidden',
    borderWidth: 1, borderColor: 'rgba(255,255,255,0.4)', paddingVertical: 10,
    shadowColor: '#000', shadowOffset: {width:0, height:10}, shadowOpacity: 0.8, shadowRadius: 20,
    backgroundColor: 'rgba(10,10,12,0.5)',
  },
  tab: {
    flex: 1, alignItems: 'center', justifyContent: 'center', gap: 3, paddingVertical: 4,
  },
  tabIcon: { fontSize: 20, color: Colors.periwinkle },
  tabIconActive: { color: Colors.teal },
  tabLabel: { ...Font.labelS, color: Colors.periwinkle, letterSpacing: 0.5 },
  tabLabelActive: { color: Colors.teal },
  activeDot: {
    position: 'absolute', bottom: -6, width: 4, height: 4,
    borderRadius: 2, backgroundColor: Colors.teal,
  },
});

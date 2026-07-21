import React from 'react';
import { View, Text, StyleSheet, ScrollView, StatusBar, Pressable } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Colors, Font, Space, Radius } from '../theme/dunda';
import * as Haptics from 'expo-haptics';
import { triggerHaptic } from '../utils/haptics';

export default function NotificationsScreen() {
  const router = useRouter();
  const NOTIFS = [
    { id: '1', title: 'Payment Confirmed', desc: 'M-Pesa payment confirmed for Astral Night VIP.', time: '2m ago' },
    { id: '2', title: 'Waitlist Alert', desc: '2 tickets available for NaiFest.', time: '1h ago' },
    { id: '3', title: 'Resale Success', desc: 'Your resale listing was successfully bought.', time: '1d ago' },
  ];

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar barStyle="light-content" backgroundColor={Colors.void} />
      <View style={styles.header}>
        <Pressable onPress={() => { triggerHaptic(Haptics.ImpactFeedbackStyle.Light); router.back(); }} style={styles.backBtn}>
          <Text style={styles.backText}>← Back</Text>
        </Pressable>
        <Text style={styles.title}>Notifications</Text>
      </View>
      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        {NOTIFS.map(n => (
          <View key={n.id} style={styles.card}>
            <View style={styles.cardHeader}>
              <Text style={styles.cardTitle}>{n.title}</Text>
              <Text style={styles.cardTime}>{n.time}</Text>
            </View>
            <Text style={styles.cardDesc}>{n.desc}</Text>
          </View>
        ))}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: Colors.void },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: Space.base, paddingVertical: Space.md, borderBottomWidth: 1, borderColor: Colors.white10 },
  backBtn: { paddingRight: Space.base },
  backText: { ...Font.labelL, color: Colors.teal },
  title: { ...Font.h2, color: Colors.white },
  scroll: { padding: Space.base, gap: Space.sm },
  card: { backgroundColor: Colors.surface, padding: Space.base, borderRadius: Radius.card, borderWidth: 1, borderColor: Colors.white10 },
  cardHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: Space.xs },
  cardTitle: { ...Font.h3, color: Colors.white },
  cardTime: { ...Font.labelS, color: Colors.periwinkle },
  cardDesc: { ...Font.bodyM, color: Colors.periwinkle, marginTop: Space.xs },
});

import React from 'react';
import { View, Text, StyleSheet, ScrollView, Pressable, Platform, Linking } from 'react-native';
import { API_ORIGIN } from '../constants/config';
import { useRouter } from 'expo-router';
import { BlurView } from 'expo-blur';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Colors, Space, Radius } from '../theme/dunda';
import { MaterialCommunityIcons } from '@expo/vector-icons';

export default function OrganiserLandingScreen() {
  const router = useRouter();

  const openPortal = () => {
    // In a real app, this might navigate to a webview or an external link
    // Here we'll try to open the local Phoenix backend URL
    if (Platform.OS === 'web') {
      window.location.href = `${API_ORIGIN}/portal`;
    } else {
      Linking.openURL(`${API_ORIGIN}/portal`);
    }
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} style={styles.backButton}>
          <MaterialCommunityIcons name="arrow-left" size={24} color={Colors.white} />
        </Pressable>
        <Text style={styles.headerTitle}>TIKETA FOR ORGANISERS</Text>
        <View style={{ width: 24 }} />
      </View>

      <ScrollView contentContainerStyle={styles.scrollContent} bounces={false}>
        {/* Hero Section */}
        <View style={styles.heroSection}>
          <View style={styles.badgeContainer}>
            <View style={styles.pulseDot} />
            <Text style={styles.badgeText}>LIVE IN NAIROBI</Text>
          </View>

          <Text style={styles.heroTitle}>
            SELL TICKETS.{'\n'}
            <Text style={{ color: Colors.opticCyan }}>KEEP THE REVENUE.</Text>
          </Text>

          <Text style={styles.heroSubtitle}>
            The first zero-fee ticketing platform for African nightlife. Get paid instantly via M-Pesa escrow.
          </Text>

          <Pressable style={styles.primaryCta} onPress={openPortal}>
            <Text style={styles.primaryCtaText}>OPEN ORGANISER PORTAL</Text>
            <MaterialCommunityIcons name="arrow-right" size={20} color={Colors.void} />
          </Pressable>
        </View>

        {/* Features Grid */}
        <View style={styles.featuresSection}>
          <Text style={styles.sectionTitle}>WHY CHOOSE TIKETA?</Text>

          <View style={styles.featureCard}>
            <MaterialCommunityIcons name="lightning-bolt" size={32} color={Colors.opticCyan} />
            <Text style={styles.featureTitle}>Instant M-Pesa Payouts</Text>
            <Text style={styles.featureText}>No more waiting 7 days for your money. Funds hit your Till/Paybill the moment the event successfully concludes.</Text>
          </View>

          <View style={styles.featureCard}>
            <MaterialCommunityIcons name="cash-multiple" size={32} color={Colors.acidGreen} />
            <Text style={styles.featureTitle}>Zero Setup Fees</Text>
            <Text style={styles.featureText}>You keep 100% of the ticket face value. We pass a transparent booking fee directly to the buyer.</Text>
          </View>

          <View style={styles.featureCard}>
            <MaterialCommunityIcons name="chart-line-variant" size={32} color={Colors.magenta} />
            <Text style={styles.featureTitle}>Live Escrow Telemetry</Text>
            <Text style={styles.featureText}>Watch your revenue grow in real-time. Full visibility into cart abandonments and live conversion rates.</Text>
          </View>

          <View style={styles.featureCard}>
            <MaterialCommunityIcons name="shield-lock-outline" size={32} color={Colors.gold} />
            <Text style={styles.featureTitle}>Bot & Scalper Proof</Text>
            <Text style={styles.featureText}>Cryptographic ticket vaults prevent screenshotting. Our price-capped resale market eliminates scalpers entirely.</Text>
          </View>
        </View>

        {/* Social Proof */}
        <View style={styles.socialProof}>
          <Text style={styles.socialProofText}>TRUSTED BY NAIROBI'S TOP PROMOTERS</Text>
          <View style={styles.logosRow}>
            <Text style={styles.logoText}>BLANKETS & WINE</Text>
            <Text style={styles.logoText}>THE ALCHEMIST</Text>
            <Text style={styles.logoText}>MUZE</Text>
          </View>
        </View>

        {/* Bottom Padding for scroll */}
        <View style={{ height: 100 }} />
      </ScrollView>

      {/* Floating Action Bar */}
      <BlurView intensity={80} tint="dark" style={styles.floatingActionBar}>
        <View style={styles.actionContent}>
          <View>
            <Text style={styles.actionTitle}>Ready to publish?</Text>
            <Text style={styles.actionSubtitle}>Takes less than 3 minutes.</Text>
          </View>
          <Pressable style={styles.floatingBtn} onPress={openPortal}>
            <Text style={styles.floatingBtnText}>CREATE EVENT</Text>
          </Pressable>
        </View>
      </BlurView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: Colors.voidBlack,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: Space.lg,
    paddingVertical: Space.md,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.1)',
  },
  backButton: {
    padding: Space.xs,
  },
  headerTitle: {
    color: Colors.white,
    fontFamily: Platform.OS === 'web' ? 'Oswald, impact, sans-serif' : 'System',
    fontWeight: '900',
    fontSize: 16,
    letterSpacing: 2,
  },
  scrollContent: {
    flexGrow: 1,
  },
  heroSection: {
    padding: Space.xl,
    paddingTop: Space.xxxl,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.1)',
    backgroundColor: Colors.abyss,
  },
  badgeContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(57, 255, 20, 0.1)',
    alignSelf: 'flex-start',
    paddingHorizontal: Space.sm,
    paddingVertical: Space.xs,
    borderRadius: Radius.pill,
    borderWidth: 1,
    borderColor: 'rgba(57, 255, 20, 0.2)',
    marginBottom: Space.lg,
  },
  pulseDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: Colors.acidGreen,
    marginRight: Space.sm,
  },
  badgeText: {
    color: Colors.acidGreen,
    fontFamily: Platform.OS === 'web' ? 'Inter, sans-serif' : 'System',
    fontWeight: '700',
    fontSize: 10,
    letterSpacing: 1,
  },
  heroTitle: {
    color: Colors.white,
    fontFamily: Platform.OS === 'web' ? 'Oswald, impact, sans-serif' : 'System',
    fontWeight: '900',
    fontSize: 54,
    lineHeight: 56,
    letterSpacing: -1,
    marginBottom: Space.lg,
  },
  heroSubtitle: {
    color: Colors.periwinkle,
    fontFamily: Platform.OS === 'web' ? 'Inter, sans-serif' : 'System',
    fontWeight: '500',
    fontSize: 16,
    lineHeight: 24,
    marginBottom: Space.xl,
  },
  primaryCta: {
    backgroundColor: Colors.opticCyan,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: Space.lg,
    shadowColor: Colors.opticCyan,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.4,
    shadowRadius: 10,
    elevation: 6,
  },
  primaryCtaText: {
    color: Colors.void,
    fontFamily: Platform.OS === 'web' ? 'Inter, sans-serif' : 'System',
    fontWeight: '900',
    fontSize: 14,
    letterSpacing: 2,
    marginRight: Space.sm,
  },
  featuresSection: {
    padding: Space.xl,
  },
  sectionTitle: {
    color: Colors.periwinkle,
    fontFamily: Platform.OS === 'web' ? 'Oswald, impact, sans-serif' : 'System',
    fontWeight: '900',
    fontSize: 20,
    letterSpacing: 2,
    marginBottom: Space.xl,
  },
  featureCard: {
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    padding: Space.lg,
    marginBottom: Space.md,
  },
  featureTitle: {
    color: Colors.white,
    fontFamily: Platform.OS === 'web' ? 'Inter, sans-serif' : 'System',
    fontWeight: '700',
    fontSize: 18,
    marginTop: Space.md,
    marginBottom: Space.xs,
  },
  featureText: {
    color: Colors.periwinkle,
    fontFamily: Platform.OS === 'web' ? 'Inter, sans-serif' : 'System',
    fontWeight: '400',
    fontSize: 14,
    lineHeight: 20,
  },
  socialProof: {
    padding: Space.xl,
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.1)',
  },
  socialProofText: {
    color: Colors.white40,
    fontFamily: Platform.OS === 'web' ? 'Inter, sans-serif' : 'System',
    fontWeight: '700',
    fontSize: 10,
    letterSpacing: 2,
    marginBottom: Space.lg,
  },
  logosRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    flexWrap: 'wrap',
    gap: Space.xl,
  },
  logoText: {
    color: Colors.white40,
    fontFamily: Platform.OS === 'web' ? 'Oswald, impact, sans-serif' : 'System',
    fontWeight: '700',
    fontSize: 18,
    letterSpacing: 1,
  },
  floatingActionBar: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.1)',
    paddingBottom: Platform.OS === 'ios' ? 20 : 0, // Safe area bottom
  },
  actionContent: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: Space.md,
    paddingHorizontal: Space.lg,
  },
  actionTitle: {
    color: Colors.white,
    fontFamily: Platform.OS === 'web' ? 'Inter, sans-serif' : 'System',
    fontWeight: '700',
    fontSize: 14,
  },
  actionSubtitle: {
    color: Colors.periwinkle,
    fontFamily: Platform.OS === 'web' ? 'Inter, sans-serif' : 'System',
    fontWeight: '400',
    fontSize: 12,
  },
  floatingBtn: {
    backgroundColor: Colors.white,
    paddingHorizontal: Space.lg,
    paddingVertical: Space.md,
  },
  floatingBtnText: {
    color: Colors.void,
    fontFamily: Platform.OS === 'web' ? 'Inter, sans-serif' : 'System',
    fontWeight: '900',
    fontSize: 12,
    letterSpacing: 1,
  },
});

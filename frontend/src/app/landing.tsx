import React, { useState, useEffect } from 'react';
import {
  View, Text, StyleSheet, ScrollView, Pressable, Platform, Linking,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { BlurView } from 'expo-blur';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import Animated, {
  useSharedValue, useAnimatedStyle, withRepeat, withTiming, withSequence, Easing as ReanimatedEasing, useReducedMotion
} from 'react-native-reanimated';
import { Colors, Font, Space, Radius, Gradients, Screen } from '../theme/dunda';
import { triggerHaptic } from '../utils/haptics';
import * as Haptics from 'expo-haptics';
import { TiketaLogo } from '../components/TiketaLogo';
import { API_ORIGIN } from '../constants/config';

// ── Particle Field Helper ──
const FloatingParticleField: React.FC = () => {
  return (
    <View style={[StyleSheet.absoluteFillObject, { height: Screen.height, overflow: 'hidden', zIndex: 0 }]} pointerEvents="none">
      {Array.from({ length: 20 }).map((_, i) => {
        const top = Math.random() * Screen.height;
        const left = Math.random() * Screen.width;
        const size = Math.random() * 3 + 1;
        return (
          <View
            key={i}
            style={{
              position: 'absolute',
              top,
              left,
              width: size,
              height: size,
              borderRadius: size / 2,
              backgroundColor: Colors.opticCyan,
              opacity: Math.random() * 0.3 + 0.1,
            }}
          />
        );
      })}
    </View>
  );
};

const testimonials = [
  { text: "Tiketa saved our door operations. 100% check-in speed and zero ticket fraud.", author: "Muze promoter" },
  { text: "Bought tickets in three taps using M-Pesa. Best live event checkout in Kenya.", author: "David M., Attendee" },
  { text: "Waitlist demand curves let us add a second day with confidence.", author: "Alchemist Venue Manager" }
];

export default function LandingScreen() {
  const router = useRouter();
  const [activeFaq, setActiveFaq] = useState<number | null>(null);
  const [activeTestimonial, setActiveTestimonial] = useState(0);

  // Phone drift animation
  const phoneRotateX = useSharedValue(5);
  const phoneRotateY = useSharedValue(-5);
  const reduceMotion = useReducedMotion();

  useEffect(() => {
    // WCAG 2.2 SC 2.3.3 — freeze the looping 3D transform under reduced motion (QA AC-02).
    if (reduceMotion) {
      phoneRotateX.value = withTiming(0, { duration: 0 });
      phoneRotateY.value = withTiming(0, { duration: 0 });
      return;
    }
    phoneRotateX.value = withRepeat(
      withSequence(
        withTiming(-5, { duration: 6000, easing: ReanimatedEasing.inOut(ReanimatedEasing.ease) }),
        withTiming(5, { duration: 6000, easing: ReanimatedEasing.inOut(ReanimatedEasing.ease) })
      ),
      -1,
      true
    );
    phoneRotateY.value = withRepeat(
      withSequence(
        withTiming(5, { duration: 6000, easing: ReanimatedEasing.inOut(ReanimatedEasing.ease) }),
        withTiming(-5, { duration: 6000, easing: ReanimatedEasing.inOut(ReanimatedEasing.ease) })
      ),
      -1,
      true
    );
  }, [reduceMotion, phoneRotateX, phoneRotateY]);

  const phoneAnimStyle = useAnimatedStyle(() => ({
    transform: [
      { perspective: 1000 },
      { rotateX: `${phoneRotateX.value}deg` },
      { rotateY: `${phoneRotateY.value}deg` }
    ]
  }));

  useEffect(() => {
    const interval = setInterval(() => {
      setActiveTestimonial((t) => (t + 1) % testimonials.length);
    }, 5000);
    return () => clearInterval(interval);
  }, []);

  const faqData = [
    { q: "How do I buy a ticket?", a: "1. Select your event from the Discovery feed.\n2. Choose your ticket tier (General or VIP).\n3. Enter your M-Pesa phone number.\n4. Input your PIN in the secure SIM popup to complete payment." },
    { q: "Where do I find my ticket QR code?", a: "Go to the 'Tickets' tab. Your active tickets will display in a staggered stack layout. Tap a card to reveal the cryptographic vault." },
    { q: "Do I need internet at the gate?", a: "The venue coordinator verifies device-bound proofs on its local network; a partition is explicitly degraded rather than falsely claiming global uniqueness." },
    { q: "Can I resell my ticket?", a: "Yes. Swipe left on your ticket in the Wallet and select 'Resell'. Enter your price. To prevent ticket scalping, resale prices are capped at the original face value." },
    { q: "When am I entitled to a refund?", a: "Refunds are issued automatically if the event is cancelled or rescheduled. You are also eligible if your ticket is successfully bought back by a waitlisted user." }
  ];

  return (
    <SafeAreaView style={styles.root}>
      <LinearGradient colors={Gradients.deepSpace} style={StyleSheet.absoluteFillObject} />
      <FloatingParticleField />

      <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>
        {/* ── Top Nav Header ── */}
        <View style={styles.navHeader}>
          <View style={styles.logoRow}>
            <TiketaLogo size={34} color={Colors.teal} label="Tiketa home" />
            <Text style={styles.logo}>TIKETA</Text>
          </View>
          <Pressable style={styles.navBtn} onPress={() => {
            triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
            router.push({ pathname: '/' });
          }}>
            <Text style={styles.navBtnText}>Launch App</Text>
          </Pressable>
        </View>

        {/* ── Hero Section ── */}
        <View style={styles.heroSection}>
          <View style={styles.heroLeft}>
            {/* Hollow title stack */}
            <View style={styles.hollowContainer} aria-hidden={true}>
              <Text style={styles.hollowText}>WHAT'S ON</Text>
              <Text style={styles.solidText}>WHAT'S ON</Text>
            </View>
            <Text style={styles.heroTitleSub}>IN NAIROBI</Text>
            <Text style={styles.heroSub}>
              Discover, buy, and resell tickets. M-Pesa native. Offline-resilient. No queues.
            </Text>

            <View style={styles.ctaRow}>
              <Pressable style={styles.primaryCta} onPress={() => {
                triggerHaptic(Haptics.ImpactFeedbackStyle.Medium);
                router.push({ pathname: '/' });
              }}>
                <Text style={styles.primaryCtaText}>Browse Events →</Text>
              </Pressable>
              <Pressable style={styles.secondaryCta} onPress={() => {
                triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                router.push({ pathname: '/profile' });
              }}>
                <Text style={styles.secondaryCtaText}>Start Selling</Text>
              </Pressable>
            </View>

            {/* Social Proof */}
            <Text style={styles.socialProof}>
              47,000+ Nairobians · 1,200+ events · 98% checkout success
            </Text>
          </View>

          {/* Interactive Phone Mockup */}
          {Platform.OS === 'web' && (
            <Animated.View style={[styles.phoneMockup, phoneAnimStyle]}>
              <BlurView intensity={20} tint="dark" style={styles.phoneInner}>
                <View style={styles.phoneScreen}>
                  <View style={styles.phoneNotch} />
                  <Text style={styles.phoneAppLogo}>TIKETA</Text>
                  <View style={styles.phoneEventCard}>
                    <View style={styles.phoneEventImage} />
                    <Text style={styles.phoneEventName}>BLANKETS & WINE</Text>
                    <Text style={styles.phoneEventVenue}>Ngong Racecourse</Text>
                  </View>
                  <View style={styles.phoneCtaBar}>
                    <Text style={styles.phonePrice}>KSh 2,500/=</Text>
                    <View style={styles.phoneBuyBtn}>
                      <Text style={styles.phoneBuyText}>BUY</Text>
                    </View>
                  </View>
                </View>
              </BlurView>
            </Animated.View>
          )}
        </View>

        {/* ── Partner Logo Strip ── */}
        <View style={styles.partnerStrip}>
          <Text style={styles.partnerLogo}>THE ALCHEMIST</Text>
          <Text style={styles.partnerLogo}>MUZE</Text>
          <Text style={styles.partnerLogo}>CARNIVORE</Text>
          <Text style={styles.partnerLogo}>KICC ROOFTOP</Text>
        </View>

        {/* ── How It Works ── */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>How It Works</Text>
          <View style={styles.grid}>
            {[
              { num: "01", title: "DISCOVER", desc: "Browse curated events based on your music preferences." },
              { num: "02", title: "BUY SECURELY", desc: "Checkout in three taps with direct M-Pesa STK push integration." },
              { num: "03", title: "SHOW QR", desc: "Present your rotating, offline-resilient QR ticket at the gate." }
            ].map((step) => (
              <View key={step.num} style={styles.stepCard}>
                <Text style={styles.stepNum}>{step.num}</Text>
                <Text style={styles.stepTitle}>{step.title}</Text>
                <Text style={styles.stepDesc}>{step.desc}</Text>
              </View>
            ))}
          </View>
        </View>

        {/* ── Split Panel (Attendees vs Organisers) ── */}
        <View style={styles.splitPanel}>
          <View style={styles.splitHalf}>
            <Text style={styles.splitTitle}>FOR FANS</Text>
            <Text style={styles.splitDesc}>Curated shows. Instant checkout. Safe resale capped at face value.</Text>
            <Pressable style={styles.splitCta} onPress={() => router.push({ pathname: '/' })}>
              <Text style={styles.splitCtaText}>Explore Shows</Text>
            </Pressable>
          </View>
          <View style={[styles.splitHalf, styles.splitHalfElevated]}>
            <Text style={[styles.splitTitle, { color: Colors.gold }]}>FOR PROMOTERS</Text>
            <Text style={styles.splitDesc}>Run your gate. Track real-time ticket velocity. Get paid daily via M-Pesa.</Text>
            <Pressable style={[styles.splitCta, { borderColor: Colors.gold }]} onPress={() => {
              triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
              Linking.openURL(`${API_ORIGIN}/portal`).catch((err) => console.warn('Failed to open URL', err));
            }}>
              <Text style={[styles.splitCtaText, { color: Colors.gold }]}>Start Hosting</Text>
            </Pressable>
          </View>
        </View>

        {/* ── Testimonials ── */}
        <View style={styles.testimonialSection}>
          <Text style={styles.testimonialQuotes}>“</Text>
          <Text style={styles.testimonialText}>
            {testimonials[activeTestimonial].text}
          </Text>
          <Text style={styles.testimonialAuthor}>
            — {testimonials[activeTestimonial].author}
          </Text>
        </View>

        {/* ── FAQs ── */}
        <View style={styles.faqSection}>
          <Text style={styles.sectionTitle}>Frequently Asked Questions</Text>
          {faqData.map((faq, idx) => {
            if (Platform.OS === 'web') {
              return (
                <details key={idx} style={styles.faqCard as React.CSSProperties}>
                  <summary style={styles.faqHeader as React.CSSProperties}>
                    <Text style={styles.faqQ}>{faq.q}</Text>
                  </summary>
                  <Text style={styles.faqA}>{faq.a}</Text>
                </details>
              );
            }
            return (
              <Pressable
                key={idx}
                style={styles.faqCard}
                accessibilityRole="button"
                accessibilityState={{ expanded: activeFaq === idx }}
                onPress={() => {
                  triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                  setActiveFaq(activeFaq === idx ? null : idx);
                }}
              >
                <View style={styles.faqHeader}>
                  <Text style={styles.faqQ}>{faq.q}</Text>
                  <Text style={styles.faqToggle}>{activeFaq === idx ? "−" : "+"}</Text>
                </View>
                {activeFaq === idx && (
                  <Text style={styles.faqA}>{faq.a}</Text>
                )}
              </Pressable>
            );
          })}
        </View>

        <Pressable style={{ marginTop: Space.xl, alignItems: 'center' }} onPress={() => { triggerHaptic(Haptics.ImpactFeedbackStyle.Light); router.push('/faq'); }}>
           <Text style={{ ...Font.labelL, color: Colors.teal }}>View Full FAQ & Help Center →</Text>
        </Pressable>

        <View style={{ height: 100 }} />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: Colors.void },
  scroll: { paddingHorizontal: Space.base, paddingTop: Space.sm },

  navHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: Space.md,
    borderBottomWidth: 1,
    borderColor: Colors.white10,
    marginBottom: Space.xl,
  },
  logoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  logo: {
    ...Font.displayM,
    color: Colors.white,
    letterSpacing: 2,
  },
  navBtn: {
    backgroundColor: Colors.tealDark,
    borderColor: Colors.teal,
    borderWidth: 1,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.md,
    paddingVertical: Space.sm - 2,
  },
  navBtnText: {
    ...Font.labelS,
    color: Colors.white,
  },

  heroSection: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: Space.xxl,
    minHeight: 400,
  },
  heroLeft: {
    flex: 1,
    justifyContent: 'center',
  },
  hollowContainer: {
    position: 'relative',
    height: 70,
  },
  hollowText: {
    position: 'absolute',
    left: 0,
    fontFamily: Platform.OS === 'web' ? 'Oswald, impact, sans-serif' : 'System',
    fontWeight: '900',
    fontSize: 58,
    lineHeight: 58,
    color: 'transparent',
    textShadowColor: 'rgba(255,255,255,0.2)',
    textShadowOffset: { width: 0, height: 0 },
    textShadowRadius: 2,
    transform: [{ translateX: 4 }, { translateY: -4 }],
  },
  solidText: {
    position: 'absolute',
    left: 0,
    fontFamily: Platform.OS === 'web' ? 'Oswald, impact, sans-serif' : 'System',
    fontWeight: '900',
    fontSize: 58,
    lineHeight: 58,
    color: Colors.white,
  },
  heroTitleSub: {
    ...Font.displayXL,
    fontSize: 48,
    lineHeight: 48,
    color: Colors.teal,
    marginBottom: Space.base,
  },
  heroSub: {
    ...Font.bodyL,
    color: Colors.periwinkle,
    lineHeight: 26,
    marginBottom: Space.xl,
  },
  ctaRow: {
    flexDirection: 'row',
    gap: Space.md,
    marginBottom: Space.lg,
  },
  primaryCta: {
    backgroundColor: Colors.magenta,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.xl,
    paddingVertical: Space.md,
  },
  primaryCtaText: {
    ...Font.labelL,
    color: Colors.white,
    textTransform: 'uppercase',
  },
  secondaryCta: {
    borderColor: Colors.white20,
    borderWidth: 1,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.xl,
    paddingVertical: Space.md,
  },
  secondaryCtaText: {
    ...Font.labelL,
    color: Colors.white,
    textTransform: 'uppercase',
  },
  socialProof: {
    ...Font.bodyS,
    color: Colors.periwinkle,
  },

  phoneMockup: {
    width: 260,
    height: 520,
    borderRadius: 36,
    borderWidth: 6,
    borderColor: '#222',
    overflow: 'hidden',
    marginLeft: Space.xl,
    backgroundColor: Colors.void,
  },
  phoneInner: {
    flex: 1,
  },
  phoneScreen: {
    flex: 1,
    padding: Space.base,
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  phoneNotch: {
    width: 110,
    height: 18,
    backgroundColor: '#222',
    borderBottomLeftRadius: 10,
    borderBottomRightRadius: 10,
    top: -Space.base,
  },
  phoneAppLogo: {
    ...Font.h2,
    color: Colors.teal,
    letterSpacing: 2,
    marginTop: Space.sm,
  },
  phoneEventCard: {
    width: '100%',
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: Space.sm,
  },
  phoneEventImage: {
    height: 140,
    backgroundColor: Colors.tealDark,
    borderRadius: Radius.sm,
    marginBottom: Space.sm,
  },
  phoneEventName: {
    ...Font.h3,
    color: Colors.white,
    fontSize: 16,
  },
  phoneEventVenue: {
    ...Font.bodyS,
    color: Colors.periwinkle,
  },
  phoneCtaBar: {
    flexDirection: 'row',
    width: '100%',
    justifyContent: 'space-between',
    alignItems: 'center',
    backgroundColor: Colors.depth,
    padding: Space.sm,
    borderRadius: Radius.pill,
  },
  phonePrice: {
    ...Font.labelL,
    color: Colors.white,
  },
  phoneBuyBtn: {
    backgroundColor: Colors.magenta,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.md,
    paddingVertical: Space.xs,
  },
  phoneBuyText: {
    ...Font.labelS,
    color: Colors.white,
  },

  partnerStrip: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: Space.xl,
    borderTopWidth: 1,
    borderBottomWidth: 1,
    borderColor: Colors.white10,
    marginBottom: Space.xxl,
  },
  partnerLogo: {
    ...Font.labelS,
    color: Colors.white40,
    letterSpacing: 1.5,
  },

  section: {
    marginBottom: Space.xxl,
  },
  sectionTitle: {
    ...Font.h2,
    color: Colors.white,
    marginBottom: Space.lg,
  },
  grid: {
    flexDirection: 'row',
    gap: Space.md,
  },
  stepCard: {
    flex: 1,
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: Space.lg,
    ...(Platform.OS === 'web' && { transition: 'transform 0.3s ease' } as any),
  },
  stepNum: {
    ...Font.displayXL,
    fontSize: 32,
    lineHeight: 32,
    color: Colors.teal,
    marginBottom: Space.sm,
  },
  stepTitle: {
    ...Font.h3,
    color: Colors.white,
    marginBottom: Space.xs,
  },
  stepDesc: {
    ...Font.bodyM,
    color: Colors.periwinkle,
  },

  splitPanel: {
    flexDirection: 'row',
    gap: Space.lg,
    marginBottom: Space.xxl,
  },
  splitHalf: {
    flex: 1,
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: Space.xl,
    justifyContent: 'space-between',
    minHeight: 220,
  },
  splitHalfElevated: {
    backgroundColor: Colors.abyss,
    borderColor: Colors.goldGlowSoft,
  },
  splitTitle: {
    ...Font.h2,
    color: Colors.teal,
  },
  splitDesc: {
    ...Font.bodyM,
    color: Colors.periwinkle,
    marginVertical: Space.md,
  },
  splitCta: {
    borderColor: Colors.teal,
    borderWidth: 1,
    borderRadius: Radius.pill,
    paddingVertical: Space.sm,
    alignItems: 'center',
  },
  splitCtaText: {
    ...Font.labelM,
    color: Colors.teal,
    textTransform: 'uppercase',
  },

  testimonialSection: {
    alignItems: 'center',
    paddingVertical: Space.xl,
    marginBottom: Space.xxl,
    borderBottomWidth: 1,
    borderColor: Colors.white10,
  },
  testimonialQuotes: {
    fontSize: 64,
    color: Colors.teal,
    lineHeight: 64,
  },
  testimonialText: {
    ...Font.bodyL,
    color: Colors.white,
    textAlign: 'center',
    lineHeight: 26,
    marginBottom: Space.md,
    fontStyle: 'italic',
  },
  testimonialAuthor: {
    ...Font.labelL,
    color: Colors.periwinkle,
  },

  faqSection: {
    marginBottom: Space.xxl,
  },
  faqCard: {
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    borderRadius: Radius.card,
    padding: Space.base,
    marginBottom: Space.sm,
  },
  faqHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  faqQ: {
    ...Font.labelL,
    color: Colors.white,
  },
  faqToggle: {
    ...Font.h2,
    color: Colors.teal,
  },
  faqA: {
    ...Font.bodyM,
    color: Colors.periwinkle,
    marginTop: Space.md,
    lineHeight: 20,
  },
});

// src/screens/EventDetailScreen.tsx
// Dunda "Astral Dark" — Event Detail + Checkout
//
// Design:
//   - Full-bleed hero image with scrolling parallax pull
//   - Sticky bottom bar with price + CTA (DICE checkout pattern)
//   - Glass artist/lineup section
//   - Map preview chip
//   - M-Pesa STK push trigger with loading state

import React, { useState, useEffect } from 'react';
import {
  View, Text, StyleSheet, Pressable,
  ImageBackground, StatusBar, ActivityIndicator, Platform,
  TextInput, Alert
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { BlurView } from 'expo-blur';
import Animated, {
  useSharedValue, useAnimatedStyle, interpolate, useAnimatedScrollHandler, Extrapolate,
  withRepeat, withSequence, withTiming, Easing as ReanimatedEasing
} from 'react-native-reanimated';
import { SafeAreaView } from 'react-native-safe-area-context';
import { triggerHaptic } from '../utils/haptics';
import * as Haptics from 'expo-haptics';
import { useRouter } from 'expo-router';
import { api, newIdempotencyKey } from '../api/client';
import { subscribeSettlement } from '../api/settlementSocket';
import { AstralEvent } from '../components/AstralEventCard';
import { Colors, Font, Space, Radius, Screen } from '../theme/dunda';

const HERO_H = Screen.height * 0.48;

interface Props {
  event: AstralEvent;
  onBack?: () => void;
}

const StockBar: React.FC<{ sold: number; total: number; isLow: boolean }> = ({ sold, total, isLow }) => {
  const widthVal = useSharedValue(0);

  useEffect(() => {
    widthVal.value = withTiming(sold / total, { duration: 600, easing: ReanimatedEasing.out(ReanimatedEasing.ease) });
  }, [sold, total, widthVal]);

  const animatedStyle = useAnimatedStyle(() => ({
    width: `${widthVal.value * 100}%`,
  }));

  const barColor = isLow ? Colors.magenta : Colors.opticCyan;

  return (
    <View style={styles.stockBarTrack}>
      <Animated.View style={[styles.stockBarFill, { backgroundColor: barColor }, animatedStyle]} />
    </View>
  );
};

export const EventDetailScreen: React.FC<Props> = ({ event, onBack }) => {
  const router = useRouter();
  const [checkoutState, setCheckoutState] = useState<'none' | 'confirm' | 'escrow' | 'waiting' | 'success' | 'failure' | 'pending'>('none');
  const [quantity, setQuantity] = useState(1);
  const [phoneNumber, setPhoneNumber] = useState('');
  const [selectedTierId, setSelectedTierId] = useState<string | undefined>(event.tiers?.find((tier) => tier.remaining > 0)?.id);
  const [countdown, setCountdown] = useState(300); // 5 minutes (5:00)

  useEffect(() => {
    setSelectedTierId(event.tiers?.find((tier) => tier.remaining > 0)?.id);
  }, [event.id, event.tiers]);

  useEffect(() => {
    const prefillPhone = async () => {
      try {
        const u = await api.getUser();
        if (u && u.phone) {
          let num = u.phone;
          if (num.startsWith('+254')) {
            num = num.slice(4);
          } else if (num.startsWith('254')) {
            num = num.slice(3);
          } else if (num.startsWith('0')) {
            num = num.slice(1);
          }
          setPhoneNumber(num);
        }
      } catch {}
    };
    prefillPhone();
  }, []);

  useEffect(() => {
    let timer: ReturnType<typeof setInterval>;
    if (checkoutState === 'escrow' || checkoutState === 'waiting') {
      timer = setInterval(() => {
        setCountdown((c) => (c > 0 ? c - 1 : 0));
      }, 1000);
    } else {
      setCountdown(300);
    }
    return () => clearInterval(timer);
  }, [checkoutState]);

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  const scrollY = useSharedValue(0);

  const scrollHandler = useAnimatedScrollHandler({
    onScroll: (e) => {
      scrollY.value = e.contentOffset.y;
    }
  });

  const heroStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: interpolate(scrollY.value, [0, HERO_H], [0, HERO_H * 0.4], Extrapolate.CLAMP) }],
  }));

  const headerOpacity = useAnimatedStyle(() => ({
    opacity: interpolate(scrollY.value, [HERO_H * 0.5, HERO_H * 0.8], [0, 1], Extrapolate.CLAMP),
  }));

  const handleBuy = async () => {
    triggerHaptic(Haptics.ImpactFeedbackStyle.Medium);
    const token = await api.getToken();
    if (!token) {
      Alert.alert(
        'Authentication Required',
        'You must be signed in to purchase tickets. Please navigate to the Profile tab to register or sign in.',
        [
          { text: 'Cancel', style: 'cancel' },
          { text: 'Go to Profile', onPress: () => router.push({ pathname: '/profile' }) }
        ]
      );
      return;
    }
    setCheckoutState('confirm');
  };

  const executePurchase = async () => {
    triggerHaptic(Haptics.ImpactFeedbackStyle.Heavy);

    try {
      const token = await api.getToken();
      if (!token) {
        setCheckoutState('none');
        return;
      }

      setCheckoutState('escrow');

      let formattedPhone = phoneNumber.trim();
      if (!formattedPhone.startsWith('+') && !formattedPhone.startsWith('254')) {
        if (formattedPhone.startsWith('0')) {
          formattedPhone = formattedPhone.slice(1);
        }
        formattedPhone = '+254' + formattedPhone;
      } else if (formattedPhone.startsWith('254')) {
        formattedPhone = '+' + formattedPhone;
      }

      if (!/^\+254\d{9}$/.test(formattedPhone)) throw new Error('Enter a valid Kenyan M-Pesa phone number.');

      const quote = await api.createQuote({ eventId: String(event.id), tierId: selectedTierId, quantity });
      const payment = await api.createCheckout({ quoteId: quote.quote_id, phone: formattedPhone, idempotencyKey: newIdempotencyKey() });
      const txId = payment.payment_intent_id;

      setCheckoutState('waiting');
      if (Platform.OS !== 'web') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(() => {});

      // FI-01: a WebSocket settlement channel is the primary signal; HTTP
      // polling is retained as a fallback when the socket cannot connect.
      // Tolerate delayed Daraja callbacks (up to ~2 min) before giving up.
      let settled = false;
      let attempts = 0;
      const maxAttempts = 60; // ~2 minutes
      let pollTimer: ReturnType<typeof setInterval> | undefined;
      let unsubscribe: (() => void) | undefined;

      const finish = (status: 'success' | 'failure') => {
        if (settled) return;
        settled = true;
        if (pollTimer) clearInterval(pollTimer);
        unsubscribe?.();

        if (status === 'success') {
          setCheckoutState('success');
          if (Platform.OS !== 'web') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
          setTimeout(() => {
            setCheckoutState('none');
            router.navigate('/tickets');
          }, 1500);
        } else {
          setCheckoutState('failure');
          Alert.alert('Checkout Failed', 'The M-Pesa transaction failed or timed out.');
        }
      };

      unsubscribe = subscribeSettlement(txId, token, (update) => {
        if (update.status === 'success') finish('success');
        else if (update.status === 'failure') finish('failure');
      });

      pollTimer = setInterval(async () => {
        try {
          attempts++;
          const statusRes = await api.checkoutStatus(txId);
          const status = statusRes.state;

          if (['confirmed', 'confirmed_late', 'fulfilled'].includes(status)) {
            finish('success');
          } else if (['failed', 'refunded', 'manual_review'].includes(status)) {
            finish('failure');
          } else if (attempts >= maxAttempts) {
            if (pollTimer) clearInterval(pollTimer);
            unsubscribe?.();
            setCheckoutState('pending');
          }
        } catch (err) {
          console.warn('Error polling checkout status:', err);
        }
      }, 2000);

    } catch (e: any) {
      console.error('Checkout error:', e);
      setCheckoutState('failure');
      Alert.alert('Checkout Failed', e.message || 'An error occurred during checkout. Please try again.');
    }
  };

  const selectedTier = event.tiers?.find((tier) => tier.id === selectedTierId) ?? event.tiers?.find((tier) => tier.remaining > 0);
  const selectedPriceCents = selectedTier?.price_kes ?? event.price_kes;
  const isSoldOut = selectedTier ? selectedTier.remaining === 0 : (event.sold_out || event.remaining === 0);

  const getButtonText = () => {
    return isSoldOut ? 'JOIN WAITLIST' : 'Buy with M-Pesa';
  };

  const formattedDate = new Intl.DateTimeFormat('en-KE', {
    weekday:'long', day:'numeric', month:'long', year:'numeric', hour:'2-digit', minute:'2-digit'
  }).format(new Date(event.starts_at));

  const minPrice = event.tiers && event.tiers.length > 0
    ? Math.min(...event.tiers.filter(t => t.remaining > 0).map(t => t.price_kes))
    : event.price_kes;
  const priceToUse = isFinite(minPrice) ? minPrice : event.price_kes;
  const price = `KSh ${(priceToUse / 100).toLocaleString('en-KE')}/=`;

  const [isHovered, setIsHovered] = useState(false);

  // Kinetic Spatial Floating Animation
  const floatY = useSharedValue(0);
  useEffect(() => {
    floatY.value = withRepeat(
      withSequence(
        withTiming(-20, { duration: 4000, easing: ReanimatedEasing.inOut(ReanimatedEasing.ease) }),
        withTiming(20, { duration: 4000, easing: ReanimatedEasing.inOut(ReanimatedEasing.ease) })
      ),
      -1,
      true
    );
  }, [floatY]);
  const floatStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: floatY.value }]
  }));

  return (
    <View style={styles.root}>
      <StatusBar barStyle="light-content" translucent backgroundColor="transparent" />

      {/* ── Sticky transparent back header ── */}
      {checkoutState === 'none' && (
        <View style={styles.stickyHeader}>
          <Pressable onPress={onBack} style={styles.backBtn}>
            <BlurView intensity={40} tint="dark" style={[styles.blurBtn, Platform.OS === 'web' && { backdropFilter: 'blur(24px) saturate(150%)' } as any]}>
              <Text style={styles.backIcon}>←</Text>
            </BlurView>
          </Pressable>
          <Animated.View style={[styles.stickyTitle, headerOpacity]}>
            <BlurView intensity={60} tint="dark" style={[styles.stickyBlur, Platform.OS === 'web' && { backdropFilter: 'blur(24px) saturate(150%)' } as any]}>
              <Text style={styles.stickyTitleText} numberOfLines={1}>{event.name}</Text>
            </BlurView>
          </Animated.View>
          <Pressable style={styles.backBtn}>
            <BlurView intensity={40} tint="dark" style={[styles.blurBtn, Platform.OS === 'web' && { backdropFilter: 'blur(24px) saturate(150%)' } as any]}>
              <Text style={styles.backIcon}>♡</Text>
            </BlurView>
          </Pressable>
        </View>
      )}

      <Animated.ScrollView
        onScroll={scrollHandler}
        scrollEventThrottle={16}
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.scroll}
      >
        {/* ── Cyber-Brutalist Z-Axis Hero Scene ── */}
        {Platform.OS === 'web' ? (
          <div className="cb-scene-container" style={{ height: HERO_H }}>
            <div className="cb-hollow-text-bg" dangerouslySetInnerHTML={{__html: event.name.toUpperCase().replace(' ', '<br>')}} />
            <div className="cb-iridescent-object" style={{
              backgroundImage: `linear-gradient(135deg, var(--optic-cyan), var(--deep-purple), var(--hot-pink), var(--electric-yellow)), url(${event.cover_uri})`,
              backgroundBlendMode: 'overlay',
              backgroundSize: '300% 300%, cover',
              backgroundPosition: 'center, center'
            }} />
            <div className="cb-solid-text-fg" dangerouslySetInnerHTML={{__html: event.name.toUpperCase().replace(' ', '<br>')}} />
          </div>
        ) : (
          <Animated.View style={[styles.sceneContainer, { height: HERO_H }, heroStyle]}>
             {/* LAYER 1: Background Hollow Text */}
             <Text style={styles.hollowTextBg} numberOfLines={2}>
                {event.name.toUpperCase()}
             </Text>

             {/* LAYER 2: Iridescent Object (Floating Cover Image) */}
             <Animated.View style={[styles.iridescentObject, floatStyle]}>
                <ImageBackground source={{uri: event.cover_uri}} style={StyleSheet.absoluteFillObject} imageStyle={{borderRadius: 40}}>
                   <LinearGradient colors={['#00F0FF', '#C900FF', '#FF1C5E', '#F4F800']} style={[StyleSheet.absoluteFillObject, { borderRadius: 40, opacity: 0.4 }]} start={{x:0,y:0}} end={{x:1,y:1}} />
                </ImageBackground>
             </Animated.View>

             {/* LAYER 3: Foreground Solid Text */}
             <Text style={styles.solidTextFg} numberOfLines={2}>
                {event.name.toUpperCase()}
             </Text>
          </Animated.View>
        )}

        {/* ── Body (Asymmetrical left-aligned on web) ── */}
        <View style={styles.body}>
          <View style={Platform.OS === 'web' ? { maxWidth: 600 } : {}}>

            {/* Date / Venue row */}
            <View style={styles.infoGrid}>
              <View style={styles.infoCard}>
                <Text style={styles.infoIcon}>📅</Text>
                <View>
                  <Text style={styles.infoLabel}>DATE & TIME</Text>
                  <Text style={styles.infoValue}>{formattedDate}</Text>
                </View>
              </View>
              <View style={styles.infoCard}>
                <Text style={styles.infoIcon}>📍</Text>
                <View>
                  <Text style={styles.infoLabel}>VENUE</Text>
                  <Text style={styles.infoValue}>{event.venue}</Text>
                </View>
              </View>
            </View>

            {/* About */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>About</Text>
              <Text style={styles.bodyText}>
                {event.description || 'The most beloved outdoor music experience in Nairobi returns. Sip wine, spread your blanket, and lose yourself in world-class performances under the Nairobi sky. Curated lineups, artisan food, and a community of music lovers.'}
              </Text>
            </View>

            {/* Lineup */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Lineup</Text>
              {['Sauti Sol', 'Bien', 'Nviiri the Storyteller', 'Brandy Maina'].map((artist) => (
                <Pressable key={artist} style={styles.artistRow} onPress={() => {
                  triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                  Alert.alert('Artist Profile', `View profile for ${artist}`);
                }}>
                  <View style={styles.artistAvatar}>
                    <Text style={styles.artistInitial}>{artist[0]}</Text>
                  </View>
                  <Text style={styles.artistName}>{artist}</Text>
                  <Text style={styles.artistArrow}>›</Text>
                </Pressable>
              ))}
            </View>

            {/* Social Coordination (Groups) */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Who's going?</Text>
              <View style={styles.socialCard}>
                <View style={styles.avatarsOverlap}>
                  {['J', 'A', 'M', 'K'].map((initial, i) => (
                    <View key={i} style={[styles.overlapAvatar, { left: i * 24, zIndex: 10 - i }]}>
                      <Text style={styles.overlapAvatarText}>{initial}</Text>
                    </View>
                  ))}
                  <View style={[styles.overlapAvatar, { left: 4 * 24, zIndex: 5, backgroundColor: Colors.surface, borderColor: Colors.white20 }]}>
                    <Text style={[styles.overlapAvatarText, { color: Colors.periwinkle }]}>+12</Text>
                  </View>
                </View>
                <Text style={styles.socialText}>
                  Jane, Alex, Mike, and 12 other friends are going to this show.
                </Text>

                <View style={styles.socialButtons}>
                  <Pressable style={styles.socialBtn} onPress={() => {
                    triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                    Alert.alert('Groups Chat', 'Open attendee chat group.');
                  }}>
                    <Text style={styles.socialBtnText}>💬 Groups Chat</Text>
                  </Pressable>
                  <Pressable style={[styles.socialBtn, styles.socialBtnSecondary]} onPress={() => {
                    triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                    Alert.alert('Invite Friends', 'Open share sheet.');
                  }}>
                    <Text style={styles.socialBtnTextSecondary}>🔗 Invite Friends</Text>
                  </Pressable>
                </View>
              </View>
            </View>

            {/* Ticket types */}
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>Tickets</Text>
              {(event.tiers || [{ label: event.tier_label, price_kes: event.price_kes, sold: Math.max(0, 1000 - event.remaining), total: 1000, remaining: event.remaining, vip: event.is_vip }]).map((t) => {
                const isLow = t.remaining <= 20 && t.remaining > 0;
                const formattedPrice = `KSh ${(t.price_kes / 100).toLocaleString('en-KE')}/=`;
                return (
                  <Pressable
                    key={t.id || t.label}
                    style={[styles.tierCard, t.vip ? styles.tierVip : {}, t.id === selectedTierId ? styles.tierSelected : {}]}
                    accessibilityRole="radio"
                    onPress={() => {
                      triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                      setSelectedTierId(t.id);
                    }}
                  >
                    <View style={{ flex: 1 }}>
                      <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                        {t.vip && <View style={styles.tierVipBadge}><Text style={styles.tierVipText}>VIP</Text></View>}
                        <Text style={styles.tierLabel}>{t.label}</Text>
                      </View>
                      <Text style={styles.tierRemaining}>{t.sold}/{t.total} sold</Text>
                      <StockBar sold={t.sold} total={t.total} isLow={isLow} />
                    </View>
                    <Text style={[styles.tierPrice, t.vip ? styles.tierPriceGold : {}]}>{formattedPrice}</Text>
                  </Pressable>
                );
              })}
            </View>

            <View style={{ height: 120 }} />
          </View>
        </View>
      </Animated.ScrollView>

      {/* ── Sticky CTA bar ── */}
      {checkoutState === 'none' && (
        <BlurView intensity={80} tint="dark" style={[styles.ctaBar, Platform.OS === 'web' && { backdropFilter: 'blur(24px) saturate(150%)' } as any]}>
          <SafeAreaView edges={['bottom']} style={styles.ctaInner}>
            <View>
              <Text style={styles.ctaFrom}>From</Text>
              <Text style={styles.ctaPrice}>{price}</Text>
            </View>
            <Pressable
              onHoverIn={() => setIsHovered(true)}
              onHoverOut={() => setIsHovered(false)}
              style={[
                styles.ctaBtn,
                isHovered && styles.ctaBtnHovered
              ]}
              onPress={handleBuy}
              disabled={false}
            >
              <View style={{flexDirection: 'row', alignItems: 'center', gap: Space.sm}}>
                <Text style={styles.ctaBtnText}>{getButtonText()}</Text>
              </View>
            </Pressable>
          </SafeAreaView>
        </BlurView>
      )}

      {checkoutState !== 'none' && (
        <View style={[StyleSheet.absoluteFillObject, { zIndex: 100, backgroundColor: 'rgba(0,0,0,0.85)', justifyContent: 'center', alignItems: 'center' }]}>
          <BlurView intensity={90} tint="dark" style={StyleSheet.absoluteFillObject} />

          {checkoutState === 'success' ? (
            <Animated.View style={styles.successFlash}>
              <Text style={styles.successTitle}>YOU'RE IN</Text>
              <Text style={styles.successBody}>Ticket Secured via M-Pesa</Text>
            </Animated.View>
          ) : checkoutState === 'pending' ? (
            <Animated.View style={styles.modalContent}>
              <Text style={styles.modalTitle}>Payment Still Processing</Text>
              <Text style={styles.modalBody}>We cannot confirm the provider response yet. Do not pay again. Check your Wallet later; the server will reconcile this payment.</Text>
              <Pressable style={styles.confirmBtn} onPress={() => setCheckoutState('none')}>
                <Text style={styles.confirmBtnText}>Close</Text>
              </Pressable>
            </Animated.View>
          ) : (
            <View style={[styles.modalContent, checkoutState === 'failure' && styles.failurePulse]}>
              {checkoutState === 'confirm' && (
                <>
                  {event.sold_out ? (
                    <>
                      <Text style={styles.modalTitle}>Join Waitlist</Text>
                      <Text style={styles.modalBody}>Tickets are currently sold out. We will notify you instantly and auto-charge payment if a ticket becomes available.</Text>

                      <View style={styles.stepper}>
                        <Pressable
                          style={styles.stepBtn}
                          onPress={() => {
                            triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                            setQuantity((q) => Math.max(1, q - 1));
                          }}
                        >
                          <Text style={styles.stepBtnText}>−</Text>
                        </Pressable>
                        <Text style={styles.stepValue}>{quantity}</Text>
                        <Pressable
                          style={styles.stepBtn}
                          onPress={() => {
                            triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                            setQuantity((q) => q + 1);
                          }}
                        >
                          <Text style={styles.stepBtnText}>+</Text>
                        </Pressable>
                      </View>

                      <Text style={styles.modalBody}>Confirm your M-Pesa phone number</Text>
                      <View style={styles.phoneInputWrapper}>
                        <Text style={styles.phonePrefix}>+254</Text>
                        <TextInput
                          style={styles.phoneInput}
                          keyboardType="phone-pad"
                          value={phoneNumber}
                          onChangeText={setPhoneNumber}
                        />
                      </View>

                      <Pressable style={[styles.confirmBtn, { backgroundColor: Colors.teal }]} onPress={() => {
                        Alert.alert('Waitlist unavailable', 'This build cannot create a durable waitlist entry. No payment was taken.');
                        setCheckoutState('none');
                      }}>
                        <Text style={[styles.confirmBtnText, { color: Colors.void }]}>Close</Text>
                      </Pressable>

                      <Pressable style={styles.cancelLink} onPress={() => setCheckoutState('none')}>
                        <Text style={styles.cancelLinkText}>Cancel</Text>
                      </Pressable>
                    </>
                  ) : (
                    <>
                      <Text style={styles.modalTitle}>Select Tickets</Text>
                  <Text style={styles.modalBody}>How many spots should we hold for you?</Text>

                  <View style={styles.stepper}>
                    <Pressable
                      style={styles.stepBtn}
                      onPress={() => {
                        triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                        setQuantity((q) => Math.max(1, q - 1));
                      }}
                    >
                      <Text style={styles.stepBtnText}>−</Text>
                    </Pressable>
                    <Text style={styles.stepValue}>{quantity}</Text>
                    <Pressable
                      style={styles.stepBtn}
                      onPress={() => {
                        triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                        setQuantity((q) => q + 1);
                      }}
                    >
                      <Text style={styles.stepBtnText}>+</Text>
                    </Pressable>
                  </View>

                  <Text style={styles.modalBody}>Confirm your M-Pesa phone number</Text>
                  <View style={styles.phoneInputWrapper}>
                    <Text style={styles.phonePrefix}>+254</Text>
                    <TextInput
                      style={styles.phoneInput}
                      keyboardType="phone-pad"
                      value={phoneNumber}
                      onChangeText={setPhoneNumber}
                    />
                  </View>

                  <Text style={styles.totalText}>
                    Total: KSh {((selectedPriceCents * quantity) / 100).toLocaleString('en-KE')}/=
                  </Text>

                  <Pressable style={styles.confirmBtn} onPress={executePurchase}>
                    <Text style={styles.confirmBtnText}>Confirm & Pay via M-Pesa</Text>
                  </Pressable>

                  <Pressable style={styles.cancelLink} onPress={() => setCheckoutState('none')}>
                    <Text style={styles.cancelLinkText}>Cancel</Text>
                  </Pressable>
                </>
              )}
            </>
          )}

              {checkoutState === 'escrow' && (
                <>
                  <Text style={styles.modalTitle}>Holding Spot</Text>
                  <Text style={styles.modalBody}>We are holding your ticket. Completing reservation...</Text>

                  <View style={styles.countdownRing}>
                    <Text style={styles.countdownRingText}>{formatTime(countdown)}</Text>
                  </View>

                  <Text style={[styles.modalBody, { color: Colors.opticCyan }]}>
                    ✓ Inventory locked in Redis escrow
                  </Text>
                </>
              )}

              {checkoutState === 'waiting' && (
                <>
                  <Text style={styles.modalTitle}>M-Pesa STK Push</Text>
                  <Text style={styles.modalBody}>Check your phone — enter your M-Pesa PIN to complete the purchase.</Text>

                  <View style={styles.checklist}>
                    <View style={styles.checkItem}>
                      <View style={[styles.checkIndicator, styles.checkIndicatorActive]}>
                        <Text style={styles.checkIndicatorText}>✓</Text>
                      </View>
                      <Text style={styles.checkLabel}>1. Reserved Spot ({formatTime(countdown)})</Text>
                    </View>
                    <View style={styles.checkItem}>
                      <View style={[styles.checkIndicator, { borderColor: Colors.opticCyan }]}>
                        <ActivityIndicator size="small" color={Colors.opticCyan} />
                      </View>
                      <Text style={[styles.checkLabel, styles.checkLabelPending]}>2. Verifying PIN callback...</Text>
                    </View>
                    <View style={styles.checkItem}>
                      <View style={styles.checkIndicator}>
                        <Text style={styles.checkIndicatorText}> </Text>
                      </View>
                      <Text style={[styles.checkLabel, styles.checkLabelPending]}>3. Confirming Settlement</Text>
                    </View>
                  </View>

                  <Text style={[styles.modalBody, { fontSize: 12, marginTop: Space.base }]}>
                    Prompt not appearing? We'll check automatically in 30 seconds.
                  </Text>
                </>
              )}

              {checkoutState === 'failure' && (
                <>
                  <Text style={[styles.modalTitle, { color: Colors.magenta }]}>Haikufanikiwa</Text>
                  <Text style={styles.modalBody}>M-Pesa payment failed or was cancelled by the user.</Text>

                  <Pressable style={styles.confirmBtn} onPress={() => setCheckoutState('confirm')}>
                    <Text style={styles.confirmBtnText}>Retry Checkout</Text>
                  </Pressable>

                  <Pressable style={styles.cancelLink} onPress={() => setCheckoutState('none')}>
                    <Text style={styles.cancelLinkText}>Close</Text>
                  </Pressable>
                </>
              )}
            </View>
          )}
        </View>
      )}
    </View>
  );
};

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: Colors.void },
  scroll: {},
  stickyHeader: {
    position: 'absolute', top: 0, left: 0, right: 0, zIndex: 40,
    flexDirection: 'row', alignItems: 'flex-end',
    paddingTop: 50, paddingHorizontal: Space.base, paddingBottom: Space.sm, gap: Space.sm,
  },
  backBtn: { },
  blurBtn: { width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  backIcon: { color: Colors.white, fontSize: 20 },
  stickyTitle: { flex: 1, overflow: 'hidden', borderRadius: Radius.pill },
  stickyBlur: { paddingHorizontal: Space.md, paddingVertical: Space.sm, overflow: 'hidden', alignItems: 'center' },
  stickyTitleText: { ...Font.labelL, color: Colors.white },
  sceneContainer: {
    position: 'relative',
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    overflow: 'hidden',
    backgroundColor: Colors.void,
  },
  hollowTextBg: {
    position: 'absolute',
    fontFamily: Platform.OS === 'web' ? 'Oswald, impact, sans-serif' : 'System',
    fontWeight: '900',
    fontSize: Platform.OS === 'web' ? 120 : 60,
    textTransform: 'uppercase',
    letterSpacing: -2,
    lineHeight: Platform.OS === 'web' ? 100 : 54,
    textAlign: 'center',
    zIndex: 1,
    color: 'rgba(255,255,255,0.1)', // Fallback if webkit text stroke fails
  },
  iridescentObject: {
    position: 'absolute',
    width: 280,
    height: 280,
    borderRadius: 40,
    zIndex: 2,
    boxShadow: Platform.OS === 'web' ? '0 0 80px rgba(201, 0, 255, 0.35), inset 0 0 40px rgba(0, 240, 255, 0.5), inset 20px 20px 60px rgba(255, 255, 255, 0.4)' : undefined,
    shadowColor: Colors.purple, shadowOffset: {width:0, height:0}, shadowOpacity: 0.5, shadowRadius: 30, // Native fallback
  },
  solidTextFg: {
    position: 'absolute',
    fontFamily: Platform.OS === 'web' ? 'Oswald, impact, sans-serif' : 'System',
    fontWeight: '900',
    fontSize: Platform.OS === 'web' ? 120 : 60,
    textTransform: 'uppercase',
    letterSpacing: -2,
    lineHeight: Platform.OS === 'web' ? 100 : 54,
    textAlign: 'center',
    color: Colors.white,
    zIndex: 3,
    textShadowColor: 'rgba(2, 2, 2, 0.9)',
    textShadowOffset: { width: 0, height: 10 },
    textShadowRadius: 30,
  },
  body: {
    backgroundColor: Colors.void, padding: Space.base, marginTop: -Space.xl,
    borderTopLeftRadius: Radius.xl, borderTopRightRadius: Radius.xl
  },
  secondaryTextSection: {
    marginBottom: Space.xl,
    marginTop: Space.md,
    alignItems: 'flex-start',
  },
  secondaryText: {
    fontFamily: 'System', // Fallback for Inter
    fontWeight: '300',
    fontSize: 18,
    color: Colors.periwinkle, // Periwinkle accent from spec
    lineHeight: 28,
  },
  infoGrid: { flexDirection: 'row', gap: Space.base, marginBottom: Space.xl },
  infoCard: { flex: 1, backgroundColor: Colors.surface, padding: Space.base, borderRadius: Radius.card, borderWidth: 1, borderColor: Colors.glassBorder, gap: Space.xs },
  infoIcon: { fontSize: 22 },
  infoLabel: { ...Font.labelS, color: Colors.periwinkle, marginBottom: 2 },
  infoValue: { ...Font.bodyM, color: Colors.white },
  section: { marginBottom: Space.xl },
  sectionTitle: { ...Font.h3, color: Colors.white, marginBottom: Space.md },
  bodyText: { ...Font.bodyM, color: Colors.periwinkle, lineHeight: 24 },
  artistRow: { flexDirection:'row', alignItems:'center', gap: Space.md, paddingVertical: Space.sm, borderBottomWidth:1, borderBottomColor: Colors.white10 },
  artistAvatar: { width:40, height:40, borderRadius:20, backgroundColor: Colors.surface, alignItems:'center', justifyContent:'center', borderWidth:1, borderColor: Colors.teal },
  artistInitial: { ...Font.labelL, color: Colors.teal },
  artistName: { ...Font.bodyM, color: Colors.white, flex:1 },
  artistArrow: { color: Colors.periwinkle, fontSize:20 },
  tierCard: { flexDirection:'row', alignItems:'center', backgroundColor: Colors.surface, borderRadius: Radius.md, padding: Space.base, marginBottom: Space.sm, borderWidth:1, borderColor: 'rgba(255,255,255,0.4)' },
  tierSelected: { borderColor: Colors.teal, borderWidth: 2 },
  tierVip: { borderColor: Colors.gold, backgroundColor: Colors.abyss },
  tierVipBadge: { backgroundColor: Colors.goldGlowSoft, borderWidth:1, borderColor: Colors.goldMid, borderRadius: Radius.xs, paddingHorizontal: Space.xs, paddingVertical: 2, marginRight: Space.sm },
  tierVipText: { ...Font.labelS, color: Colors.gold },
  tierLabel: { ...Font.labelL, color: Colors.white, marginBottom: 2 },
  tierRemaining: { ...Font.bodyS, color: Colors.periwinkle },
  tierPrice: { ...Font.h3, color: Colors.teal },
  tierPriceGold: { color: Colors.gold },
  ctaBar: { position:'absolute', bottom:0, left:0, right:0, borderTopWidth:1, borderTopColor: Colors.glassBorder, overflow:'hidden', backgroundColor: Colors.glass },
  ctaInner: { flexDirection:'row', alignItems:'center', justifyContent:'space-between', paddingHorizontal: Space.base, paddingTop: Space.base },
  ctaFrom: { ...Font.labelS, color: Colors.periwinkle },
  ctaPrice: { ...Font.h2, color: Colors.white },
  ctaBtn: {
    backgroundColor: Colors.magenta,
    paddingVertical: Space.sm + 2, paddingHorizontal: Space.xl,
    borderRadius: Radius.xs, // sharper button
    shadowColor: Colors.magenta, shadowOffset: {width:0, height:4}, shadowOpacity: 0.6, shadowRadius: 10,
    ...(Platform.OS === 'web' && { transition: 'all 0.4s cubic-bezier(0.16, 1, 0.3, 1)' } as any),
  },
  ctaBtnHovered: {
    borderColor: Colors.teal, // Optic Cyan
    boxShadow: `0 0 12px ${Colors.tealGlow}` as any,
    transform: [{ scale: 1.02 }],
  },
  ctaBtnLoading: { opacity: 0.9, backgroundColor: Colors.surface, borderWidth: 1, borderColor: Colors.magenta },
  ctaBtnText: { ...Font.labelL, color: Colors.white, letterSpacing: 0.5 },

  // Social
  socialCard: {
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: Space.base,
    marginBottom: Space.md,
  },
  avatarsOverlap: {
    flexDirection: 'row',
    height: 40,
    marginBottom: Space.sm,
    position: 'relative',
  },
  overlapAvatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: Colors.tealDark,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: Colors.void,
    position: 'absolute',
  },
  overlapAvatarText: {
    ...Font.labelS,
    color: Colors.white,
  },
  socialText: {
    ...Font.bodyM,
    color: Colors.periwinkle,
    marginBottom: Space.base,
  },
  socialButtons: {
    flexDirection: 'row',
    gap: Space.sm,
  },
  socialBtn: {
    flex: 1,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.white10,
    borderRadius: Radius.pill,
    height: 40,
    alignItems: 'center',
    justifyContent: 'center',
  },
  socialBtnSecondary: {
    borderColor: Colors.white20,
  },
  socialBtnText: {
    ...Font.labelM,
    color: Colors.white,
  },
  socialBtnTextSecondary: {
    ...Font.labelM,
    color: Colors.periwinkle,
  },

  // Stock Bars
  stockBarTrack: {
    height: 6,
    backgroundColor: Colors.white10,
    borderRadius: 3,
    marginTop: Space.sm,
    overflow: 'hidden',
  },
  stockBarFill: {
    height: '100%',
    borderRadius: 3,
  },

  // Modal checkout
  modalCentered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: Space.xl,
  },
  modalContent: {
    width: '100%',
    maxWidth: 400,
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: Space.xl,
    alignItems: 'center',
    overflow: 'hidden',
    position: 'relative',
  },
  modalTitle: {
    ...Font.h2,
    color: Colors.white,
    marginBottom: Space.md,
  },
  modalBody: {
    ...Font.bodyM,
    color: Colors.periwinkle,
    textAlign: 'center',
    marginBottom: Space.lg,
  },
  stepper: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Space.lg,
    marginVertical: Space.md,
  },
  stepBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: Colors.depth,
    borderWidth: 1,
    borderColor: Colors.white10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  stepBtnText: {
    ...Font.h2,
    color: Colors.white,
  },
  stepValue: {
    ...Font.h1,
    color: Colors.white,
    minWidth: 40,
    textAlign: 'center',
  },
  phoneInputWrapper: {
    width: '100%',
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.depth,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.base,
    height: 50,
    borderWidth: 1,
    borderColor: Colors.white10,
    marginBottom: Space.lg,
  },
  phonePrefix: {
    ...Font.h3,
    color: Colors.white,
    marginRight: Space.xs,
  },
  phoneInput: {
    flex: 1,
    ...Font.h3,
    color: Colors.white,
  },
  totalText: {
    ...Font.h2,
    color: Colors.gold,
    marginBottom: Space.lg,
  },
  confirmBtn: {
    width: '100%',
    backgroundColor: Colors.magenta,
    borderRadius: Radius.pill,
    height: 50,
    alignItems: 'center',
    justifyContent: 'center',
  },
  confirmBtnText: {
    ...Font.labelL,
    color: Colors.white,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  cancelLink: {
    marginTop: Space.base,
  },
  cancelLinkText: {
    ...Font.bodyS,
    color: Colors.periwinkle,
  },

  // Escrow state
  countdownRing: {
    width: 120,
    height: 120,
    borderRadius: 60,
    borderWidth: 4,
    borderColor: Colors.opticCyan,
    alignItems: 'center',
    justifyContent: 'center',
    marginVertical: Space.lg,
  },
  countdownRingText: {
    ...Font.displayM,
    color: Colors.opticCyan,
  },

  // Checklist
  checklist: {
    width: '100%',
    gap: Space.sm,
    marginVertical: Space.md,
  },
  checkItem: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Space.md,
    backgroundColor: Colors.depth,
    borderRadius: Radius.sm,
    padding: Space.base,
    borderWidth: 1,
    borderColor: Colors.white05,
    width: '100%',
  },
  checkIndicator: {
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: Colors.white20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkIndicatorActive: {
    backgroundColor: Colors.success,
    borderColor: Colors.success,
  },
  checkIndicatorText: {
    ...Font.labelM,
    color: Colors.white,
  },
  checkLabel: {
    ...Font.labelL,
    color: Colors.white,
  },
  checkLabelPending: {
    color: Colors.periwinkle,
  },

  // Success
  successFlash: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: Colors.success,
    alignItems: 'center',
    justifyContent: 'center',
    zIndex: 200,
  },
  successTitle: {
    ...Font.displayL,
    color: Colors.void,
    letterSpacing: 2,
    marginBottom: Space.sm,
  },
  successBody: {
    ...Font.h2,
    color: Colors.void,
  },

  // Failure
  failurePulse: {
    borderWidth: 2,
    borderColor: Colors.magenta,
  },
});

// src/screens/TicketVaultScreen.tsx
// Dunda "Astral Dark" — Cryptographic QR Vault
//
// Visual language:
//   - Void black full-bleed background (Image 2: palace on void)
//   - The QR code is the throne — dead center, maximum size
//   - Prismatic aurora gradient animates perpetually around the QR border
//     (Image 3: crystal energy, Image 5: prismatic explosion)
//   - Gold details for VIP tier (Image 2: staircase gold)
//   - Crystal glass metadata panel (Image 4: white glass towers)
//   - Device-proof countdown arc: real-time, 30-second window
//   - Admitted state: full-bleed scan-green flash (Image 3: aurora)

import React, { useEffect } from 'react';
import {
  View, Text, StyleSheet, ScrollView, Platform,
  Pressable, StatusBar, ActivityIndicator, AppState, TextInput
} from 'react-native';
import Animated, {
  useSharedValue, useAnimatedStyle, useAnimatedProps, withTiming, withRepeat,
  withSequence, interpolate, withSpring, Easing as RNEasing, runOnJS,
  FadeIn, FadeOut
} from 'react-native-reanimated';
import { Gesture, GestureDetector } from 'react-native-gesture-handler';
import { LinearGradient } from 'expo-linear-gradient';
import { BlurView } from 'expo-blur';
import QRCode from 'react-native-qrcode-svg';
import { SafeAreaView } from 'react-native-safe-area-context';
import Svg, { Circle } from 'react-native-svg';
import { triggerHaptic } from '../utils/haptics';
import * as Haptics from 'expo-haptics';
import { bindTicketDevice, useDeviceBoundQr } from '../hooks/useDeviceBoundQr';
import type { DeviceSigner } from '../security/ticketCredential';
import { api } from '../api/client';
import { Colors, Font, Space, Radius, Glow, Screen, Gradients } from '../theme/dunda';
import { TiketaLogo } from '../components/TiketaLogo';
import { Ionicons } from '@expo/vector-icons';

interface TicketData {
  id:         string;
  event_id:   string;
  event_name: string;
  venue:      string;
  date_label: string;
  tier_label: string;
  is_vip:     boolean;
  holder:     string;
  jwt:        string;
  face_value_kes?: number;
  protocol_version?: number;
  credential_public_key?: string | null;
  credential_valid_until?: string | null;
  credential_epoch?: number;
  is_scanned: boolean;
  resale_status?: 'none' | 'pending' | 'sold' | 'expired' | 'withdrawn' | 'review';
}


// ── Device-proof countdown ring ──────────────────────────────────────────────
const RING_R = 16;
const RING_C = 2 * Math.PI * RING_R;

const AnimatedCircle = Animated.createAnimatedComponent(Circle);

const CountdownRing: React.FC<{ seconds: number }> = ({ seconds }) => {
  const progress = useSharedValue(1);
  useEffect(() => {
    progress.value = withTiming(seconds / 30, { duration: 1000, easing: RNEasing.linear });
  }, [seconds, progress]);
  const animatedCircleProps = useAnimatedProps(() => ({
    strokeDashoffset: RING_C * (1 - progress.value),
  }));
  const color = seconds > 10 ? Colors.teal : seconds > 5 ? Colors.gold : Colors.magenta;
  return (
    <View style={{ position: 'absolute', top: -20, right: -20, width: 48, height: 48, alignItems: 'center', justifyContent: 'center' }}>
      <Svg width="48" height="48" viewBox="0 0 36 36">
        <Circle
          cx="18"
          cy="18"
          r={RING_R}
          fill="none"
          stroke="rgba(255,255,255,0.06)"
          strokeWidth="3"
        />
        <AnimatedCircle
          cx="18"
          cy="18"
          r={RING_R}
          fill="none"
          stroke={color}
          strokeWidth="3"
          strokeDasharray={RING_C}
          animatedProps={animatedCircleProps}
          strokeLinecap="round"
          transform="rotate(-90 18 18)"
        />
      </Svg>
      <View style={{ position: 'absolute', width: 48, height: 48, alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ ...Font.monoS, color, fontSize: 12, fontWeight: '700' }}>{seconds}</Text>
      </View>
    </View>
  );
};

// ── Aurora Border Animation ───────────────────────────────────────────────────
const AuroraBorder: React.FC<{ size: number }> = ({ size }) => {
  const rotation = useSharedValue(0);
  useEffect(() => {
    rotation.value = withRepeat(withTiming(360, { duration: 4000, easing: RNEasing.linear }), -1, false);
  }, [rotation]);
  const rotStyle = useAnimatedStyle(() => ({ transform: [{ rotate: `${rotation.value}deg` }] }));
  return (
    <Animated.View style={[{
      position: 'absolute', width: size + 6, height: size + 6,
      top: -3, left: -3, borderRadius: Radius.card + 3, // using Chroma-Noir 16px base radius
      overflow: 'hidden',
    }, rotStyle]}>
      {Platform.OS === 'web' ? (
        <View style={{
          width: '100%', height: '100%',
          backgroundImage: 'radial-gradient(circle at 50% 50%, #FF1C5E, #8A2BE2, #00F0FF, #020202)',
          backgroundSize: '200% 200%'
        }} />
      ) : (
        <LinearGradient
          colors={Gradients.aurora}
          style={{ width: '100%', height: '100%' }}
          start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }}
        />
      )}
    </Animated.View>
  );
};

interface Props {
  ticketId?: string;
  onBack?: () => void;
}

// ── Main Screen ───────────────────────────────────────────────────────────────
export const TicketVaultScreen: React.FC<Props> = ({ ticketId, onBack }) => {
  const [ticket, setTicket] = React.useState<TicketData | null>(null);
  const [loading, setLoading] = React.useState(true);
  const [binding, setBinding] = React.useState(false);

  // Robust ticket fetching with AppState (foreground refetch) for real-time gate syncing
  useEffect(() => {
    let mounted = true;

    const fetchTicketData = () => {
      api.get('/tickets').then(res => {
        if (!mounted) return;
        const ticketList: TicketData[] = res.data || [];
        if (ticketList.length > 0) {
          const found = ticketId ? ticketList.find(t => t.id === ticketId) : null;
          setTicket(found || ticketList[0]);
        } else {
          setTicket(null);
        }
      }).catch(e => {
        if (!mounted) return;
        console.warn("Failed to fetch tickets", e);
        setTicket(null);
      }).finally(() => {
        if (mounted) setLoading(false);
      });
    };

    // Initial fetch
    fetchTicketData();

    // Refetch on app foreground
    const subscription = AppState.addEventListener('change', nextAppState => {
      if (nextAppState === 'active') {
        fetchTicketData();
      }
    });

    return () => {
      mounted = false;
      subscription.remove();
    };
  }, [ticketId]);

  const admitted = ticket?.is_scanned ?? false;
  const computedQrSize = Screen.width - Space.base * 2 - Space.xl * 2;
  const qrSize   = Math.min(computedQrSize, 280);
  const [showResaleModal, setShowResaleModal] = React.useState(false);
  const [askingPrice, setAskingPrice] = React.useState('');
  const { qrPayload, secondsRemaining, reason: credentialReason } = useDeviceBoundQr(ticket);
  const bindCurrentDevice = async () => {
    if (!ticket || binding) return;
    const signer = (globalThis as typeof globalThis & { __DUNDA_DEVICE_SIGNER__?: DeviceSigner }).__DUNDA_DEVICE_SIGNER__;
    if (!signer) { alert('Secure device key support is unavailable on this build.'); return; }
    setBinding(true);
    try {
      const response = await bindTicketDevice(api, ticket.id, signer);
      const bound = response?.data;
      setTicket({ ...ticket, protocol_version: bound.protocol_version, credential_public_key: bound.credential_public_key, credential_epoch: bound.credential_epoch, jwt: bound.jwt });
    } catch (error) {
      alert(error instanceof Error ? error.message : 'Unable to bind this device');
    } finally {
      setBinding(false);
    }
  };

  // Admitted flash
  const admitOpacity = useSharedValue(admitted ? 1 : 0);
  useEffect(() => {
    if (admitted) admitOpacity.value = withSequence(
      withTiming(1, { duration: 400 }),
      withTiming(0.5, { duration: 600 }),
    );
  }, [admitted, admitOpacity]);
  const admitStyle = useAnimatedStyle(() => ({ opacity: admitOpacity.value }));

  // Entry shimmer on mount
  const entryY = useSharedValue(60);
  const entryO = useSharedValue(0);
  useEffect(() => {
    entryY.value = withSpring(0, { damping: 16, stiffness: 180 });
    entryO.value = withTiming(1, { duration: 500 });

    // Simulate auto-brightness boost on mount
    console.log("[TicketVault] Boosting screen brightness to 100%");
    return () => {
      console.log("[TicketVault] Restoring screen brightness to default");
    };
  }, [entryO, entryY]);
  const entryStyle = useAnimatedStyle(() => ({ transform: [{ translateY: entryY.value }], opacity: entryO.value }));

  // 3D Tilt for QR Vault
  const qrRotateX = useSharedValue(0);
  const qrRotateY = useSharedValue(0);
  const qrAnimStyle = useAnimatedStyle(() => ({
    transform: [
      { perspective: 1000 },
      { rotateX: `${qrRotateX.value}deg` },
      { rotateY: `${qrRotateY.value}deg` }
    ],
  }));

  return (
    <View style={styles.root}>
      <StatusBar barStyle="light-content" backgroundColor={Colors.void} />

      {/* Admitted overlay — full-bleed green */}
      {admitted && (
        <Animated.View style={[StyleSheet.absoluteFillObject, styles.admitOverlay, admitStyle]}>
          <LinearGradient colors={[Colors.scanGlow, Colors.void]} style={StyleSheet.absoluteFillObject} />
          <Text style={styles.admitText}>✓ ADMITTED</Text>
        </Animated.View>
      )}

      {/* Rejected overlay — full-bleed magenta */}
      <SafeAreaView style={{ flex: 1 }}>
        <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>

          {/* ── Header ── */}
          <View style={styles.headerRow}>
            <Pressable style={styles.backBtn} onPress={() => {
              triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
              if (onBack) onBack();
            }}>
              <Text style={styles.backText}>← Wallet</Text>
            </Pressable>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: Space.xs }}>
              <TiketaLogo size={20} color={Colors.teal} label="Tiketa" />
              <Text style={styles.headerTitle}>My Ticket</Text>
            </View>
            <Pressable style={styles.shareBtn} onPress={() => triggerHaptic(Haptics.ImpactFeedbackStyle.Light)}>
              <Text style={styles.shareIcon}>⬆</Text>
            </Pressable>
          </View>

          {/* ── Ticket Card ── */}
          {loading ? (
             <ActivityIndicator color={Colors.teal} style={{marginTop: Space.xl}} />
          ) : ticket ? (
             <Animated.View style={[styles.ticketCard, entryStyle, ticket.is_vip ? Glow.goldLg : Glow.tealSm]}>

            {/* VIP prism gradient top edge */}
            {ticket.is_vip && (
              <LinearGradient colors={Gradients.vipGold} style={styles.vipEdge} start={{x:0,y:0}} end={{x:1,y:0}} />
            )}

            {/* Event metadata */}
            <View style={styles.eventMeta}>
              {ticket.is_vip && (
                <View style={styles.vipChip}>
                  <Text style={styles.vipChipText}><Ionicons name="sparkles" size={12} color={Colors.gold} /> VIP</Text>
                </View>
              )}
              <Text style={styles.eventName}>{ticket.event_name}</Text>
              <Text style={styles.venueLine}>📍 {ticket.venue}</Text>
              <View style={styles.metaRow}>
                <View style={styles.metaItem}>
                  <Text style={styles.metaLabel}>DATE & TIME</Text>
                  <Text style={styles.metaValue}>{ticket.date_label}</Text>
                </View>
                <View style={styles.metaDivider} />
                <View style={styles.metaItem}>
                  <Text style={styles.metaLabel}>TIER</Text>
                  <Text style={[styles.metaValue, ticket.is_vip ? styles.metaGold : {}]}>{ticket.tier_label}</Text>
                </View>
                <View style={styles.metaDivider} />
                <View style={styles.metaItem}>
                  <Text style={styles.metaLabel}>HOLDER</Text>
                  <Text style={styles.metaValue}>{ticket.holder}</Text>
                </View>
              </View>
            </View>

            {/* Resale Status Badge (if applicable) */}
            {ticket.resale_status && ticket.resale_status !== 'none' && (
              <View style={styles.resaleBadge}>
                <Text style={styles.resaleBadgeText}>Resale Status: {ticket.resale_status.toUpperCase()}</Text>
              </View>
            )}

            {/* Ticket tear line */}
            <View style={styles.tearLine}>
              <View style={styles.tearCircleL} />
              <View style={styles.tearDash} />
              <View style={styles.tearCircleR} />
            </View>

            {/* QR Vault */}
            <View style={styles.qrSection}>
              <GestureDetector gesture={Gesture.Pan().minDistance(0)
                .onBegin(() => {
                  'worklet';
                  runOnJS(triggerHaptic)(Haptics.ImpactFeedbackStyle.Light);
                })
                .onUpdate((e) => {
                  'worklet';
                  qrRotateX.value = interpolate(e.y, [0, qrSize], [15, -15], 'clamp');
                  qrRotateY.value = interpolate(e.x, [0, qrSize], [-15, 15], 'clamp');
                })
                .onFinalize(() => {
                  'worklet';
                  qrRotateX.value = withSpring(0);
                  qrRotateY.value = withSpring(0);
                })}>
                <Animated.View style={[styles.qrWrapper, { width: qrSize, height: qrSize }, qrAnimStyle]}>
                  {/* Animated aurora border */}
                  <AuroraBorder size={qrSize} />

                  {/* QR frosted container */}
                  <View style={[styles.qrInner, { width: qrSize, height: qrSize, borderRadius: Radius.card }]}>
                    {qrPayload ? (
                      <QRCode value={qrPayload} size={qrSize - 40} backgroundColor={Colors.white} color={Colors.void} quietZone={10} />
                    ) : (
                      <View style={{ padding: Space.base, alignItems: 'center' }}>
                        <Text style={styles.credentialUnavailable}>SECURE CREDENTIAL INACTIVE</Text>
                        <Text style={styles.credentialReason}>{credentialReason || 'Ticket credentials are unavailable offline.'}</Text>
                        {ticket.protocol_version !== 2 && (
                          <Pressable style={styles.bindButton} onPress={() => void bindCurrentDevice()} disabled={binding}>
                            <Text style={styles.bindButtonText}>{binding ? 'Binding…' : 'Bind this device securely'}</Text>
                          </Pressable>
                        )}
                      </View>
                    )}
                  </View>

                  {/* Live device-proof countdown */}
                  <CountdownRing seconds={secondsRemaining} />
                </Animated.View>
              </GestureDetector>

              {/* Refresh countdown */}
              <View style={styles.proofRow}>
                <View style={styles.proofDot} />
                <Text style={styles.proofLabel}>{qrPayload ? `Device proof refreshes in ${secondsRemaining}s` : 'No usable credential'}</Text>
                <View style={[styles.proofDot, { backgroundColor: Colors.magenta }]} />
              </View>
            </View>

            {/* Ticket ID */}
            <View style={styles.ticketFooter}>
              <View style={{ flex: 1 }}>
                <Text style={styles.ticketIdLabel}>TICKET ID</Text>
                <Text style={styles.ticketIdValue}>{ticket.id}</Text>
              </View>
              {(!ticket.resale_status || ticket.resale_status === 'none') && !ticket.is_scanned && (
                 <Pressable style={styles.resellBtn} onPress={() => setShowResaleModal(true)}>
                   <Text style={styles.resellBtnText}>Sell Ticket</Text>
                 </Pressable>
              )}
            </View>

          </Animated.View>
          ) : null}

          {/* ── Info Banner ── */}
          {Platform.OS === 'ios' ? (
            <BlurView intensity={24} tint="dark" style={styles.infoBanner}>
              <View style={StyleSheet.absoluteFill}>
                 <View style={{ flex: 1, backgroundColor: Colors.glass }} />
              </View>
              <Text style={styles.infoIcon}>🔐</Text>
              <Text style={styles.infoText}>This QR code rotates automatically. Screenshots will not work at the gate.</Text>
            </BlurView>
          ) : (
            <View style={[styles.infoBanner, { backgroundColor: 'rgba(26, 27, 35, 0.85)', borderColor: 'rgba(255, 255, 255, 0.1)' }]}>
              <Text style={styles.infoIcon}>🔐</Text>
              <Text style={styles.infoText}>This QR code rotates automatically. Screenshots will not work at the gate.</Text>
            </View>
          )}

          <View style={{ height: 100 }} />
        </ScrollView>
      </SafeAreaView>

      {/* Resale Price Cap Modal */}
      {showResaleModal && (
         <View style={[StyleSheet.absoluteFillObject, { zIndex: 200, backgroundColor: 'rgba(0,0,0,0.8)', justifyContent: 'flex-end' }]}>
            <Animated.View style={styles.resaleSheet} entering={FadeIn} exiting={FadeOut}>
               <Text style={styles.sheetTitle}>Resell Your Ticket</Text>
               <Text style={styles.sheetDesc}>Set an asking price at or below the immutable purchase face value.</Text>
               <View style={styles.priceInputWrapper}>
                  <Text style={styles.pricePrefix}>KSh</Text>
                  <TextInput
                    style={styles.priceValue}
                    keyboardType="number-pad"
                    value={askingPrice}
                    onChangeText={setAskingPrice}
                    placeholder={ticket?.face_value_kes ? String(ticket.face_value_kes / 100) : 'Unavailable'}
                    placeholderTextColor={Colors.periwinkle}
                    accessibilityLabel="Resale asking price in Kenyan shillings"
                  />
                  <Text style={styles.pricePrefix}>/=</Text>
               </View>
               <Pressable style={styles.sheetBtn} onPress={async () => {
                  try {
                    if (ticket) {
                      const amountKes = Number(askingPrice);
                      const askingPriceCents = Math.round(amountKes * 100);
                      if (!Number.isSafeInteger(askingPriceCents) || askingPriceCents < 0 || ticket.face_value_kes == null || askingPriceCents > ticket.face_value_kes) {
                        throw new Error('Enter a price no greater than the original face value.');
                      }
                      await api.post('/resale/listings', { ticket_id: ticket.id, asking_price_kes: askingPriceCents });
                      setTicket({...ticket, resale_status: 'pending'});
                    }
                  } catch (e: any) {
                    alert(e.message || "Failed to list ticket");
                    return;
                  }
                  setShowResaleModal(false);
                  if (Platform.OS !== 'web') Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
               }}>
                  <Text style={styles.sheetBtnText}>Confirm Listing</Text>
               </Pressable>
               <Pressable style={styles.sheetBtnSecondary} onPress={() => setShowResaleModal(false)}>
                  <Text style={styles.sheetBtnSecondaryText}>Cancel</Text>
               </Pressable>
               <View style={styles.resaleFaq}>
                 <Text style={styles.resaleFaqText}>Resale Rules & Anti-Fraud Guarantee</Text>
               </View>
            </Animated.View>
         </View>
      )}

    </View>
  );
};

const styles = StyleSheet.create({
  root:  { flex: 1, backgroundColor: Colors.void },
  scroll: { paddingHorizontal: Space.base, paddingTop: Space.sm },

  admitOverlay: { ...StyleSheet.absoluteFillObject, zIndex: 100, alignItems: 'center', justifyContent: 'center' },
  admitText:    { ...Font.displayXL, color: Colors.scanGreen, letterSpacing: 4, textShadowColor: Colors.scanGlow, textShadowOffset: {width:0,height:0}, textShadowRadius: 30 },

  headerRow:   { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: Space.base },
  backBtn:     { padding: Space.sm },
  backText:    { ...Font.bodyM, color: Colors.teal },
  headerTitle: { ...Font.h3, color: Colors.white },
  shareBtn:    { padding: Space.sm, backgroundColor: Colors.surface, borderRadius: Radius.sm, borderWidth:1, borderColor: Colors.glassBorder },
  shareIcon:   { color: Colors.periwinkle, fontSize: 16 },

  ticketCard: {
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    marginBottom: Space.base,
  },
  vipEdge: { height: 3, width: '100%' },

  eventMeta: { padding: Space.base },
  vipChip: {
    backgroundColor: Colors.goldGlowSoft, borderWidth:1, borderColor: Colors.goldMid,
    borderRadius: Radius.pill, paddingHorizontal: Space.sm, paddingVertical: 3,
    alignSelf: 'flex-start', marginBottom: Space.sm,
  },
  vipChipText: { ...Font.labelS, color: Colors.gold },
  eventName:   { ...Font.h1, color: Colors.white, marginBottom: Space.xs },
  venueLine:   { ...Font.bodyS, color: Colors.periwinkle, marginBottom: Space.base },
  metaRow:     { flexDirection: 'row', alignItems: 'center' },
  metaItem:    { flex: 1, alignItems: 'center' },
  metaLabel:   { ...Font.labelS, color: Colors.periwinkle, marginBottom: 3 },
  metaValue:   { ...Font.labelL, color: Colors.white },
  metaGold:    { color: Colors.gold },
  metaDivider: { width: 1, height: 32, backgroundColor: Colors.white10 },

  tearLine:    { flexDirection: 'row', alignItems: 'center', marginVertical: 0 },
  tearCircleL: { width: 20, height: 20, borderRadius: 10, backgroundColor: Colors.void, marginLeft: -10 },
  tearDash:    { flex: 1, height: 1, borderStyle: 'dashed', borderWidth: 1, borderColor: Colors.white20, marginHorizontal: Space.xs },
  tearCircleR: { width: 20, height: 20, borderRadius: 10, backgroundColor: Colors.void, marginRight: -10 },

  qrSection:  { alignItems: 'center', padding: Space.xl },
  qrWrapper:  { position: 'relative', alignItems: 'center', justifyContent: 'center' },
  qrInner:    { backgroundColor: Colors.white, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },

  proofRow:   { flexDirection: 'row', alignItems: 'center', gap: Space.sm, marginTop: Space.base },
  proofDot:   { width: 6, height: 6, borderRadius: 3, backgroundColor: Colors.teal },
  proofLabel: { ...Font.labelM, color: Colors.periwinkle },
  credentialUnavailable: { ...Font.labelM, color: Colors.magenta, textAlign: 'center', letterSpacing: 1 },
  credentialReason: { ...Font.bodyS, color: Colors.periwinkle, textAlign: 'center', marginTop: Space.sm },
  bindButton: { marginTop: Space.md, backgroundColor: Colors.teal, borderRadius: Radius.pill, paddingHorizontal: Space.base, paddingVertical: Space.sm },
  bindButtonText: { ...Font.labelM, color: Colors.void },

  ticketFooter: { alignItems: 'center', paddingVertical: Space.md, borderTopWidth: 1, borderTopColor: Colors.white10 },
  ticketIdLabel: { ...Font.labelS, color: Colors.periwinkle, marginBottom: 3 },
  ticketIdValue: { ...Font.monoS, color: Colors.periwinkle, letterSpacing: 2 },

  infoBanner: {
    flexDirection: 'row', alignItems: 'center', gap: Space.sm,
    borderRadius: Radius.card, padding: Space.base,
    borderWidth: 1, borderColor: Colors.glassBorder, overflow: 'hidden',
  },
  infoIcon: { fontSize: 18 },
  infoText: { ...Font.bodyS, color: Colors.periwinkle, flex: 1 },

  resaleBadge: { backgroundColor: Colors.surface, borderWidth: 1, borderColor: Colors.teal, borderRadius: Radius.sm, paddingVertical: Space.sm, alignItems: 'center', marginHorizontal: Space.base },
  resaleBadgeText: { ...Font.labelS, color: Colors.teal },
  resellBtn: { backgroundColor: Colors.surface, borderWidth: 1, borderColor: Colors.white20, borderRadius: Radius.pill, paddingHorizontal: Space.base, paddingVertical: Space.sm },
  resellBtnText: { ...Font.labelS, color: Colors.white },

  resaleSheet: { backgroundColor: Colors.void, borderTopLeftRadius: Radius.xl, borderTopRightRadius: Radius.xl, padding: Space.xl, borderWidth: 1, borderColor: Colors.glassBorder },
  sheetTitle: { ...Font.h2, color: Colors.white, marginBottom: Space.sm },
  sheetDesc: { ...Font.bodyS, color: Colors.periwinkle, marginBottom: Space.xl },
  priceInputWrapper: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', backgroundColor: Colors.surface, borderRadius: Radius.card, paddingVertical: Space.lg, marginBottom: Space.xl, borderWidth: 1, borderColor: Colors.white10 },
  pricePrefix: { ...Font.h3, color: Colors.periwinkle, marginRight: Space.sm },
  priceValue: { ...Font.displayL, color: Colors.white },
  sheetBtn: { backgroundColor: Colors.magenta, borderRadius: Radius.pill, paddingVertical: Space.md, alignItems: 'center', marginBottom: Space.md },
  sheetBtnText: { ...Font.labelL, color: Colors.white },
  sheetBtnSecondary: { backgroundColor: 'transparent', borderRadius: Radius.pill, paddingVertical: Space.md, alignItems: 'center', borderWidth: 1, borderColor: Colors.white10, marginBottom: Space.lg },
  sheetBtnSecondaryText: { ...Font.labelL, color: Colors.white },
  resaleFaq: { alignItems: 'center', borderTopWidth: 1, borderTopColor: Colors.white10, paddingTop: Space.md },
  resaleFaqText: { ...Font.labelS, color: Colors.teal },
  rejectOverlay: { ...StyleSheet.absoluteFillObject, zIndex: 100, alignItems: 'center', justifyContent: 'center' },
  rejectText: { ...Font.displayXL, color: Colors.magenta, letterSpacing: 4 },
  rejectHelpBtn: { marginTop: Space.xl, backgroundColor: Colors.magenta, borderRadius: Radius.pill, paddingHorizontal: Space.xl, paddingVertical: Space.md },
  rejectHelpBtnText: { ...Font.labelL, color: Colors.white },
  walletBtnRow: { flexDirection: 'row', gap: Space.sm, paddingHorizontal: Space.base, paddingBottom: Space.base },
  walletBtn: { flex: 1, backgroundColor: '#000', borderWidth: 1, borderColor: Colors.white20, borderRadius: Radius.sm, height: 44, alignItems: 'center', justifyContent: 'center' },
  walletBtnGoogle: { backgroundColor: '#111' },
  walletBtnText: { ...Font.labelM, color: Colors.white },
  simRow: { flexDirection: 'row', gap: Space.sm, marginTop: Space.md, paddingHorizontal: Space.base },
  simBtn: { flex: 1, backgroundColor: Colors.surface, borderWidth: 1, borderColor: Colors.success, borderRadius: Radius.pill, height: 44, alignItems: 'center', justifyContent: 'center' },
  simBtnReject: { borderColor: Colors.magenta },
  simBtnText: { ...Font.labelM, color: Colors.white, fontSize: 11 },
  passGeneratingOverlay: { zIndex: 300, backgroundColor: 'rgba(0,0,0,0.9)', alignItems: 'center', justifyContent: 'center' },
  passGeneratingText: { ...Font.h3, color: Colors.white, marginBottom: Space.xs },
  passGeneratingSub: { ...Font.bodyS, color: Colors.teal },
});

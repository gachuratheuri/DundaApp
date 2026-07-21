// src/app/(tabs)/tickets.tsx
// Dunda "Astral Dark" — Ticket Wallet List
//
// Shows all owned tickets as pressable cards.
// Tapping a card reveals the full TicketVaultScreen inline.
// Empty state prompts the user to browse events.

import React, { useState } from 'react';
import {
  View, Text, StyleSheet, ScrollView, Pressable, StatusBar, Modal, TextInput,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { TicketVaultScreen } from '../../screens/TicketVaultScreen';
import { Colors, Font, Space, Radius, Glow } from '../../theme/dunda';
import { Ionicons } from '@expo/vector-icons';
import { triggerHaptic } from '../../utils/haptics';
import * as Haptics from 'expo-haptics';
import { RequireAuth } from '../../components/RequireAuth';

type Tab = 'upcoming' | 'past' | 'resale' | 'waitlist';

interface TicketRecord {
  id: string;
  event_name: string;
  venue: string;
  date_label: string;
  tier: string;
  status: 'active' | 'pending' | 'attended' | 'resale_pending';
  price_kes?: number;
  position?: number;
  probability?: string;
  is_vip?: boolean;
}

// ── Helpers ──────────────────────────────────────────────────────────────────
const isVipTier = (tier: string): boolean =>
  tier?.toUpperCase().includes('VIP') || false;

const statusColor = (status: TicketRecord['status']): string =>
  status === 'active' ? Colors.success : Colors.warning;

const statusLabel = (status: TicketRecord['status']): string =>
  status === 'active' ? 'Active' : 'Pending';

// ── Custom Hook for Resilient Fetching (Stale-While-Revalidate) ──
function useTickets() {
  const [tickets, setTickets] = useState<TicketRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  React.useEffect(() => {
    let mounted = true;
    const fetchTickets = async () => {
      try {
        const { api } = await import('../../api/client');
        const res = await api.get('/tickets');
        const freshTickets = Array.isArray(res.data) ? res.data : [];
        if (mounted) setTickets(freshTickets);
      } catch (err) {
        if (mounted) {
          setTickets([]);
          setError(err instanceof Error ? err : new Error('Unable to load tickets'));
        }
      } finally {
        if (mounted) setLoading(false);
      }
    };

    fetchTickets();
    return () => { mounted = false; };
  }, []);

  return { tickets, loading, error };
}

// ── Component ────────────────────────────────────────────────────────────────
export default function TicketsScreen() {
  const router = useRouter();
  const [selectedTicketId, setSelectedTicketId] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<Tab>('upcoming');
  const [reviewTicketId, setReviewTicketId] = useState<string | null>(null);

  const { tickets, loading, error } = useTickets();

  // ── Detail view (TicketVaultScreen) ──
  if (selectedTicketId !== null) {
    return (
      <View style={styles.root}>
        <StatusBar barStyle="light-content" backgroundColor={Colors.void} />
        <SafeAreaView style={styles.safeArea} edges={['top']}>
          {/* Back bar */}
          <View style={styles.detailHeader}>
            <Pressable
              style={styles.backBtn}
              onPress={() => setSelectedTicketId(null)}
            >
              <Text style={styles.backText}>← My Tickets</Text>
            </Pressable>
          </View>
        </SafeAreaView>

        {/* Full TicketVaultScreen */}
        <View style={styles.vaultContainer}>
          <TicketVaultScreen ticketId={selectedTicketId} onBack={() => setSelectedTicketId(null)} />
        </View>
      </View>
    );
  }

  const getActiveTickets = () => {
    switch (activeTab) {
      case 'upcoming': return tickets.filter(t => t.status === 'active');
      case 'past': return tickets.filter(t => t.status === 'attended');
      case 'resale': return tickets.filter(t => t.status === 'resale_pending');
      case 'waitlist': return tickets.filter(t => t.status === 'pending');
      default: return [];
    }
  };

  const activeTickets = getActiveTickets();

  // ── List / Empty view ──
  return (
    <RequireAuth>
    <View style={styles.root}>
      <StatusBar barStyle="light-content" backgroundColor={Colors.void} />
      <SafeAreaView style={styles.safeArea} edges={['top']}>
        {/* Header */}
        <View style={styles.header}>
          <Text style={styles.title}>My Tickets</Text>
          <Text style={styles.subtitle}>Cryptographic Wallet</Text>
        </View>

        {/* Tab Switcher */}
        <View style={styles.tabBar}>
          {(['upcoming', 'past', 'resale', 'waitlist'] as Tab[]).map((tab) => (
            <Pressable
              key={tab}
              style={[styles.tabItem, activeTab === tab && styles.tabItemActive]}
              onPress={() => {
                triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                setActiveTab(tab);
              }}
            >
              <Text style={[styles.tabItemText, activeTab === tab && styles.tabItemTextActive]}>
                {tab.toUpperCase()}
              </Text>
            </Pressable>
          ))}
        </View>

        {loading ? (
          <ScrollView
            contentContainerStyle={styles.listContent}
            showsVerticalScrollIndicator={false}
          >
            {Array.from({ length: 3 }).map((_, idx) => (
              <View
                key={`skeleton_${idx}`}
                style={[
                  styles.card,
                  { opacity: 0.15 + (0.1 * idx), height: 120, justifyContent: 'center' }
                ]}
              >
                <View style={{ width: '60%', height: 16, backgroundColor: Colors.white, borderRadius: 4, marginBottom: 8, opacity: 0.5 }} />
                <View style={{ width: '80%', height: 12, backgroundColor: Colors.white, borderRadius: 4, marginBottom: 12, opacity: 0.3 }} />
                <View style={{ width: '30%', height: 16, backgroundColor: Colors.white, borderRadius: 4, opacity: 0.4 }} />
              </View>
            ))}
          </ScrollView>
        ) : activeTickets.length === 0 ? (
          /* ── Empty state ── */
          <View style={styles.emptyContainer}>
            <Ionicons name="ticket-outline" style={styles.emptyIcon} />
            <Text style={styles.emptyTitle}>No tickets yet</Text>
            <Text style={styles.emptyBody}>
              {error ? 'Tickets are unavailable while offline. Reconnect to refresh your wallet.' : 'Browse events to get started'}
            </Text>
            <Pressable
              style={styles.browseBtn}
              onPress={() => router.push({ pathname: '/' })}
            >
              <Text style={styles.browseBtnText}>Browse Events</Text>
            </Pressable>
          </View>
        ) : (
          /* ── Ticket list ── */
          <ScrollView
            contentContainerStyle={styles.listContent}
            showsVerticalScrollIndicator={false}
          >
            {activeTickets.map((ticket, index) => {
              const vip = isVipTier(ticket.tier);
              const cardOffset = index * 12; // staggered offset
              return (
                <Pressable
                  key={ticket.id}
                  style={({ pressed }) => [
                    styles.card,
                    vip && styles.cardVip,
                    pressed && styles.cardPressed,
                    { transform: [{ translateY: cardOffset }] }
                  ]}
                  onPress={() => {
                    if (activeTab === 'upcoming') {
                      setSelectedTicketId(ticket.id);
                    }
                  }}
                >
                  {/* Top row: event name + status dot */}
                  <View style={styles.cardTopRow}>
                    <Text style={styles.cardEventName} numberOfLines={1}>
                      {ticket.event_name}
                    </Text>
                    {activeTab === 'upcoming' && (
                      <View style={styles.statusGroup}>
                        <View
                          style={[
                            styles.statusDot,
                            { backgroundColor: statusColor(ticket.status as any) },
                          ]}
                        />
                        <Text
                          style={[
                            styles.statusText,
                            { color: statusColor(ticket.status as any) },
                          ]}
                        >
                          {statusLabel(ticket.status as any)}
                        </Text>
                      </View>
                    )}
                  </View>

                  {/* Venue + date */}
                  <Text style={styles.cardVenueLine}>
                    📍 {ticket.venue}  ·  {ticket.date_label}
                  </Text>

                  {/* Resale Info */}
                  {activeTab === 'resale' && (
                    <View style={styles.resaleDetails}>
                      <Text style={styles.resalePriceText}>
                        Listed Price: KSh {((ticket.price_kes || 0) / 100).toLocaleString('en-KE')}/=
                      </Text>
                      <View style={styles.resaleBadge}>
                        <Text style={styles.resaleBadgeText}>LISTING: PENDING</Text>
                      </View>
                    </View>
                  )}

                  {/* Waitlist Info */}
                  {activeTab === 'waitlist' && (
                    <View style={styles.waitlistDetails}>
                      <Text style={styles.waitlistPosText}>
                        Queue Position: #{ticket.position}
                      </Text>
                      <Text style={styles.waitlistProbText}>
                        Probability: {ticket.probability}
                      </Text>
                    </View>
                  )}

                  {/* Bottom row: tier badge + QR icon */}
                  <View style={styles.cardBottomRow}>
                    <View
                      style={[
                        styles.tierBadge,
                        vip && styles.tierBadgeVip,
                      ]}
                    >
                      <Text
                        style={[
                          styles.tierBadgeText,
                          vip && styles.tierBadgeTextVip,
                        ]}
                      >
                        {vip ? <Ionicons name="sparkles" size={10} color={Colors.gold} /> : null}
                        {vip ? ' ' : ''}{ticket.tier}
                      </Text>
                    </View>

                    {activeTab === 'past' && (
                      <Pressable
                        style={styles.reviewBtn}
                        onPress={() => setReviewTicketId(ticket.id)}
                      >
                        <Text style={styles.reviewBtnText}>★ Leave Review</Text>
                      </Pressable>
                    )}

                    {activeTab === 'upcoming' && (
                      <View style={styles.qrIconBox}>
                        <Ionicons name="qr-code" style={styles.qrIconText} />
                      </View>
                    )}
                  </View>
                </Pressable>
              );
            })}

            {/* Bottom spacing for tab bar */}
            <View style={{ height: 150 }} />
          </ScrollView>
        )}
      </SafeAreaView>

      {/* Review Modal */}
      {reviewTicketId && (
        <Modal transparent animationType="fade" visible={true} onRequestClose={() => setReviewTicketId(null)}>
          <View style={styles.modalOverlay}>
            <View style={styles.reviewModal}>
              <Text style={styles.reviewTitle}>How was the event?</Text>
              <Text style={styles.reviewSubtitle}>Your feedback helps organizers improve future events.</Text>

              <View style={styles.starRow}>
                {[1, 2, 3, 4, 5].map((star) => (
                  <Pressable key={star} onPress={() => triggerHaptic(Haptics.ImpactFeedbackStyle.Light)}>
                    <Ionicons name="star" style={styles.starIcon} />
                  </Pressable>
                ))}
              </View>

              <TextInput
                style={styles.reviewInput}
                placeholder="Share your experience (optional)"
                placeholderTextColor={Colors.white20}
                multiline
              />

              <Pressable style={styles.reviewSubmitBtn} onPress={() => {
                triggerHaptic(Haptics.ImpactFeedbackStyle.Heavy);
                alert("Thank you for your feedback!");
                setReviewTicketId(null);
              }}>
                <Text style={styles.reviewSubmitText}>Submit Review</Text>
              </Pressable>

              <Pressable style={styles.reviewCancelBtn} onPress={() => setReviewTicketId(null)}>
                <Text style={styles.reviewCancelText}>Cancel</Text>
              </Pressable>
            </View>
          </View>
        </Modal>
      )}
    </View>
    </RequireAuth>
  );
}

// ── Styles ────────────────────────────────────────────────────────────────────
const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: Colors.void,
  },
  safeArea: {
    flex: 1,
  },

  // Header
  header: {
    paddingHorizontal: Space.base,
    paddingTop: Space.lg,
    paddingBottom: Space.md,
  },
  title: {
    ...Font.h1,
    color: Colors.white,
  },
  subtitle: {
    ...Font.labelM,
    color: Colors.periwinkle,
    marginTop: Space.xs,
  },

  // List
  listContent: {
    paddingHorizontal: Space.base,
    paddingTop: Space.sm,
  },

  // Card
  card: {
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: Space.base,
    marginBottom: Space.md,
    ...Glow.cardBase,
  },
  cardVip: {
    borderColor: Colors.goldGlowSoft,
    borderWidth: 1,
    ...Glow.goldSm,
  },
  cardPressed: {
    opacity: 0.85,
  },

  // Card top row
  cardTopRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: Space.xs,
  },
  cardEventName: {
    ...Font.h3,
    color: Colors.white,
    flex: 1,
    marginRight: Space.sm,
  },
  statusGroup: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Space.xs,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  statusText: {
    ...Font.labelS,
  },

  // Card venue line
  cardVenueLine: {
    ...Font.bodyS,
    color: Colors.periwinkle,
    marginBottom: Space.md,
  },

  // Card bottom row
  cardBottomRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  tierBadge: {
    backgroundColor: Colors.white05,
    borderWidth: 1,
    borderColor: Colors.white10,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.sm,
    paddingVertical: 4,
  },
  tierBadgeVip: {
    backgroundColor: Colors.goldGlowSoft,
    borderColor: Colors.goldMid,
  },
  tierBadgeText: {
    ...Font.labelS,
    color: Colors.white60,
  },
  tierBadgeTextVip: {
    color: Colors.gold,
  },
  qrIconBox: {
    width: 32,
    height: 32,
    borderRadius: Radius.sm,
    backgroundColor: Colors.white05,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    alignItems: 'center',
    justifyContent: 'center',
  },
  qrIconText: {
    color: Colors.periwinkle,
    fontSize: 16,
  },

  // Empty state
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: Space.xxl,
  },
  emptyIcon: {
    fontSize: 64,
    color: Colors.white10,
    marginBottom: Space.xl,
  },
  emptyTitle: {
    ...Font.h2,
    color: Colors.white,
    marginBottom: Space.sm,
  },
  emptyBody: {
    ...Font.bodyM,
    color: Colors.periwinkle,
    textAlign: 'center',
    marginBottom: Space.xxl,
  },
  browseBtn: {
    backgroundColor: Colors.magenta,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.xl,
    paddingVertical: Space.md,
  },
  browseBtnText: {
    ...Font.labelL,
    color: Colors.white,
  },

  // Detail view (back bar + vault)
  detailHeader: {
    paddingHorizontal: Space.base,
    paddingVertical: Space.md,
  },
  backBtn: {
    alignSelf: 'flex-start',
    paddingVertical: Space.xs,
  },
  backText: {
    ...Font.bodyM,
    color: Colors.teal,
  },
  vaultContainer: {
    flex: 1,
  },
  tabBar: {
    flexDirection: 'row',
    paddingHorizontal: Space.base,
    marginBottom: Space.md,
    gap: Space.sm,
  },
  tabItem: {
    paddingVertical: Space.sm,
    paddingHorizontal: Space.md,
    borderRadius: Radius.pill,
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
  },
  tabItemActive: {
    backgroundColor: Colors.tealDark,
    borderColor: Colors.teal,
  },
  tabItemText: {
    ...Font.labelS,
    color: Colors.periwinkle,
  },
  tabItemTextActive: {
    color: Colors.white,
  },
  resaleDetails: {
    marginTop: Space.xs,
    marginBottom: Space.sm,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  resalePriceText: {
    ...Font.bodyM,
    color: Colors.white,
  },
  resaleBadge: {
    backgroundColor: 'rgba(0, 240, 255, 0.1)',
    borderWidth: 1,
    borderColor: Colors.opticCyan,
    paddingHorizontal: Space.sm,
    paddingVertical: 2,
    borderRadius: Radius.sm,
  },
  resaleBadgeText: {
    ...Font.labelS,
    color: Colors.opticCyan,
    fontSize: 10,
  },
  waitlistDetails: {
    marginTop: Space.xs,
    marginBottom: Space.sm,
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  waitlistPosText: {
    ...Font.bodyM,
    color: Colors.white,
  },
  waitlistProbText: {
    ...Font.bodyM,
    color: Colors.success,
  },
  reviewBtn: {
    backgroundColor: Colors.surface,
    borderWidth: 1,
    borderColor: Colors.gold,
    paddingHorizontal: Space.md,
    paddingVertical: Space.sm - 2,
    borderRadius: Radius.pill,
  },
  reviewBtnText: {
    ...Font.labelS,
    color: Colors.gold,
  },
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.8)',
    justifyContent: 'center',
    padding: Space.xl,
  },
  reviewModal: {
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    padding: Space.xl,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    alignItems: 'center',
  },
  reviewTitle: {
    ...Font.h2,
    color: Colors.white,
    marginBottom: Space.xs,
  },
  reviewSubtitle: {
    ...Font.bodyS,
    color: Colors.periwinkle,
    textAlign: 'center',
    marginBottom: Space.xl,
  },
  starRow: {
    flexDirection: 'row',
    gap: Space.md,
    marginBottom: Space.xl,
  },
  starIcon: {
    fontSize: 40,
    color: Colors.gold,
  },
  reviewInput: {
    width: '100%',
    height: 100,
    backgroundColor: Colors.depth,
    borderRadius: Radius.sm,
    borderWidth: 1,
    borderColor: Colors.white10,
    padding: Space.md,
    color: Colors.white,
    ...Font.bodyM,
    textAlignVertical: 'top',
    marginBottom: Space.xl,
  },
  reviewSubmitBtn: {
    backgroundColor: Colors.teal,
    width: '100%',
    paddingVertical: Space.md,
    borderRadius: Radius.pill,
    alignItems: 'center',
    marginBottom: Space.md,
  },
  reviewSubmitText: {
    ...Font.labelL,
    color: Colors.void,
  },
  reviewCancelBtn: {
    paddingVertical: Space.sm,
  },
  reviewCancelText: {
    ...Font.labelM,
    color: Colors.periwinkle,
  },
});

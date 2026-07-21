import React, { useState } from 'react';
import {
  View, Text, StyleSheet, ScrollView, Pressable, TextInput, StatusBar,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Colors, Font, Space, Radius } from '../theme/dunda';
import { triggerHaptic } from '../utils/haptics';
import * as Haptics from 'expo-haptics';

interface FAQItem {
  q: string;
  a: string;
}

const BUYING_FAQS: FAQItem[] = [
  { q: "How do I buy a ticket?", a: "1. Select your event from the Discovery feed.\n2. Choose your ticket tier (General or VIP).\n3. Enter your M-Pesa phone number.\n4. Input your PIN in the secure SIM popup to complete payment." },
  { q: "Why hasn't my M-Pesa STK prompt appeared?", a: "Wait up to 60 seconds. If it doesn't appear, check if your phone number is correct. Tiketa automatically polls the M-Pesa gateway in the background to verify delayed transactions." },
  { q: "Is the price I see the final price?", a: "Yes. In accordance with our trust policy, all convenience fees and taxes are included upfront. What you see is exactly what you pay." }
];

const WALLET_FAQS: FAQItem[] = [
  { q: "Where do I find my ticket QR code?", a: "Go to the 'Tickets' tab. Your active tickets will display in a staggered stack layout. Tap a card to reveal the cryptographic vault." },
  { q: "Do I need internet at the gate?", a: "The venue coordinator can verify device-bound proofs on its local network. A coordinator partition is shown as degraded and cannot claim globally unique admission." },
  { q: "What should I do if my QR won't scan?", a: "Ensure your device is bound to the ticket and the secure key is available. The coordinator will hold admission when clock drift or manifest freshness cannot be verified." }
];

const RESELL_FAQS: FAQItem[] = [
  { q: "Can I resell my ticket?", a: "Yes. Swipe left on your ticket in the Wallet and select 'Resell'. Enter your price. To prevent ticket scalping, resale prices are capped at the original face value." },
  { q: "When do I get paid for a resale?", a: "Once another fan buys your listed ticket, your original ticket is revoked, a new QR is generated for the buyer, and your payout is sent via M-Pesa B2C within 24 hours." }
];

const REFUND_FAQS: FAQItem[] = [
  { q: "When am I entitled to a refund?", a: "Refunds are issued automatically if the event is cancelled or rescheduled. You are also eligible if your ticket is successfully bought back by a waitlisted user." },
  { q: "How long does a refund take?", a: "Automatic refunds are settled directly to the purchasing M-Pesa account within 3 to 5 business days." }
];

const ORGANISER_FAQS: FAQItem[] = [
  { q: "How does the scraper work?", a: "Link your Facebook Page, Instagram Business, or Eventbrite ID. Tiketa's background workers pull updates every 30 minutes, keeping your listings synchronized." },
  { q: "When are payouts disbursed?", a: "Payouts are automatically swept daily at 06:00 EAT directly to your configured M-Pesa shortcode or verified bank account." }
];

export default function FAQScreen() {
  const router = useRouter();
  const [search, setSearch] = useState('');
  const [expandedIndex, setExpandedIndex] = useState<string | null>(null);

  const toggleExpand = (id: string) => {
    triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
    setExpandedIndex(expandedIndex === id ? null : id);
  };

  const filterFaqs = (faqs: FAQItem[], section: string) => {
    return faqs.filter(
      item =>
        item.q.toLowerCase().includes(search.toLowerCase()) ||
        item.a.toLowerCase().includes(search.toLowerCase())
    ).map((faq, idx) => {
      const uniqueId = `${section}_${idx}`;
      const expanded = expandedIndex === uniqueId;
      return (
        <Pressable
          key={uniqueId}
          style={styles.faqCard}
          onPress={() => toggleExpand(uniqueId)}
        >
          <View style={styles.faqHeader}>
            <Text style={styles.faqQuestion}>{faq.q}</Text>
            <Text style={styles.faqIcon}>{expanded ? "−" : "+"}</Text>
          </View>
          {expanded && (
            <Text style={styles.faqAnswer}>{faq.a}</Text>
          )}
        </Pressable>
      );
    });
  };

  return (
    <View style={styles.root}>
      <StatusBar barStyle="light-content" backgroundColor={Colors.void} />
      <SafeAreaView style={styles.container} edges={['top']}>

        {/* Back navigation */}
        <View style={styles.header}>
          <Pressable style={styles.backBtn} onPress={() => router.back()}>
            <Text style={styles.backText}>← Back</Text>
          </Pressable>
          <Text style={styles.title}>FAQ Center</Text>
        </View>

        {/* Search */}
        <View style={styles.searchBar}>
          <Text style={styles.searchIcon}>⌕</Text>
          <TextInput
            placeholder="Search help topics..."
            placeholderTextColor={Colors.periwinkle}
            style={styles.searchInput}
            value={search}
            onChangeText={setSearch}
          />
        </View>

        <ScrollView contentContainerStyle={styles.scroll} showsVerticalScrollIndicator={false}>

          <Text style={styles.sectionTitle}>Buying & Payments</Text>
          {filterFaqs(BUYING_FAQS, 'buying')}

          <Text style={styles.sectionTitle}>Wallet & Gate Entry</Text>
          {filterFaqs(WALLET_FAQS, 'wallet')}

          <Text style={styles.sectionTitle}>Reselling & Capping</Text>
          {filterFaqs(RESELL_FAQS, 'resell')}

          <Text style={styles.sectionTitle}>Refund Policy</Text>
          {filterFaqs(REFUND_FAQS, 'refund')}

          <Text style={styles.sectionTitle}>For Organisers</Text>
          {filterFaqs(ORGANISER_FAQS, 'organiser')}

          <View style={{ height: 100 }} />
        </ScrollView>
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: Colors.void },
  container: { flex: 1 },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: Space.base,
    paddingVertical: Space.md,
    gap: Space.lg,
  },
  backBtn: {},
  backText: { ...Font.bodyM, color: Colors.teal },
  title: { ...Font.h2, color: Colors.white },

  searchBar: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.base,
    height: 48,
    marginHorizontal: Space.base,
    marginBottom: Space.base,
    borderWidth: 1,
    borderColor: Colors.white10,
  },
  searchIcon: { fontSize: 20, color: Colors.periwinkle, marginRight: Space.xs },
  searchInput: { flex: 1, ...Font.bodyM, color: Colors.white },

  scroll: { paddingHorizontal: Space.base },
  sectionTitle: { ...Font.h3, color: Colors.teal, marginTop: Space.lg, marginBottom: Space.sm },

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
  faqQuestion: { ...Font.labelL, color: Colors.white, flex: 1, marginRight: Space.sm },
  faqIcon: { ...Font.h2, color: Colors.teal },
  faqAnswer: { ...Font.bodyM, color: Colors.periwinkle, marginTop: Space.md, lineHeight: 20 },
});

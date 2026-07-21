import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  StatusBar,
  Pressable,
  TextInput,
  Alert,
  LayoutAnimation,
  UIManager,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { BlurView } from 'expo-blur';
import { Colors, Font, Space, Radius, Glow } from '../../theme/dunda';
import { triggerHaptic } from '../../utils/haptics';
import * as Haptics from 'expo-haptics';
import { api } from '../../api/client';
import { TiketaLogo } from '../../components/TiketaLogo';
import { useRouter } from 'expo-router';
// Enable LayoutAnimation on Android
if (
  Platform.OS === 'android' &&
  UIManager.setLayoutAnimationEnabledExperimental
) {
  UIManager.setLayoutAnimationEnabledExperimental(true);
}

// ── FAQ Data ───────────────────────────────────────────────────────────────────
const FAQ_DATA = [
  {
    q: 'How do I buy tickets?',
    a: 'Browse events on the Discover tab, select your event, choose a tier, and pay instantly with M-Pesa. Your ticket appears in your Wallet within seconds.',
  },
  {
    q: 'Is my ticket transferable?',
    a: 'Yes. Use the Resell feature in your Ticket Wallet. Tiketa caps resale prices at the original face value to prevent scalping.',
  },
  {
    q: 'How do refunds work?',
    a: 'If an event is cancelled, refunds are automatically processed to your M-Pesa within 48 hours. For postponements, your ticket remains valid.',
  },
  {
    q: 'What is the QR code on my ticket?',
    a: 'Your QR code contains a device-bound Ed25519 proof that refreshes every 30 seconds. Screenshots cannot be used as a live proof.',
  },
  {
    q: 'How do I become an organiser?',
    a: 'Visit dunda.app/portal to create your organiser account. You can import events from existing platforms or create them manually.',
  },
];

// ── Types ──────────────────────────────────────────────────────────────────────
type AuthTab = 'phone' | 'email';
type PhoneStep = 'phone' | 'otp';

interface UserData {
  name?: string;
  email?: string;
  phone?: string;
}

// ── FAQ Item Component ─────────────────────────────────────────────────────────
function FAQItem({ question, answer }: { question: string; answer: string }) {
  const [expanded, setExpanded] = React.useState(false);

  const toggle = () => {
    triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
    LayoutAnimation.configureNext(LayoutAnimation.Presets.easeInEaseOut);
    setExpanded((prev) => !prev);
  };

  return (
    <Pressable style={styles.faqItem} onPress={toggle}>
      <View style={styles.faqHeader}>
        <Text style={styles.faqQuestion}>{question}</Text>
        <Text style={styles.faqChevron}>{expanded ? '▾' : '›'}</Text>
      </View>
      {expanded && <Text style={styles.faqAnswer}>{answer}</Text>}
    </Pressable>
  );
}

// ── Main Screen ────────────────────────────────────────────────────────────────
export default function ProfileScreen() {
  const router = useRouter();
  // Auth state
  const [isAuthenticated, setIsAuthenticated] = React.useState(false);
  const [authTab, setAuthTab] = React.useState<AuthTab>('phone');
  const [loading, setLoading] = React.useState(false);

  // Phone OTP state
  const [phoneStep, setPhoneStep] = React.useState<PhoneStep>('phone');
  const [phone, setPhone] = React.useState('');
  const [otp, setOtp] = React.useState('');

  // Email state
  const [email, setEmail] = React.useState('');
  const [password, setPassword] = React.useState('');
  const [name, setName] = React.useState('');
  const [isRegister, setIsRegister] = React.useState(false);

  // Profile state
  const [user, setUser] = React.useState<UserData | null>(null);
  const [pushEnabled, setPushEnabled] = React.useState(true);

  // Restore session on mount
  React.useEffect(() => {
    const unsubscribe = api.onSessionExpired(() => {
      setIsAuthenticated(false);
      setUser(null);
    });

    const restoreSession = async () => {
      try {
        const token = await api.getToken();
        const cachedUser = await api.getUser();
        if (token && cachedUser) {
          setUser(cachedUser);
          setIsAuthenticated(true);
        }
      } catch (e) {
        console.error('Error restoring session:', e);
      }
    };
    restoreSession();
    return unsubscribe;
  }, []);

  // ── Auth Handlers ──────────────────────────────────────────────────────────

  const handleSendOtp = async () => {
    if (phone.length < 9) return;
    triggerHaptic(Haptics.ImpactFeedbackStyle.Medium);
    setLoading(true);
    try {
      await api.post('/auth/otp/send', { phone });
      setPhoneStep('otp');
    } catch (e: any) {
      Alert.alert('Error', e.message || 'Failed to send OTP');
    } finally {
      setLoading(false);
    }
  };

  const handleVerifyOtp = async () => {
    if (otp.length < 4) return;
    triggerHaptic(Haptics.ImpactFeedbackStyle.Heavy);
    setLoading(true);
    try {
      const res = await api.post('/auth/otp/verify', { phone, otp });

      if (res.token) {
        await api.setSession(res.token, res.refresh_token);
        const u = res.data?.user ?? res.user ?? null;
        if (u) {
          const normalizedUser = { ...u, phone: u.phone || phone };
          await api.setUser(normalizedUser);
          setUser(normalizedUser);
        } else {
          setUser(u);
        }
        setIsAuthenticated(true);
      }
    } catch (e: any) {
      Alert.alert('Error', e.message || 'Invalid OTP');
    } finally {
      setLoading(false);
    }
  };

  const handleEmailLogin = async () => {
    if (!email || !password) return;
    triggerHaptic(Haptics.ImpactFeedbackStyle.Medium);
    setLoading(true);
    try {
      const res = await api.post('/auth/login', { email, password });
      if (res.token) {
        await api.setSession(res.token, res.refresh_token);
        const u = res.data?.user ?? res.user ?? null;
        if (u) {
          await api.setUser(u);
        }
        setUser(u);
        setIsAuthenticated(true);
      }
    } catch (e: any) {
      Alert.alert('Error', e.message || 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  const handleRegister = async () => {
    if (!email || !password || !name) return;
    triggerHaptic(Haptics.ImpactFeedbackStyle.Medium);
    setLoading(true);
    try {
      const res = await api.post('/auth/register', { email, password, name });
      if (res.token) {
        await api.setSession(res.token, res.refresh_token);
        const u = res.data?.user ?? res.user ?? null;
        if (u) {
          await api.setUser(u);
        }
        setUser(u);
        setIsAuthenticated(true);
      }
    } catch (e: any) {
      Alert.alert('Error', e.message || 'Registration failed');
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = async () => {
    triggerHaptic(Haptics.ImpactFeedbackStyle.Heavy);
    await api.removeToken();
    await api.removeUser();
    setIsAuthenticated(false);
    setUser(null);
    setPhoneStep('phone');
    setPhone('');
    setOtp('');
    setEmail('');
    setPassword('');
    setName('');
    setIsRegister(false);
  };

  const handlePrivacyAction = (action: string) => {
    triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
    Alert.alert(
      action,
      `${action} requested. The Tiketa Data Protection Officer (DPO) will process this under the 72-hour SLA.`,
    );
  };

  // ── Helpers ────────────────────────────────────────────────────────────────

  const displayName = user?.name || 'Guest User';
  const initials = displayName
    .split(' ')
    .map((w) => w[0])
    .join('')
    .toUpperCase()
    .slice(0, 2);

  // ── Auth Screen ────────────────────────────────────────────────────────────

  if (!isAuthenticated) {
    return (
      <View style={styles.authRoot}>
        <StatusBar barStyle="light-content" backgroundColor={Colors.void} />
        <View style={styles.authContainer}>
          <View style={styles.brandLogo}>
            <TiketaLogo size={76} color={Colors.teal} label="Tiketa" />
          </View>
          <Text style={styles.brandTitle}>TIKETA</Text>

          {/* Auth Tabs */}
          <View style={styles.tabRow}>
            <Pressable
              style={[styles.tab, authTab === 'phone' && styles.tabActive]}
              onPress={() => {
                triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                setAuthTab('phone');
              }}
            >
              <Text
                style={[
                  styles.tabText,
                  authTab === 'phone' && styles.tabTextActive,
                ]}
              >
                Phone
              </Text>
            </Pressable>
            <Pressable
              style={[styles.tab, authTab === 'email' && styles.tabActive]}
              onPress={() => {
                triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                setAuthTab('email');
              }}
            >
              <Text
                style={[
                  styles.tabText,
                  authTab === 'email' && styles.tabTextActive,
                ]}
              >
                Email
              </Text>
            </Pressable>
          </View>

          {/* Phone Tab */}
          {authTab === 'phone' && (
            <>
              {phoneStep === 'phone' ? (
                <View style={styles.form}>
                  <Text style={styles.instruction}>
                    Enter your M-Pesa number to continue
                  </Text>
                  <View style={styles.inputWrapper}>
                    <Text style={styles.prefix}>+254</Text>
                    <TextInput
                      style={styles.input}
                      keyboardType="phone-pad"
                      placeholder="712 345 678"
                      placeholderTextColor={Colors.periwinkle}
                      value={phone}
                      onChangeText={setPhone}
                      autoFocus
                    />
                  </View>
                  <Pressable
                    style={[styles.submitBtn, loading && styles.submitBtnDisabled]}
                    onPress={handleSendOtp}
                    disabled={loading}
                  >
                    <Text style={styles.submitText}>
                      {loading ? 'WAITING...' : 'SEND CODE'}
                    </Text>
                  </Pressable>
                </View>
              ) : (
                <View style={styles.form}>
                  <Text style={styles.instruction}>
                    Enter the 4-digit code sent to +254 {phone}
                  </Text>
                  <TextInput
                    style={[styles.input, styles.otpInput]}
                    keyboardType="number-pad"
                    placeholder="0000"
                    placeholderTextColor={Colors.periwinkle}
                    maxLength={4}
                    value={otp}
                    onChangeText={setOtp}
                    autoFocus
                  />
                  <Pressable
                    style={[styles.submitBtn, loading && styles.submitBtnDisabled]}
                    onPress={handleVerifyOtp}
                    disabled={loading}
                  >
                    <Text style={styles.submitText}>
                      {loading ? 'VERIFYING...' : 'LOGIN'}
                    </Text>
                  </Pressable>
                </View>
              )}
            </>
          )}

          {/* Email Tab */}
          {authTab === 'email' && (
            <View style={styles.form}>
              <Text style={styles.instruction}>
                {isRegister ? 'Create your Tiketa account' : 'Sign in with email'}
              </Text>

              {isRegister && (
                <View style={styles.inputWrapperFull}>
                  <TextInput
                    style={styles.inputFull}
                    placeholder="Full Name"
                    placeholderTextColor={Colors.periwinkle}
                    value={name}
                    onChangeText={setName}
                    autoCapitalize="words"
                  />
                </View>
              )}

              <View style={styles.inputWrapperFull}>
                <TextInput
                  style={styles.inputFull}
                  placeholder="Email address"
                  placeholderTextColor={Colors.periwinkle}
                  value={email}
                  onChangeText={setEmail}
                  keyboardType="email-address"
                  autoCapitalize="none"
                  autoFocus
                />
              </View>

              <View style={styles.inputWrapperFull}>
                <TextInput
                  style={styles.inputFull}
                  placeholder="Password"
                  placeholderTextColor={Colors.periwinkle}
                  value={password}
                  onChangeText={setPassword}
                  secureTextEntry
                />
              </View>

              {!isRegister && (
                <Pressable
                  style={{ alignSelf: 'flex-end', marginBottom: Space.xl }}
                  onPress={() => {
                    triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                    Alert.alert('Forgot Password', 'A password reset link will be sent to your email.');
                  }}
                >
                  <Text style={{ ...Font.labelS, color: Colors.teal }}>Forgot Password?</Text>
                </Pressable>
              )}

              <Pressable
                style={[styles.submitBtn, loading && styles.submitBtnDisabled]}
                onPress={isRegister ? handleRegister : handleEmailLogin}
                disabled={loading}
              >
                <Text style={styles.submitText}>
                  {loading
                    ? 'PLEASE WAIT...'
                    : isRegister
                      ? 'REGISTER'
                      : 'SIGN IN'}
                </Text>
              </Pressable>

              <Pressable
                style={styles.toggleLink}
                onPress={() => {
                  triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                  setIsRegister((prev) => !prev);
                }}
              >
                <Text style={styles.toggleLinkText}>
                  {isRegister
                    ? 'Already have an account? Sign In'
                    : 'Create Account'}
                </Text>
              </Pressable>
            </View>
          )}
        </View>
      </View>
    );
  }

  // ── Authenticated Profile ──────────────────────────────────────────────────

  return (
    <View style={styles.root}>
      <StatusBar barStyle="light-content" backgroundColor={Colors.void} />
      <SafeAreaView style={styles.flex} edges={['top']}>
        <ScrollView
          contentContainerStyle={styles.scroll}
          showsVerticalScrollIndicator={false}
        >
          {/* Header */}
          <View style={styles.header}>
            <Text style={styles.headerTitle}>My Profile</Text>
            <Text style={styles.headerSub}>
              Data Governance &amp; KYC Vault
            </Text>
          </View>

          {/* User Info Card */}
          <View style={[styles.card, Glow.tealSm]}>
            <View style={styles.avatarRow}>
              <View style={styles.avatar}>
                <Text style={styles.avatarText}>{initials}</Text>
              </View>
              <View style={styles.flex}>
                <Text style={styles.userName}>{displayName}</Text>
                <Text style={styles.userRole}>Attendee Account</Text>
              </View>
              <View style={styles.kycChip}>
                <Text style={styles.kycChipText}>✓ Verified</Text>
              </View>
            </View>
          </View>

          {/* My Stats */}
          <Text style={styles.sectionTitle}>My Stats</Text>
          <View style={styles.statsRow}>
            <View style={styles.statCard}>
              <Text style={styles.statValue}>3</Text>
              <Text style={styles.statLabel}>Events Attended</Text>
            </View>
            <View style={styles.statCard}>
              <Text style={styles.statValue}>2</Text>
              <Text style={styles.statLabel}>Upcoming</Text>
            </View>
            <View style={styles.statCard}>
              <Text style={styles.statValue}>1</Text>
              <Text style={styles.statLabel}>Resale Active</Text>
            </View>
          </View>

          {/* ODPC Compliance Section */}
          <Text style={styles.sectionTitle}>Kenya ODPC Privacy Portal</Text>
          <Text style={styles.sectionDesc}>
            Manage your personal data rights under Section 31 of the Kenya Data
            Protection Act.
          </Text>

          <Pressable
            style={styles.btnRow}
            onPress={() => handlePrivacyAction('Data Access')}
          >
            <View style={styles.btnIconContainer}>
              <Text style={styles.btnIcon}>👁</Text>
            </View>
            <View style={styles.flex}>
              <Text style={styles.btnLabel}>Request Access to My Data</Text>
              <Text style={styles.btnDesc}>
                Export all personal details and transaction ledger history.
              </Text>
            </View>
            <Text style={styles.btnArrow}>›</Text>
          </Pressable>

          <Pressable
            style={styles.btnRow}
            onPress={() => handlePrivacyAction('Data Rectification')}
          >
            <View style={styles.btnIconContainer}>
              <Text style={styles.btnIcon}>✏️</Text>
            </View>
            <View style={styles.flex}>
              <Text style={styles.btnLabel}>Correct My Information</Text>
              <Text style={styles.btnDesc}>
                Update phone number, device fingerprints, or identification
                docs.
              </Text>
            </View>
            <Text style={styles.btnArrow}>›</Text>
          </Pressable>

          <Pressable
            style={styles.btnRow}
            onPress={() => handlePrivacyAction('Data Erasure')}
          >
            <View style={styles.btnIconContainer}>
              <Text style={styles.btnIcon}>🗑</Text>
            </View>
            <View style={styles.flex}>
              <Text style={styles.btnLabel}>
                Request Erasure (Right to Be Forgotten)
              </Text>
              <Text style={styles.btnDesc}>
                Pseudonymize your record. Active tickets must be voided first.
              </Text>
            </View>
            <Text style={styles.btnArrow}>›</Text>
          </Pressable>

          {/* Preferences */}
          <Text style={styles.sectionTitle}>Preferences</Text>

          <Pressable
            style={styles.btnRow}
            onPress={() => {
              triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
              setPushEnabled((prev) => !prev);
            }}
          >
            <View style={styles.btnIconContainer}>
              <Text style={styles.btnIcon}>🔔</Text>
            </View>
            <View style={styles.flex}>
              <Text style={styles.btnLabel}>Push Notifications</Text>
              <Text style={styles.btnDesc}>
                {pushEnabled
                  ? 'Currently enabled for event updates and resales.'
                  : 'Notifications are paused.'}
              </Text>
            </View>
            <Text
              style={[
                styles.btnArrow,
                { color: pushEnabled ? Colors.teal : Colors.periwinkle },
              ]}
            >
              {pushEnabled ? 'ON' : 'OFF'}
            </Text>
          </Pressable>

          <View style={styles.btnRow}>
            <View style={styles.btnIconContainer}>
              <Text style={styles.btnIcon}>🌙</Text>
            </View>
            <View style={styles.flex}>
              <Text style={styles.btnLabel}>Dark Mode</Text>
              <Text style={styles.btnDesc}>Always on — Chroma-Noir.</Text>
            </View>
            <Text style={[styles.btnArrow, { color: Colors.teal }]}>ON</Text>
          </View>

          {/* FAQ Section */}
          <Text style={styles.sectionTitle}>Frequently Asked Questions</Text>
          {FAQ_DATA.map((item, index) => (
            <FAQItem key={index} question={item.q} answer={item.a} />
          ))}
          <Pressable style={{ marginTop: Space.xl, marginBottom: Space.xl, alignItems: 'center' }} onPress={() => { triggerHaptic(Haptics.ImpactFeedbackStyle.Light); router.push('/faq'); }}>
             <Text style={{ ...Font.labelL, color: Colors.teal }}>View Full FAQ & Help Center →</Text>
          </Pressable>

          {/* Logout */}
          <Pressable style={styles.logoutBtn} onPress={handleLogout}>
            <Text style={styles.logoutText}>Log Out</Text>
          </Pressable>

          {/* DPO Information Banner */}
          <BlurView intensity={24} tint="dark" style={styles.banner}>
            <Text style={styles.bannerTitle}>
              🛡️ DATA PROTECTION OFFICER (DPO)
            </Text>
            <Text style={styles.bannerText}>
              For escalation, contact the Dunda Privacy Office at{' '}
              <Text style={styles.bannerEmail}>dpo@dunda.app</Text>. Registration
              No:{' '}
              <Text style={[styles.mono, { color: Colors.white }]}>
                ODPC/REG/2026/0894
              </Text>
              .
            </Text>
          </BlurView>

          <View style={styles.bottomSpacer} />
        </ScrollView>
      </SafeAreaView>
    </View>
  );
}

// ── Styles ─────────────────────────────────────────────────────────────────────
const styles = StyleSheet.create({
  // Layout
  flex: { flex: 1 },
  root: { flex: 1, backgroundColor: Colors.void },
  scroll: { paddingHorizontal: Space.base, paddingTop: Space.base },
  bottomSpacer: { height: 100 },

  // Header
  header: { marginBottom: Space.xl },
  headerTitle: { ...Font.displayL, color: Colors.white },
  headerSub: {
    ...Font.bodyS,
    color: Colors.periwinkle,
    marginTop: Space.xs,
  },

  // User card
  card: {
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: Space.base,
    marginBottom: Space.xl,
  },
  avatarRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Space.md,
  },
  avatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: Colors.tealDark,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: Colors.teal,
  },
  avatarText: { ...Font.h3, color: Colors.white },
  userName: { ...Font.h2, color: Colors.white },
  userRole: { ...Font.bodyS, color: Colors.periwinkle },
  kycChip: {
    marginLeft: 'auto',
    backgroundColor: 'rgba(57,255,20,0.1)',
    borderWidth: 1,
    borderColor: Colors.success,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.sm,
    paddingVertical: 3,
  },
  kycChipText: { ...Font.labelS, color: Colors.success },

  // Stats
  statsRow: {
    flexDirection: 'row',
    gap: Space.sm,
    marginBottom: Space.xl,
  },
  statCard: {
    flex: 1,
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: Space.md,
    alignItems: 'center',
  },
  statValue: {
    ...Font.h1,
    color: Colors.teal,
    marginBottom: 2,
  },
  statLabel: {
    ...Font.labelS,
    color: Colors.periwinkle,
    textAlign: 'center',
  },

  // Sections
  sectionTitle: {
    ...Font.h3,
    color: Colors.white,
    marginBottom: Space.xs,
  },
  sectionDesc: {
    ...Font.bodyS,
    color: Colors.periwinkle,
    marginBottom: Space.base,
  },

  // Action rows
  btnRow: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: Space.base,
    marginBottom: Space.sm,
    gap: Space.md,
  },
  btnIconContainer: {
    width: 36,
    height: 36,
    borderRadius: Radius.sm,
    backgroundColor: Colors.depth,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: Colors.white10,
  },
  btnIcon: { fontSize: 18, color: Colors.periwinkle },
  btnLabel: { ...Font.labelL, color: Colors.white, marginBottom: 2 },
  btnDesc: { ...Font.bodyS, color: Colors.periwinkle, flex: 1 },
  btnArrow: { color: Colors.periwinkle, fontSize: 22 },

  // FAQ
  faqItem: {
    backgroundColor: Colors.surface,
    borderRadius: Radius.card,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    padding: Space.base,
    marginBottom: Space.sm,
    overflow: 'hidden',
  },
  faqHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  faqQuestion: {
    ...Font.labelL,
    color: Colors.white,
    flex: 1,
    marginRight: Space.sm,
  },
  faqChevron: {
    fontSize: 20,
    color: Colors.periwinkle,
  },
  faqAnswer: {
    ...Font.bodyM,
    color: Colors.periwinkle,
    marginTop: Space.md,
    lineHeight: 20,
  },

  // Logout
  logoutBtn: {
    alignItems: 'center',
    paddingVertical: Space.lg,
    marginTop: Space.base,
    marginBottom: Space.sm,
  },
  logoutText: {
    ...Font.h3,
    color: Colors.magenta,
  },

  // DPO Banner
  banner: {
    borderRadius: Radius.card,
    padding: Space.base,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    marginTop: Space.lg,
    overflow: 'hidden',
  },
  bannerTitle: {
    ...Font.labelS,
    color: Colors.teal,
    marginBottom: Space.xs,
  },
  bannerText: {
    ...Font.bodyS,
    color: Colors.periwinkle,
    lineHeight: 18,
  },
  bannerEmail: { color: Colors.teal },
  mono: { ...Font.monoS, color: Colors.periwinkle },

  // ── Auth Styles ────────────────────────────────────────────────────────────
  authRoot: { flex: 1, backgroundColor: Colors.void, padding: Space.base },
  authContainer: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  brandLogo: { marginBottom: Space.md, alignItems: 'center' },
  brandTitle: {
    ...Font.displayL,
    color: Colors.teal,
    fontSize: 48,
    marginBottom: 40,
    letterSpacing: 4,
  },

  // Tab switcher
  tabRow: {
    flexDirection: 'row',
    backgroundColor: Colors.surface,
    borderRadius: Radius.pill,
    borderWidth: 1,
    borderColor: Colors.glassBorder,
    marginBottom: Space.xxl,
    width: '100%',
    maxWidth: 400,
    overflow: 'hidden',
  },
  tab: {
    flex: 1,
    paddingVertical: Space.md,
    alignItems: 'center',
    borderRadius: Radius.pill,
  },
  tabActive: {
    backgroundColor: Colors.tealDark,
  },
  tabText: {
    ...Font.h3,
    color: Colors.periwinkle,
  },
  tabTextActive: {
    color: Colors.white,
  },

  // Form
  form: { width: '100%', maxWidth: 400, alignItems: 'center' },
  instruction: {
    ...Font.bodyM,
    color: Colors.periwinkle,
    marginBottom: Space.lg,
    textAlign: 'center',
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: Colors.surface,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.base,
    height: 56,
    width: '100%',
    marginBottom: Space.lg,
    borderWidth: 1,
    borderColor: Colors.white10,
  },
  inputWrapperFull: {
    backgroundColor: Colors.surface,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.base,
    height: 56,
    width: '100%',
    marginBottom: Space.md,
    borderWidth: 1,
    borderColor: Colors.white10,
    justifyContent: 'center',
  },
  prefix: { ...Font.h3, color: Colors.white, marginRight: Space.sm },
  input: {
    flex: 1,
    ...Font.h3,
    color: Colors.white,
    outlineStyle: 'none',
  } as any,
  inputFull: {
    ...Font.bodyL,
    color: Colors.white,
    width: '100%',
    outlineStyle: 'none',
  } as any,
  otpInput: {
    backgroundColor: Colors.surface,
    borderRadius: Radius.pill,
    paddingHorizontal: Space.xl,
    height: 56,
    width: '100%',
    textAlign: 'center',
    marginBottom: Space.lg,
    borderWidth: 1,
    borderColor: Colors.white10,
  },
  submitBtn: {
    backgroundColor: Colors.magenta,
    borderRadius: Radius.pill,
    width: '100%',
    height: 56,
    justifyContent: 'center',
    alignItems: 'center',
    marginTop: Space.sm,
  },
  submitBtnDisabled: {
    opacity: 0.6,
  },
  submitText: {
    ...Font.h3,
    color: Colors.white,
    textTransform: 'uppercase',
  },
  toggleLink: {
    marginTop: Space.lg,
    paddingVertical: Space.sm,
  },
  toggleLinkText: {
    ...Font.bodyS,
    color: Colors.teal,
  },
});

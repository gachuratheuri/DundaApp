import React, { useState } from 'react';
import {
  View, Text, StyleSheet, Pressable, TextInput, Alert, StatusBar,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Colors, Font, Space, Radius } from '../theme/dunda';
import { triggerHaptic } from '../utils/haptics';
import * as Haptics from 'expo-haptics';
import { api } from '../api/client';
import { TiketaLogo } from '../components/TiketaLogo';

type AuthTab = 'phone' | 'email';
type PhoneStep = 'phone' | 'otp';

export default function AuthScreen() {
  const router = useRouter();
  const [authTab, setAuthTab] = useState<AuthTab>('phone');
  const [loading, setLoading] = useState(false);

  // Phone OTP state
  const [phoneStep, setPhoneStep] = useState<PhoneStep>('phone');
  const [phone, setPhone] = useState('');
  const [otp, setOtp] = useState('');

  // Email state
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [isRegister, setIsRegister] = useState(false);

  const handleSendOtp = async () => {
    if (phone.length < 9) {
      Alert.alert('Error', 'Please enter a valid phone number');
      return;
    }
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
        if (res.user) await api.setUser(res.user);
        router.replace('/profile');
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
        if (res.user) await api.setUser(res.user);
        router.replace('/profile');
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
        if (res.user) await api.setUser(res.user);
        router.replace('/profile');
      }
    } catch (e: any) {
      Alert.alert('Error', e.message || 'Registration failed');
    } finally {
      setLoading(false);
    }
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
        </View>

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
              <Text style={[styles.tabText, authTab === 'phone' && styles.tabTextActive]}>
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
              <Text style={[styles.tabText, authTab === 'email' && styles.tabTextActive]}>
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
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: Colors.void },
  container: { flex: 1 },
  header: {
    paddingHorizontal: Space.base,
    paddingVertical: Space.md,
  },
  backBtn: {},
  backText: { ...Font.bodyM, color: Colors.teal },

  authContainer: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingHorizontal: Space.xl },
  brandLogo: { marginBottom: Space.md, alignItems: 'center' },
  brandTitle: {
    ...Font.displayL,
    color: Colors.teal,
    fontSize: 48,
    marginBottom: 40,
    letterSpacing: 4,
  },

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

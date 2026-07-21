import React, { useEffect } from 'react';
import { View, Text, StyleSheet, Modal, Pressable, Platform } from 'react-native';
import { BlurView } from 'expo-blur';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  withTiming,
  interpolate,
} from 'react-native-reanimated';
import * as Haptics from 'expo-haptics';
import { triggerHaptic } from '../utils/haptics';
import { Colors, Space, Font, Radius } from '../theme/dunda';

interface Props {
  visible: boolean;
  title: string;
  message: string;
  actionLabel?: string;
  onAction?: () => void;
  onClose: () => void;
}

export const AstralModal: React.FC<Props> = ({
  visible,
  title,
  message,
  actionLabel = 'Confirm',
  onAction,
  onClose,
}) => {
  const animValue = useSharedValue(0);

  useEffect(() => {
    if (visible) {
      triggerHaptic(Haptics.ImpactFeedbackStyle.Medium);
      animValue.value = withSpring(1, { damping: 15, stiffness: 200 });
    } else {
      animValue.value = withTiming(0, { duration: 250 });
    }
  }, [visible, animValue]);

  // ND-01 (WCAG 2.2 SC 1.4.13): dismiss on the Escape key vector on web.
  // Native hardware back is handled by <Modal onRequestClose>.
  useEffect(() => {
    if (Platform.OS !== 'web' || !visible) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' || e.code === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [visible, onClose]);

  const overlayStyle = useAnimatedStyle(() => ({
    opacity: animValue.value,
  }));

  const modalStyle = useAnimatedStyle(() => {
    const translateY = interpolate(animValue.value, [0, 1], [100, 0]);
    const rotateX = interpolate(animValue.value, [0, 1], [30, 0]);
    const scale = interpolate(animValue.value, [0, 1], [0.9, 1]);

    return {
      transform: [
        { translateY },
        { scale },
        { perspective: 800 },
        { rotateX: `${rotateX}deg` },
      ],
      opacity: animValue.value,
    };
  });

  return (
    <Modal visible={visible} transparent animationType="none" onRequestClose={onClose}>
      <Animated.View style={[styles.overlay, overlayStyle]}>
        <Pressable style={StyleSheet.absoluteFill} onPress={onClose} />
        <BlurView intensity={40} tint="dark" style={StyleSheet.absoluteFill} />

        <Animated.View style={[styles.card, modalStyle]}>
          <View style={styles.content}>
            <Text style={styles.title}>{title}</Text>
            <Text style={styles.message}>{message}</Text>

            <View style={styles.actions}>
              <Pressable
                style={[styles.btn, styles.btnCancel]}
                onPress={() => {
                  triggerHaptic(Haptics.ImpactFeedbackStyle.Light);
                  onClose();
                }}
              >
                <Text style={styles.btnTextCancel}>Cancel</Text>
              </Pressable>
              <Pressable
                style={[styles.btn, styles.btnConfirm]}
                onPress={() => {
                  triggerHaptic(Haptics.ImpactFeedbackStyle.Heavy);
                  onAction?.();
                  onClose();
                }}
              >
                <Text style={styles.btnTextConfirm}>{actionLabel}</Text>
              </Pressable>
            </View>
          </View>
        </Animated.View>
      </Animated.View>
    </Modal>
  );
};

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0,0,0,0.3)',
  },
  card: {
    width: '85%',
    backgroundColor: 'rgba(20,20,30,0.85)',
    borderRadius: Radius.xl,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.4)',
    shadowColor: Colors.void,
    shadowOffset: { width: 0, height: 20 },
    shadowOpacity: 0.8,
    shadowRadius: 30,
  },
  content: {
    padding: Space.xl,
    alignItems: 'center',
  },
  title: {
    ...Font.h3,
    color: Colors.white,
    marginBottom: Space.sm,
    textAlign: 'center',
  },
  message: {
    ...Font.bodyM,
    color: Colors.white80,
    textAlign: 'center',
    marginBottom: Space.xl,
  },
  actions: {
    flexDirection: 'row',
    gap: Space.md,
    width: '100%',
  },
  btn: {
    flex: 1,
    paddingVertical: 14,
    borderRadius: Radius.md,
    alignItems: 'center',
    justifyContent: 'center',
  },
  btnCancel: {
    backgroundColor: Colors.glassDim,
  },
  btnConfirm: {
    backgroundColor: Colors.teal,
  },
  btnTextCancel: {
    ...Font.labelL,
    color: Colors.white,
  },
  btnTextConfirm: {
    ...Font.labelL,
    color: Colors.void,
  },
});

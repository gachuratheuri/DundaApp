import { Stack } from 'expo-router';
import Head from 'expo-router/head';
import { Colors } from '../theme/dunda';
import { View, StyleSheet, Platform } from 'react-native';

import { GestureHandlerRootView } from 'react-native-gesture-handler';

// A minimal 64x64 noise pattern for tactile film grain
const NOISE_BASE64 = 'url("data:image/svg+xml,%3Csvg viewBox=%220 0 200 200%22 xmlns=%22http://www.w3.org/2000/svg%22%3E%3Cfilter id=%22noiseFilter%22%3E%3CfeTurbulence type=%22fractalNoise%22 baseFrequency=%220.65%22 numOctaves=%223%22 stitchTiles=%22stitch%22/%3E%3C/filter%3E%3Crect width=%22100%25%22 height=%22100%25%22 filter=%22url(%23noiseFilter)%22/%3E%3C/svg%3E")';

export default function RootLayout() {
  return (
    <>
      {Platform.OS === 'web' && (
        <Head>
          <title>Tiketa — Discover & Book Live Events</title>
          <meta name="description" content="Discover, book, and resell tickets to the best live events in Nairobi. Secure cryptographic tickets powered by M-Pesa." />
          <link rel="preconnect" href="https://fonts.googleapis.com" />
          <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
          <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;500&family=Oswald:wght@700;900&display=swap" rel="stylesheet" />
          <style>{`
            :root {
                --void-black: #000000;
                --pure-white: #FFFFFF;
                --periwinkle-accent: #A99FB8;
                --electric-yellow: #F4F800;
                --hot-pink: #FF1C5E;
                --acid-green: #39FF14;
                --optic-cyan: #00F0FF;
                --deep-purple: #C900FF;
            }
            body, html {
                margin: 0;
                padding: 0;
                background-color: var(--void-black);
                font-family: 'Inter', sans-serif;
            }

            /* LAYER 1: Background - The "Hollow" or Stroke Technique */
            .cb-scene-container {
                position: relative;
                width: 100%;
                height: 100%;
                display: flex;
                align-items: center;
                justify-content: center;
                transform-style: preserve-3d;
                perspective: 1000px;
                overflow: hidden;
            }
            .cb-hollow-text-bg {
                position: absolute;
                font-family: 'Oswald', impact, sans-serif;
                font-weight: 900;
                font-size: 18vw;
                text-transform: uppercase;
                letter-spacing: -0.02em;
                line-height: 0.8;
                text-align: center;
                color: transparent;
                -webkit-text-stroke: 2px rgba(255, 255, 255, 0.25);
                z-index: 1;
                pointer-events: none;
            }
            .cb-iridescent-object {
                position: absolute;
                width: 35vw;
                height: 35vw;
                max-width: 400px;
                max-height: 400px;
                border-radius: 15%;
                background: linear-gradient(135deg, var(--optic-cyan), var(--deep-purple), var(--hot-pink), var(--electric-yellow));
                background-size: 300% 300%;
                box-shadow: 0 0 80px rgba(201, 0, 255, 0.35), inset 0 0 40px rgba(0, 240, 255, 0.5), inset 20px 20px 60px rgba(255, 255, 255, 0.4);
                z-index: 2;
                animation: cb-spectralShift 6s ease-in-out infinite, cb-floatObject 8s ease-in-out infinite;
            }
            .cb-solid-text-fg {
                position: absolute;
                font-family: 'Oswald', impact, sans-serif;
                font-weight: 900;
                font-size: 18vw;
                text-transform: uppercase;
                letter-spacing: -0.02em;
                line-height: 0.8;
                text-align: center;
                color: var(--pure-white);
                z-index: 3;
                pointer-events: none;
                text-shadow: 0px 10px 30px rgba(2, 2, 2, 0.9);
            }
            .cb-secondary-text {
                position: absolute;
                bottom: 8%;
                font-family: 'Inter', sans-serif;
                font-weight: 300;
                font-size: 1.1rem;
                letter-spacing: 0.05em;
                max-width: 500px;
                text-align: center;
                line-height: 1.6;
                color: var(--periwinkle-accent);
                z-index: 4;
            }
            .cb-secondary-text strong {
                font-weight: 500;
                color: var(--pure-white);
            }
            @keyframes cb-spectralShift {
                0% { background-position: 0% 50%; transform: rotate3d(1, 1, 0, 0deg) scale(1); }
                50% { background-position: 100% 50%; transform: rotate3d(1, 1, 0, 15deg) scale(1.05); }
                100% { background-position: 0% 50%; transform: rotate3d(1, 1, 0, 0deg) scale(1); }
            }
            @keyframes cb-floatObject {
                0%, 100% { top: calc(50% - 20px); }
                50% { top: calc(50% + 20px); }
            }
          `}</style>
        </Head>
      )}
      <GestureHandlerRootView style={{ flex: 1, backgroundColor: Colors.void }}>
        <Stack screenOptions={{ headerShown: false, contentStyle: { backgroundColor: 'transparent' } }}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="event/[id]" options={{ presentation: 'modal' }} />
      </Stack>
      {/* Tactile Noise Overlay (Chroma-Noir spec) */}
      <View
        pointerEvents="none"
        style={[
          StyleSheet.absoluteFill,
          {
            opacity: 0.05,
            ...(Platform.OS === 'web' && {
              backgroundImage: NOISE_BASE64,
              mixBlendMode: 'overlay',
            } as any)
          }
        ]}
      />
      </GestureHandlerRootView>
    </>
  );
}

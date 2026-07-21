// src/theme/dunda.ts
// Dunda "Astral Dark" design system v2.0
// Palette drawn from the five mood-board images:
//   Void Black   — the crystalline dark base (Image 2, 5)
//   Abyss Navy   — deep atmospheric background (Image 1)
//   Aurora Teal  — primary accent, bioluminescent glow (Image 1, 3)
//   Prism Gold   — prestige / VIP accent, warm staircase light (Image 2)
//   Crystal White — purity, clarity, glass surface (Image 4)
//   Nebula Magenta — energy, tickets, notification badges (Image 5)

import { Dimensions, Platform } from 'react-native';

const OSWALD = Platform.OS === 'web' ? '"Oswald", impact, sans-serif' : 'System';
const INTER  = Platform.OS === 'web' ? '"Inter", sans-serif' : 'System';

const { width: SW, height: SH } = Dimensions.get('window');

// ── Color Palette ────────────────────────────────────────────────────────────
export const Colors = {
  // Base surfaces (Chroma-Noir)
  void:          '#000000',   // True black base
  abyss:         '#060607',   // Deepened surface (near-black)
  depth:         '#030304',   // Secondary elevated (near-black)
  surface:       '#08080A',   // Deepened surface (near-black)
  overlay:       '#000000',   // Modal overlays

  // Exact CSS map
  voidBlack:      '#000000',
  surfaceCarbon:  '#08080A',
  pureWhite:      '#FCFCFD',
  periwinkle:     '#A99FB8',  // Soft lavender secondary text (harmonizes with acid purple; avoids flat gray)
  electricYellow: '#F4F800',
  hotPink:        '#FF1C5E',
  acidGreen:      '#39FF14',
  opticCyan:      '#00F0FF',
  deepPurple:     '#C900FF',

  // Glass surfaces (Chroma-Noir exact specs)
  glass:         'rgba(6, 6, 7, 0.5)',  // Frosted background (near-black)
  glassBright:   'rgba(6, 6, 7, 0.7)',
  glassDim:      'rgba(6, 6, 7, 0.3)',
  glassBorder:   'rgba(252, 252, 253, 0.08)', // Thin white border

  // Chroma Violet (Primary accent, interactive active states, selection pills).
  // NOTE: `#B026FF` is violet, NOT teal. `chromaViolet` is the correct semantic
  // name; `teal*` are retained as backward-compatible aliases (QA §1.1).
  chromaViolet:  '#B026FF',
  teal:          '#B026FF',
  tealMid:       '#8E1FCC',
  tealDark:      '#5E1488',
  tealGlow:      'rgba(176,38,255,0.40)',
  tealGlowSoft:  'rgba(176,38,255,0.15)',

  // Magenta Acid (Primary CTA, high urgency, conversions, sold-out)
  magentaAcid:   '#FF1C5E',
  magenta:       '#FF1C5E',
  magentaMid:    '#CC164B',
  magentaGlow:   'rgba(255,28,94,0.40)',

  // Gold Prestige (VIP tier status, badge highlights, premium countdowns)
  goldPrestige:  '#F4F800',
  gold:          '#F4F800',
  goldMid:       '#C4C700',
  goldDark:      '#8A8C00',
  goldGlow:      'rgba(244,248,0,0.40)',
  goldGlowSoft:  'rgba(244,248,0,0.15)',

  // Prism Violet (Iridescent gradients, mid-tones)
  purple:        '#8A2BE2',
  neonBlue:      '#8A2BE2', // Remapped to Prism Violet
  aiBlue:        '#00F0FF', // Remapped to Optic Cyan
  aiPurple:      '#8A2BE2',

  // Hyper-White (Chroma-Noir)
  white:         '#FCFCFD',
  white80:       'rgba(252,252,253,0.80)',
  white60:       'rgba(252,252,253,0.60)',
  white40:       'rgba(252,252,253,0.40)',
  white20:       'rgba(252,252,253,0.20)',
  white10:       'rgba(252,252,253,0.10)',
  white05:       'rgba(252,252,253,0.05)', // Used for the 0.08 borders in glassmorphism

  // Status
  success:       '#39FF14', // Acid Green
  warning:       '#F4F800',
  error:         '#FF1C5E',
  info:          '#8A2BE2', // Prism Violet

  // Ticket scanner
  scanGreen:     '#39FF14',
  scanGlow:      'rgba(57,255,20,0.50)',
} as const;

// ── Gradient Presets ─────────────────────────────────────────────────────────
export const Gradients = {
  // Hero card — event cover overlay (richer contrast)
  heroScrim:     [Colors.void, 'rgba(0,0,0,0.2)', 'transparent', 'transparent', Colors.void] as [string, string, ...string[]],
  heroBottom:    ['transparent', 'rgba(0,0,0,0.8)', Colors.void] as [string, string, ...string[]],

  // VIP badge
  vipGold:       [Colors.gold, Colors.goldMid, '#A0610A'] as [string, string, ...string[]],

  // Primary CTA button (Acid Magenta)
  ctaTeal:       ['#FF1C5E', '#FF1C5E'] as [string, string, ...string[]],

  // Ticket QR aurora border (Prism Violet, Optic Cyan, Acid Magenta)
  aurora:        ['#8A2BE2', '#00F0FF', '#FF1C5E', '#8A2BE2', '#00F0FF', '#FF1C5E'] as [string, string, ...string[]],

  // Prism glass shimmer (Thin-Film Iridescence)
  prismShimmer:  ['rgba(255,28,94,0.30)', 'rgba(138,43,226,0.30)', 'rgba(0,240,255,0.30)'] as [string, string, ...string[]],

  // Background deep space
  deepSpace:     [Colors.void, Colors.depth, Colors.abyss] as [string, string, ...string[]],

  // Countdown timer bar
  countdownBar:  ['#FF1C5E', '#B026FF'] as [string, string, ...string[]],
} as const;

// ── Typography ────────────────────────────────────────────────────────────────
export const Font = {
  // Primary Display (Monument Extended equivalent / Oswald)
  displayXL:  { fontFamily: OSWALD, fontSize: 42, fontWeight: '900' as const, letterSpacing: -2, lineHeight: 48, textTransform: 'uppercase' as const },
  displayL:   { fontFamily: OSWALD, fontSize: 34, fontWeight: '900' as const, letterSpacing: -2, lineHeight: 40, textTransform: 'uppercase' as const },
  displayM:   { fontFamily: OSWALD, fontSize: 28, fontWeight: '900' as const, letterSpacing: -1.5, lineHeight: 34, textTransform: 'uppercase' as const },

  // Headings
  h1: { fontFamily: OSWALD, fontSize: 24, fontWeight: '900' as const, letterSpacing: -1, lineHeight: 30, textTransform: 'uppercase' as const },
  h2: { fontFamily: OSWALD, fontSize: 20, fontWeight: '900' as const, letterSpacing: -1, lineHeight: 26, textTransform: 'uppercase' as const },
  h3: { fontFamily: OSWALD, fontSize: 17, fontWeight: '900' as const, letterSpacing: -0.5, lineHeight: 22, textTransform: 'uppercase' as const },

  // Secondary UI / Body (Space Grotesk equivalent / Inter)
  bodyL:  { fontFamily: INTER, fontSize: 16, fontWeight: '300' as const, letterSpacing: 0.5, lineHeight: 24 },
  bodyM:  { fontFamily: INTER, fontSize: 14, fontWeight: '300' as const, letterSpacing: 0.5, lineHeight: 20 },
  bodyS:  { fontFamily: INTER, fontSize: 12, fontWeight: '300' as const, letterSpacing: 0.5, lineHeight: 16 },

  // Labels / Captions (Medium weight 500)
  labelL: { fontFamily: INTER, fontSize: 13, fontWeight: '500' as const, letterSpacing: 0.5, lineHeight: 18 },
  labelM: { fontFamily: INTER, fontSize: 11, fontWeight: '500' as const, letterSpacing: 0.5, lineHeight: 14 },
  labelS: { fontFamily: INTER, fontSize: 10, fontWeight: '500' as const, letterSpacing: 1.0, lineHeight: 12, textTransform: 'uppercase' as const },

  // Mono
  monoL: { fontFamily: INTER, fontSize: 28, fontWeight: '500' as const, letterSpacing: -0.5, fontVariant: ['tabular-nums'] as any },
  monoM: { fontFamily: INTER, fontSize: 20, fontWeight: '500' as const, letterSpacing: -0.3, fontVariant: ['tabular-nums'] as any },
  monoS: { fontFamily: INTER, fontSize: 14, fontWeight: '500' as const, fontVariant: ['tabular-nums'] as any },
} as const;

// ── Spacing ───────────────────────────────────────────────────────────────────
export const Space = {
  xs:   4,  sm:   8,   md:  12,  base: 16,
  lg:  20,  xl:  24,  xxl: 32,  xxxl: 48,
  hero: 64, section: 40,
} as const;

// ── Border Radii ──────────────────────────────────────────────────────────────
export const Radius = {
  xs:   4,  sm:   8,  md:  12,  lg:  16,
  xl:  16,  xxl: 16,  pill: 999, card: 16, // Chroma-Noir standardizes on 16px
} as const;

// ── Shadows / Elevation ───────────────────────────────────────────────────────
export const Glow = {
  tealSm: {
    shadowColor:  Colors.teal,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.60,
    shadowRadius: 12,
    elevation: 8,
  },
  tealLg: {
    shadowColor:  Colors.teal,
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.80,
    shadowRadius: 32,
    elevation: 16,
  },
  goldSm: {
    shadowColor:  Colors.gold,
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.60,
    shadowRadius: 12,
    elevation: 8,
  },
  goldLg: {
    shadowColor:  Colors.gold,
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.75,
    shadowRadius: 32,
    elevation: 16,
  },
  magentaSm: {
    shadowColor:  Colors.magenta,
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.40,
    shadowRadius: 8,
    elevation: 6,
  },
  cardBase: {
    shadowColor: Colors.teal, // Optic Cyan subtle glow
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.30,
    shadowRadius: 12,
    elevation: 10,
  },
  hoverGlow: {
    shadowColor: Colors.teal, // Optic Cyan hover
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.50,
    shadowRadius: 12,
  }
} as const;

// ── Layout helpers ────────────────────────────────────────────────────────────
export const Screen = { width: SW, height: SH } as const;
export const isSmall = SW < 375;

// ── Z-index stack ─────────────────────────────────────────────────────────────
export const Z = {
  base:    0, card:     10, fab:      20,
  header:  30, modal:   40, toast:   50,
} as const;

// ── Animation durations ───────────────────────────────────────────────────────
export const Duration = {
  instant: 100,  fast:   200,  base:   300,
  slow:    500,  xslow:  800,  hero:   1200,
} as const;

import { Easing as RNEasing } from 'react-native-reanimated';

export const Easing = {
  // Chroma-Noir custom cubic-bezier: 0.16, 1, 0.3, 1 (Used for withTiming)
  bezier: RNEasing.bezier(0.16, 1, 0.3, 1),
  // Snappy spring config simulating physical hardware snaps
  spring: { damping: 14, stiffness: 220, mass: 0.8 },
  bouncy: { damping: 10, stiffness: 300, mass: 0.6 },
} as const;

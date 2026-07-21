// src/theme/ChromaNoirTheme.ts
// Canonical ChromaNoir design-token source of truth (QA §1.1).
//
// This resolves the "semantic colour trap" where `#B026FF` was historically
// named `teal`. The correct identity is `chromaViolet`. The legacy `Colors`
// map in `./dunda.ts` re-exports these values plus backward-compatible aliases
// so existing screens keep compiling during the migration.

export const ChromaNoirTokens = {
  colors: {
    // Base Canvas Surface
    void: '#000000', // True Black: pure base background
    abyss: '#060607', // Elevated cards, modular sheets, tab bars
    surface: '#08080A', // Content containers, table rows, inner frames

    // Content & Typography
    pureWhite: '#FCFCFD', // Primary headings, structural labels (Contrast 21:1)
    periwinkle: '#A99FB8', // Body copy, descriptions, placeholders (4.68:1 on Surface)

    // Accents & Semantic States
    chromaViolet: '#B026FF', // Primary accent, interactive active states, selection pills
    magentaAcid: '#FF1C5E', // Primary CTA, high urgency, conversions, sold-out
    goldPrestige: '#F4F800', // VIP tier status, badge highlights, premium countdowns
    opticCyan: '#00F0FF', // Linear refraction gradients, interactive toggles
    acidGreen: '#39FF14', // Success state, M-Pesa settlement, ticket scan-admitted
    deepPurple: '#C900FF', // Secondary gradient anchor
  },
  typography: {
    heading: {
      fontFamily: 'Oswald',
      weights: { bold: '700', heavy: '900' },
      letterSpacing: '-0.02em',
      transform: 'uppercase',
    },
    body: {
      fontFamily: 'Inter',
      weights: { light: '300', regular: '400', medium: '500' },
    },
    mono: {
      fontFamily: 'Inter-Mono',
      // Prevents layout jitter during countdowns / pricing changes.
      fontVariant: ['tabular-nums'],
    },
  },
  radius: {
    xs: 4,
    card: 16,
    pill: 999,
  },
} as const;

export type ChromaNoirColorToken = keyof typeof ChromaNoirTokens.colors;

export default ChromaNoirTokens;

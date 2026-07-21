// src/data/events.ts
// Shared mock data — single source of truth until the real API lands.
// Prices are in KES cents (e.g. 200000 = KSh 2,000).

import { AstralEvent } from '../components/AstralEventCard';
export type { AstralEvent, EventTier } from '../components/AstralEventCard';

const now = Date.now();
const DAY_MS = 86400000;

export const MOCK_EVENTS: AstralEvent[] = [
  {
    id: '1',
    name: 'Blankets & Wine Nairobi',
    venue: 'Ngong Racecourse',
    starts_at: new Date(now + DAY_MS * 4).toISOString(),
    price_kes: 200_000,
    tier_label: 'GENERAL',
    is_vip: false,
    remaining: 312,
    sold_out: false,
    cover_uri: 'https://picsum.photos/seed/bnw/800/600',
    genre_tag: 'Live Music',
    description: 'The most beloved outdoor music experience in Nairobi returns. Sip wine, spread your blanket, and lose yourself in world-class performances under the Nairobi sky. Curated lineups, artisan food, and a community of music lovers.',
    tiers: [
      { label: 'GENERAL ADMISSION', price_kes: 200000, sold: 1800, total: 2112, remaining: 312 },
    ]
  },
  {
    id: '2',
    name: 'Carnivore Music Festival',
    venue: 'Carnivore Grounds',
    starts_at: new Date(now + DAY_MS * 12).toISOString(),
    price_kes: 500_000,
    tier_label: 'VIP',
    is_vip: true,
    remaining: 14,
    sold_out: false,
    cover_uri: 'https://picsum.photos/seed/carnivore/800/600',
    genre_tag: 'Festival',
    description: 'Experience a massive three-day celebration of African music at the iconic Carnivore Grounds. Featuring top artists from across the continent, multiple stages, and the famous Carnivore hospitality.',
    tiers: [
      { label: 'REGULAR', price_kes: 250000, sold: 5000, total: 5000, remaining: 0 },
      { label: 'VIP', price_kes: 500000, sold: 486, total: 500, remaining: 14, vip: true },
    ]
  },
  {
    id: '3',
    name: 'Saturday Night Takeover',
    venue: 'The Alchemist',
    starts_at: new Date(now + 1000 * 60 * 60 * 4).toISOString(), // Tonight (4 hours from now)
    price_kes: 50_000, // Derived from MIN(price WHERE available > 0) -> 500 KES
    tier_label: 'GENERAL ADMISSION',
    is_vip: false,
    remaining: 183, // 20 + 160 + 3
    sold_out: false, // Fix: it's not sold out
    cover_uri: 'https://picsum.photos/seed/rezosh/800/600',
    genre_tag: 'Club Night',
    description: 'An electrifying club night featuring Nairobi\'s top DJs mixing the best of Amapiano, Afrobeats, and House. The Alchemist transforms into a glowing utopia for those who never want the night to end.',
    tiers: [
      { label: 'GENERAL ADMISSION', price_kes: 50000, sold: 180, total: 200, remaining: 20 },
      { label: 'VIP FRONT LAWN', price_kes: 250000, sold: 40, total: 200, remaining: 160, vip: true },
      { label: 'PLATINUM TABLE', price_kes: 500000, sold: 47, total: 50, remaining: 3, vip: true },
    ]
  },
  {
    id: '4',
    name: 'Afrobeats Underground',
    venue: 'KICC Rooftop',
    starts_at: new Date(now + DAY_MS * 2).toISOString(),
    price_kes: 150_000,
    tier_label: 'GENERAL',
    is_vip: false,
    remaining: 8,
    sold_out: false,
    cover_uri: 'https://picsum.photos/seed/afro/800/600',
    genre_tag: 'Afrobeats',
    description: 'Elevate your vibe at the KICC Rooftop. A premium underground Afrobeats experience high above the city. Stunning skyline views and infectious rhythms all night.',
    tiers: [
      { label: 'GENERAL', price_kes: 150000, sold: 392, total: 400, remaining: 8 },
    ]
  },
  {
    id: '5',
    name: 'Jazz in the Garden',
    venue: 'Alliance Française',
    starts_at: new Date(now + DAY_MS * 6).toISOString(),
    price_kes: 350_000,
    tier_label: 'VIP',
    is_vip: true,
    remaining: 50,
    sold_out: false,
    cover_uri: 'https://picsum.photos/seed/jazz/800/600',
    genre_tag: 'Jazz',
    description: 'An elegant afternoon of smooth jazz, contemporary art, and fine dining at Alliance Française. Perfect for a relaxing weekend with soothing saxophone melodies.',
    tiers: [
      { label: 'VIP', price_kes: 350000, sold: 150, total: 200, remaining: 50, vip: true },
    ]
  },
  {
    id: '6',
    name: 'Laugh Factory Nairobi',
    venue: 'Uhuru Gardens',
    starts_at: new Date(now + DAY_MS * 1).toISOString(),
    price_kes: 120_000,
    tier_label: 'GENERAL',
    is_vip: false,
    remaining: 180,
    sold_out: false,
    cover_uri: 'https://picsum.photos/seed/comedy/800/600',
    genre_tag: 'Comedy',
    description: 'Get ready for non-stop laughter as East Africa\'s funniest stand-up comedians take the stage. Food trucks, drinks, and hilarious punchlines in an open-air setting.',
    tiers: [
      { label: 'GENERAL', price_kes: 120000, sold: 820, total: 1000, remaining: 180 },
    ]
  },
  {
    id: '7',
    name: 'Nairobi Contemporary Art Fair',
    venue: 'Kasarani Stadium',
    starts_at: new Date(now + DAY_MS * 18).toISOString(),
    price_kes: 100_000,
    tier_label: 'GENERAL',
    is_vip: false,
    remaining: 600,
    sold_out: false,
    cover_uri: 'https://picsum.photos/seed/artfair/800/600',
    genre_tag: 'Art',
    description: 'Explore the vibrant creativity of the continent. A sprawling exhibition of modern African art, installations, and creative workshops.',
    tiers: [
      { label: 'GENERAL', price_kes: 100000, sold: 1400, total: 2000, remaining: 600 },
    ]
  },
  {
    id: '8',
    name: 'Tusker Safari Sevens',
    venue: 'K1 Klubhouse',
    starts_at: new Date(now + 1000 * 60 * 60 * 2).toISOString(), // Tonight (2 hours from now)
    price_kes: 300_000,
    tier_label: 'VIP',
    is_vip: true,
    remaining: 42,
    sold_out: false,
    cover_uri: 'https://picsum.photos/seed/sevens/800/600',
    genre_tag: 'Sports',
    description: 'Catch the intense rugby sevens action broadcast live while enjoying chilled Tusker and great company at K1. The ultimate sports fan experience.',
    tiers: [
      { label: 'VIP', price_kes: 300000, sold: 258, total: 300, remaining: 42, vip: true },
    ]
  },
];

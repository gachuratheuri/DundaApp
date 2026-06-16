# Dunda App — Complete UI/UX Architecture Map

> **Version:** 2.0.0 (Astral Dark / Chroma-Noir)  
> **Platform:** React Native (Expo SDK 52) + Web + Elixir/Phoenix Backend  
> **Date:** June 2026

---

## 1. Executive Summary

Dunda is a **Nairobi-centric live event discovery, ticketing, and resale platform** with a cyber-brutalist "Astral Dark" visual identity. It spans three surfaces:

| Surface | Tech | Audience |
|---------|------|----------|
| **Mobile App** | Expo Router + React Native | Event attendees (fans) |
| **Marketing Web** | Same RN codebase, web-optimized | Browsers / SEO |
| **Organiser Portal** | Phoenix LiveView (`/portal`) | Event promoters / venues |

---

## 2. Design System — "Astral Dark" (Chroma-Noir v2.0)

### 2.1 Color Palette

| Token | Hex | Usage |
|-------|-----|-------|
| `void` | `#000000` | True black base, backgrounds |
| `abyss` | `#060607` | Elevated surfaces |
| `surface` | `#08080A` | Cards, panels |
| `pureWhite` | `#FCFCFD` | Primary text |
| `periwinkle` | `#A99FB8` | Secondary/muted text (replaces flat gray) |
| `teal` (Acid Purple) | `#B026FF` | Primary accent, active states |
| `magenta` (Acid Magenta) | `#FF1C5E` | CTAs, urgency, sold-out |
| `gold` | `#F4F800` | VIP badges, prestige states |
| `opticCyan` | `#00F0FF` | Cyan in gradients only (spectral refraction) |
| `acidGreen` | `#39FF14` | Success, scan-admitted |
| `deepPurple` | `#C900FF` | Gradient accents |

### 2.2 Typography

- **Display / Headings:** Oswald (web), System Bold (native). Weights 700–900. Uppercase, tight letter-spacing (-2 to -0.5).
- **Body / UI:** Inter (web), System (native). Weight 300 for body, 500 for labels.
- **Mono:** Inter with `tabular-nums` for prices, countdowns, ticket IDs.

### 2.3 Core Visual Effects

| Effect | Implementation |
|--------|---------------|
| **Hollow / Stroke Text** | `-webkit-text-stroke: 2px rgba(255,255,255,0.25)` on web; faint translucent fill on native. Layered behind solid text for Z-axis depth. |
| **Prismatic Aurora** | Linear gradient rotation (4s loop) using `#8A2BE2 → #00F0FF → #FF1C5E`. |
| **Glassmorphism** | `expo-blur` (intensity 60–90, tint dark) + `rgba(6,6,7,0.5)` background + `1px rgba(255,255,255,0.08)` border. |
| **Tactile Noise** | SVG fractal noise overlay at 5% opacity, `mix-blend-mode: overlay` (web only). |
| **Kinetic 3D Tilt** | Reanimated `rotateX/Y` driven by gesture pan, with `perspective: 1000`. |
| **Ambient Drift** | Slow sine-wave rotation on cards (12s loop, ±2deg). |
| **Glow Shadows** | Custom shadow presets: `tealGlow`, `goldGlow`, `magentaGlow` — colored shadowOffset/shadowRadius. |

### 2.4 Border & Shape Language

- **Border radius:** Universally `16px` (`Radius.card`) for cards and panels. Pill (`999px`) for buttons and chips.
- **Borders:** `1px solid rgba(255,255,255,0.08)` is the standard glass border.
- **Elevation:** No Material shadows; instead use colored glows (teal/gold/magenta) against void black.

---

## 3. Navigation Architecture

### 3.1 Mobile App Routing (Expo Router)

```
Root Stack (headerShown: false)
├── (tabs)                           ← Bottom tab navigator
│   ├── index     → /                → DiscoverScreen (event feed)
│   ├── tickets   → /tickets         → TicketsScreen (wallet list)
│   └── profile   → /profile         → ProfileScreen (auth + settings)
├── event/[id]    → /event/123       → EventDetailScreen (modal presentation)
├── auth          → /auth            → Standalone auth screen
├── landing       → /landing         → Marketing landing page (web)
├── organiser     → /organiser       → Promoter landing (web)
└── faq           → /faq             → Searchable help center
```

### 3.2 Custom Bottom Tab Bar — `DundaTabs.tsx`

- **Style:** Floating glass pill, absolutely positioned `bottom: 24`, `left/right: 24`.
- **Background:** `expo-blur` intensity 90, dark tint, `rgba(10,10,12,0.5)`.
- **Border:** `1px solid rgba(255,255,255,0.4)`.
- **Tabs:**
  - `✦ Discover` — acid purple active
  - `⬡ Tickets` — acid purple active
  - `◉ Profile` — acid purple active
- **Active indicator:** Teal-colored text + 4px dot below.
- **Haptics:** Light impact on tab switch.

---

## 4. Screen-by-Screen UI/UX Breakdown

### 4.1 Discover Tab — `DiscoverScreen.tsx`

**File:** `frontend/src/screens/DiscoverScreen.tsx`  
**Route:** `/`  
**Purpose:** Primary event discovery feed.

#### Layout Hierarchy (top to bottom)

| Layer | Element | Details |
|-------|---------|---------|
| Background | Deep space gradient | `Gradients.deepSpace` (void → depth → abyss) |
| Ambient | Location glow + particle field | `LocationGlow` (300px cyan blur orb) + 25 SVG circles |
| Header (sticky) | Glass blur header | Fades in after 60px scroll. Contains location pill (Nairobi), "DUNDA" brand, profile avatar |
| Title | Cyber-Brutalist stack | Hollow stroke "What's On" behind solid "What's On" + "NAIROBI" subtitle |
| Search | Pill input + filter toggle | `☰ / ⊞` grid toggle. `border: 1px white10`, `bg: surface` |
| Categories | Horizontal pill list | FlatList of 12 pills: All, Tonight, This Week, Festival, Club Night, Afrobeats, Jazz, Comedy, Art, Sports, Live Music, VIP |
| Hero | `AstralEventCard` (variant=hero) | Dominant 460px card. Full-bleed cover, deep scrim, metadata at bottom |
| CTAs | Browse Events + Start Selling | Magenta primary, ghost secondary. Trust markers below (M-Pesa Native, Verified Organisers, Offline Tickets) |
| Rail | "Near You Tonight" | Horizontal FlatList of 3 `AstralEventCard` (compact, 200px) |
| Feed | "Don't Miss" | Vertical list of `AstralEventCard` (card, 320px) OR grid (240px) based on toggle |
| Empty state | Search icon + copy | "No events found. Try a different search or category." |
| SEO | FAQ section | 3 static FAQ items |

#### Interactions
- **Pull-to-refresh:** Fetches `/events` API, falls back to `MOCK_EVENTS`.
- **Category filter:** `filterByCategory` — date math for Tonight/This Week, genre tag match for others.
- **Search filter:** `filterBySearch` — matches `name` or `venue`.
- **Scroll-driven header:** Opacity interpolates `0 → 1` over first 60px via `useAnimatedScrollHandler`.

---

### 4.2 Event Detail — `EventDetailScreen.tsx`

**File:** `frontend/src/screens/EventDetailScreen.tsx`  
**Route:** `/event/[id]` (modal)  
**Purpose:** Full event info + checkout flow.

#### Layout Hierarchy

| Layer | Element | Details |
|-------|---------|---------|
| Hero (48vh) | Cyber-Brutalist Z-axis scene | Web: CSS `cb-scene-container` with hollow text, iridescent object, solid text. Native: Reanimated parallax translateY + 3D float |
| Sticky header | Back blur button + title + heart | Back: `blurBtn` (40px circle). Title: fades in at 50% hero scroll. Heart: blur button |
| Info grid | Date + Venue cards | `surface` background, glass border, emoji icons |
| About section | Description text | Periwinkle body, line-height 24 |
| Lineup | Artist rows | Avatar initials, name, arrow. Static mock data: Sauti Sol, Bien, Nviiri, Brandy Maina |
| Social | "Who's going?" | Overlapping avatars (J, A, M, K +12). Groups Chat + Invite Friends buttons |
| Tickets | Tier cards | Each tier: label, sold/total, `StockBar` (animated width), price. VIP tiers get gold border/price |
| Sticky CTA | Price + "Buy with M-Pesa" | `BlurView` intensity 80. Price label "From KSh X". Button: `bg: magenta`, sharp `Radius.xs`. Hover glow on web |

#### Checkout Flow (Modal Overlay)

| State | UI | Actions |
|-------|-----|---------|
| `none` | Hidden | — |
| `confirm` | "Select Tickets" modal | Stepper (+/-), phone input (+254 prefix), total price, "Confirm & Pay", Cancel |
| `escrow` | "Holding Spot" | Countdown ring (5:00), "Inventory locked in Redis escrow" |
| `waiting` | "M-Pesa STK Push" | Checklist: Reserved → Verifying PIN → Confirming Settlement. Polling `/checkout/:id/status` every 2s |
| `success` | Full-bleed green flash | "YOU'RE IN / Ticket Secured". Auto-navigates to `/tickets` after 1.5s |
| `failure` | "Haikufanikiwa" | Retry / Close. Swahili copy for local resonance |
| `waitlist_success` | Queued overlay | Position number, close button |

**Auth gate:** If unauthenticated, Alert prompts to go to `/profile`.

---

### 4.3 Tickets Tab — `tickets.tsx`

**File:** `frontend/src/app/(tabs)/tickets.tsx`  
**Route:** `/tickets`  
**Purpose:** Cryptographic ticket wallet.

#### Layout Hierarchy

| Layer | Element | Details |
|-------|---------|---------|
| Header | "My Tickets" + "Cryptographic Wallet" | `Font.h1` + `Font.labelM` in periwinkle |
| Tab bar | Upcoming / Past / Resale / Waitlist | Pill switcher. Active: `bg: tealDark`, `border: teal` |
| Ticket list | Stacked cards | Cards overlap with 12px stagger offset. VIP cards get `goldGlow` border |
| Card content | Event name, venue/date, tier badge, status dot | Status: Active (green) / Pending (gold). Past tab shows "Leave Review" button |
| Empty state | Hexagon icon + "Browse Events" CTA | `emptyIcon: ⬡` |
| Detail inline | `TicketVaultScreen` | Replaces list when card tapped. Back bar "← My Tickets" |

**Data:** Fetches `/tickets` API, falls back to `MOCK_TICKETS` (5 sample tickets including VIP, resale, waitlist).

---

### 4.4 Ticket Vault — `TicketVaultScreen.tsx`

**File:** `frontend/src/screens/TicketVaultScreen.tsx`  
**Route:** Inline within `/tickets`  
**Purpose:** Offline-verifiable QR ticket presentation.

#### Layout Hierarchy

| Layer | Element | Details |
|-------|---------|---------|
| Admitted overlay | Full-bleed green flash | `scanGreen` gradient, "✓ ADMITTED". 3s auto-dismiss |
| Rejected overlay | Full-bleed magenta | "✗ INVALID", "Get Help" button |
| Header | Back + "My Ticket" + Share | |
| Ticket card | `surface`, glass border | VIP gets gold `Glow.goldLg` + gold gradient top edge (3px) |
| Event meta | Name, venue, date/tier/holder | 3-column layout with dividers. VIP chip if applicable |
| Resale badge | Status pill | Teal border if `resale_status` != none |
| Tear line | Dashed border + circle cutouts | Ticket aesthetic |
| QR vault | Centerpiece | `QRCode` (white bg, black fg, quietZone 10). Size: `min(screenWidth - 64, 280)` |
| Aurora border | Rotating gradient | `AuroraBorder` component. 4s linear rotation loop around QR |
| TOTP countdown | SVG ring | `CountdownRing`: 30s arc, color shifts teal → gold → magenta as time expires |
| TOTP label | "QR refreshes in Xs" | Live text with pulsing dots |
| Ticket ID | Monospace ID + Sell button | "Sell Ticket" triggers bottom-sheet resale modal |
| Wallet buttons | Apple + Google Wallet | Mock 2s generation, success alert |
| Info banner | `BlurView` | Lock icon: "This QR code rotates automatically. Screenshots will not work at the gate." |
| Dev sim | Gate scan buttons | Simulate Admission / Rejection |

#### Interactions
- **3D QR Tilt:** `GestureDetector` pan maps touch position to `rotateX/Y` (±15deg). Spring release on lift.
- **TOTP:** RFC 6238 via `useTicketTOTP(jwt)`. Secret extracted from JWT payload `totp_secret` claim. 30s period.
- **Resale bottom sheet:** Price capped at face value. "Confirm Listing" → POST `/resale/listings`.

---

### 4.5 Profile Tab — `profile.tsx`

**File:** `frontend/src/app/(tabs)/profile.tsx`  
**Route:** `/profile`  
**Purpose:** Authentication + user settings + privacy compliance.

#### Unauthenticated State

| Element | Details |
|---------|---------|
| Brand | "DUNDA" in `displayL`, acid purple, letter-spacing 4 |
| Tabs | Phone / Email switcher. Pill style, `tealDark` active |
| Phone flow | +254 prefix input → "SEND CODE" → OTP 4-digit input → "LOGIN" |
| Email flow | Full name (register), email, password. Toggle Register/Sign In. "Forgot Password?" link |
| Submit | `bg: magenta`, `Radius.pill`, 56px height. Loading state: "WAITING..." / "VERIFYING..." |

#### Authenticated State

| Section | Elements |
|---------|----------|
| User card | Avatar (initials), name, "Attendee Account", "✓ Verified" KYC chip (green) |
| Stats row | 3 stat cards: Events Attended, Upcoming, Resale Active. `teal` values |
| ODPC Privacy Portal | Kenya Data Protection Act compliance. 3 action rows: Request Access, Correct Info, Request Erasure. Each with icon, label, description, chevron |
| Preferences | Push Notifications (toggle ON/OFF), Dark Mode (always ON — "Chroma-Noir") |
| FAQ | 5 expandable items with `LayoutAnimation` (Android experimental enabled). Buying, Transfer, Refunds, QR, Organiser |
| Logout | Magenta text "Log Out". Clears token + user from AsyncStorage |
| DPO Banner | `BlurView` intensity 24. DPO contact: `dpo@dunda.app`, registration `ODPC/REG/2026/0894` |

---

### 4.6 Auth Screen — `auth.tsx`

**File:** `frontend/src/app/auth.tsx`  
**Route:** `/auth`  
**Purpose:** Standalone authentication entry point.

- Same UI as Profile's auth state but with back navigation (← Back).
- On success: `router.replace('/profile')`.

---

### 4.7 Marketing Landing — `landing.tsx`

**File:** `frontend/src/app/landing.tsx`  
**Route:** `/landing`  
**Purpose:** SEO + conversion landing page (web-primary).

#### Sections

| Section | Content |
|---------|---------|
| Nav | "DUNDA" logo + "Launch App" button (`tealDark` pill) |
| Hero | Hollow/solid "WHAT'S ON" stack + "IN NAIROBI" + subheadline. 2 CTAs: "Browse Events →" (magenta), "Start Selling" (ghost). Social proof: "47,000+ Nairobians · 1,200+ events · 98% checkout success" |
| Phone mockup | Web-only. `Animated.View` with `perspective: 1000`, `rotateX/Y` drift (6s loop). Simulated event card inside BlurView |
| Partners | Strip: THE ALCHEMIST, MUZE, CARNIVORE, KICC ROOFTOP |
| How It Works | 3-step grid (01 Discover / 02 Buy Securely / 03 Show QR) |
| Split panel | For Fans (teal) + For Promoters (gold). CTAs to app and portal |
| Testimonials | Rotating quotes (5s interval). Large teal quotation marks |
| FAQs | 3 expandable items with `details/summary` (web) or Pressable (native) |

---

### 4.8 Organiser Landing — `organiser.tsx`

**File:** `frontend/src/app/organiser.tsx`  
**Route:** `/organiser`  
**Purpose:** Promoter conversion page.

- Hero: "SELL TICKETS. KEEP THE REVENUE." with live badge (green pulse dot).
- Primary CTA: "OPEN ORGANISER PORTAL" → links to `localhost:4000/portal`.
- Features: Instant M-Pesa Payouts, Zero Setup Fees, Live Escrow Telemetry, Bot & Scalper Proof. MaterialCommunityIcons.
- Social proof: BLANKETS & WINE, THE ALCHEMIST, MUZE.
- Floating action bar: `BlurView` with "Ready to publish?" + "CREATE EVENT".

---

### 4.9 FAQ Center — `faq.tsx`

**File:** `frontend/src/app/faq.tsx`  
**Route:** `/faq`  
**Purpose:** Searchable help center.

- Search bar with `⌕` icon, pill shape.
- 5 sections: Buying & Payments, Wallet & Gate Entry, Reselling & Capping, Refund Policy, For Organisers.
- Expandable cards with `+ / −` toggle.
- FAQ data covers: M-Pesa STK, offline tickets, QR scanning, resale price caps, refund timelines, scraper, payouts.

---

## 5. Component Library

### 5.1 Core Components

| Component | File | Props | Behavior |
|-----------|------|-------|----------|
| `AstralEventCard` | `components/AstralEventCard.tsx` | `event`, `onPress`, `variant` | 4 variants: `hero` (460px), `card` (320px), `compact` (200px rail), `grid` (240px). ImageBackground with deep scrim. Pan + Tap gestures for 3D tilt + haptic. Pulsing dot for low stock. VIP gold gradient badge. Genre chip. |
| `AstralModal` | `components/AstralModal.tsx` | `visible`, `title`, `message`, `actionLabel`, `onAction`, `onClose` | Blur overlay. Reanimated spring entry: translateY 100→0, scale 0.9→1, rotateX 30→0. Cancel + Confirm buttons. |
| `HollowText` | `components/HollowText.tsx` | `children`, `size`, `strokeWidth`, `strokeColor` | Web: `-webkit-text-stroke` + transparent fill. Native: faint translucent fill. Oswald, 900 weight, uppercase. |
| `PrismGlassPanel` | `components/PrismGlassPanel.tsx` | `children` | `BlurView` 80 intensity + cyan-magenta gradient overlay + 1px white10 border. Hardware texture on Android. |
| `DundaTabs` | `navigation/DundaTabs.tsx` | `active`, `onChange` | Floating blur pill tab bar. 3 tabs. Haptic on switch. |

### 5.2 Animated Patterns

| Pattern | File | Tech |
|---------|------|------|
| Parallax hero | `EventDetailScreen.tsx` | `useAnimatedScrollHandler` → `translateY` interpolate |
| Sticky header fade | `DiscoverScreen.tsx` | Scroll-driven opacity + borderBottomColor |
| 3D card tilt | `AstralEventCard.tsx` | `Gesture.Pan` → `interpolate(e.y, [0, height], [8, -8])` → `rotateX/Y` |
| Ambient drift | `AstralEventCard.tsx` | `withRepeat` sine/cosine on `ambientT` (12s loop) |
| Kinetic float | `EventDetailScreen.tsx` | `withRepeat` withSequence `translateY` ±20px (8s loop) |
| Phone drift | `landing.tsx` | `rotateX/Y` ±5deg (6s loop) |
| TOTP ring | `TicketVaultScreen.tsx` | `AnimatedCircle` with `strokeDashoffset` interpolate |
| Aurora rotation | `TicketVaultScreen.tsx` | `withRepeat` `rotate: 360deg` (4s linear) |
| Entry spring | `TicketVaultScreen.tsx` | `withSpring` translateY 60→0 + opacity 0→1 |
| CountUp | Organiser Portal (web) | JS `requestAnimationFrame` cubic ease-out hook |

---

## 6. User Flows

### 6.1 Discovery → Purchase Flow

```
[Discover Tab]
    ↓ tap event
[Event Detail]
    ↓ "Buy with M-Pesa"
[Auth Gate] (if unauthenticated)
    → Alert → navigate to /profile
    ↓ authenticated
[Confirm Modal]
    → Select quantity, confirm phone
    ↓ "Confirm & Pay"
[Escrow State]
    → POST /checkout, get transaction_id
    → Redis inventory lock, 5-min countdown
    → M-Pesa STK push sent
[Waiting State]
    → Poll GET /checkout/:id/status every 2s (max 30 attempts)
    → Checklist UI: Reserved → Verifying → Confirming
[Success / Failure]
    → Success: full-bleed green, navigate to /tickets
    → Failure: "Haikufanikiwa", retry or cancel
```

### 6.2 Ticket Vault → Gate Entry Flow

```
[Tickets Tab]
    ↓ tap active ticket
[Ticket Vault Screen]
    → Live QR code (JWT + TOTP)
    → TOTP refreshes every 30s
    → 3D tilt on touch
    → Countdown ring (teal → gold → magenta)
[Gate Scan]
    → Scanner reads QR payload
    → Validates TOTP server-side (or offline via cached secret)
    → Success: full-bleed green "ADMITTED"
    → Failure: magenta "INVALID"
```

### 6.3 Resale Flow

```
[Ticket Vault]
    ↓ "Sell Ticket"
[Resale Bottom Sheet]
    → Price capped at face value (KSh 2,500)
    → "Confirm Listing"
    → POST /resale/listings
    → Ticket status → 'resale_pending'
[Tickets Tab → Resale filter]
    → Shows listed ticket with "LISTING: PENDING" badge
```

### 6.4 Authentication Flow

```
[Profile Tab]
    → Phone tab: +254 input → SEND CODE → OTP verify → token stored
    → Email tab: name/email/password → REGISTER or SIGN IN → token stored
    → Token persisted in AsyncStorage (@dunda_token)
    → User object cached (@dunda_user)
[Logout]
    → Remove token + user. Reset all auth state.
```

---

## 7. Organiser Portal (Web — Phoenix LiveView)

**Base URL:** `/portal`  
**Layout:** `DundaWeb.Layouts.root` — Tailwind CDN, custom dark theme, sticky header, LiveSocket inline.

### 7.1 Portal Pages

| Route | LiveView | Purpose |
|-------|----------|---------|
| `/portal` | `DashboardLive` | KPIs (Revenue, Tickets Sold, Conversion, Active Events), live sales ticker, scraper pulse, escrow telemetry |
| `/portal/onboarding` | `OnboardingLive` | 4-step wizard: Organisation Details → Branding → M-Pesa Till → Agreement |
| `/portal/events` | `EventsLive` | Event catalog listing |
| `/portal/events/new` | `EventEditorLive` (action=:new) | Create event: Core Details → Cover Upload → Ticket Tiers → Extras. Live mobile preview (phone simulator) |
| `/portal/events/:id/edit` | `EventEditorLive` (action=:edit) | Edit existing event |
| `/portal/events/:id/extras` | `ExtrasLive` | Upsell management |
| `/portal/events/:id/tickets` | `TicketsLive` | Ticket inventory & scan log |
| `/portal/analytics` | `AnalyticsLive` | Charts & conversion data |
| `/portal/payouts` | `PayoutsLive` | M-Pesa disbursement history |
| `/portal/scraper` | `ScraperLive` | Facebook/IG/Eventbrite sync config |
| `/portal/team` | `TeamLive` | Team members & roles |
| `/portal/health` | `HealthLive` | System status |
| `/portal/support` | `SupportLive` | Help center |

### 7.2 Portal Design Language

- Same color tokens as mobile: `voidblack`, `abyssnavy`, `opticyan`, `nebulamagenta`, `acidgreen`, `solfeggiogold`.
- Tailwind classes: no custom CSS build; all inline via CDN + `<style>` block.
- Cards: `border-white/10 bg-abyssnavy`.
- Buttons: Sharp corners (`rounded-none`), `glow-cyan` / `glow-magenta` utility classes.
- Typography: Oswald for display (uppercase, tracking-tighter), Inter for UI.

---

## 8. API Surface Supporting the UI

### 8.1 Public API (`/api` — no auth)

| Endpoint | Method | UI Consumer |
|----------|--------|-------------|
| `/auth/register` | POST | Profile/Auth email registration |
| `/auth/login` | POST | Profile/Auth email login |
| `/auth/otp/send` | POST | Profile/Auth phone OTP |
| `/auth/otp/verify` | POST | Profile/Auth phone verify |
| `/events` | GET | DiscoverScreen event feed |
| `/events/:id` | GET | EventDetailScreen |
| `/billing/orders` | POST | Pesapal hosted checkout |
| `/mpesa/callback` | POST | M-Pesa server-to-server |
| `/pesapal/ipn` | GET/POST | Pesapal IPN |

### 8.2 Authenticated API (`/api` + `AuthPlug`)

| Endpoint | Method | UI Consumer |
|----------|--------|-------------|
| `/tickets` | GET | TicketsScreen, TicketVaultScreen |
| `/checkout` | POST | EventDetailScreen purchase |
| `/checkout/:id/status` | GET | EventDetailScreen polling |
| `/resale/listings` | GET/POST | TicketVaultScreen resale |
| `/resale/listings/:id/buy` | POST | Resale marketplace |

### 8.3 Data Flow

- **Events:** `Dunda.Events.list_events/0` → reads from `ReadRepo` (replica) + annotates `remaining` from Redis.
- **Tickets:** `Dunda.Ticketing.list_user_tickets/1` → preloads event, returns JWT entitlements.
- **Checkout:** `CheckoutController.create/2` → validates user, creates order, triggers M-Pesa STK push, returns transaction_id.
- **Auth:** `AuthController` — email/password (bcrypt) + phone OTP + Google OAuth. JWT token via `ApiClient.setToken`.

---

## 9. State Management & Hooks

### 9.1 Custom Hooks

| Hook | File | Purpose |
|------|------|---------|
| `useTicketTOTP` | `hooks/useTicketTOTP.ts` | RFC 6238 TOTP from JWT `totp_secret`. 30s period, 6 digits, HMAC-SHA1. |
| `useEvents` | `hooks/useEvents.ts` | `useResource` wrapper for `/events`. Falls back to `SAMPLE_EVENTS`. |
| `useTickets` | `hooks/useTickets.ts` | `useResource` wrapper for `/tickets`. Falls back to `[SAMPLE_TICKET]`. |
| `useResource` | `hooks/useResource.ts` | Generic data hook: loading/error/data/refetch. Graceful degradation to fallback. |
| `useTheme` | `hooks/use-theme.ts` | Returns light/dark colors. Always returns dark (Chroma-Noir). |

### 9.2 API Client

**File:** `api/client.ts`

- Base URL: `http://localhost:4000/api` (web), `http://10.0.2.2:4000/api` (Android emulator).
- Token storage: `@dunda_token` in AsyncStorage.
- User cache: `@dunda_user` in AsyncStorage.
- Methods: `get()`, `post()`, `request()` with automatic `Authorization: Bearer <token>` header.

---

## 10. Haptics & Micro-interactions

| Interaction | Haptic Style | Location |
|-------------|------------|----------|
| Tab switch | `Light` | `DundaTabs.tsx` |
| Category select | `Light` | `DiscoverScreen.tsx` (implicit) |
| Event card press begin | `Light` | `AstralEventCard.tsx` (pan gesture) |
| Buy button | `Medium` | `EventDetailScreen.tsx` |
| Confirm purchase | `Heavy` | `EventDetailScreen.tsx` |
| Checkout waiting | `Warning` notification | `EventDetailScreen.tsx` (native only) |
| Checkout success | `Success` notification | `EventDetailScreen.tsx` (native only) |
| Checkout failure | `Error` notification | `EventDetailScreen.tsx` (native only) |
| Ticket card press | `Light` | `TicketsScreen.tsx` |
| Review star tap | `Light` | `TicketsScreen.tsx` |
| Review submit | `Heavy` | `TicketsScreen.tsx` |
| Auth tab switch | `Light` | `ProfileScreen.tsx`, `AuthScreen.tsx` |
| Send OTP | `Medium` | `ProfileScreen.tsx`, `AuthScreen.tsx` |
| Verify OTP / Login | `Heavy` | `ProfileScreen.tsx`, `AuthScreen.tsx` |
| Logout | `Heavy` | `ProfileScreen.tsx` |
| Privacy action | `Light` | `ProfileScreen.tsx` |
| Push toggle | `Light` | `ProfileScreen.tsx` |
| FAQ expand | `Light` | `ProfileScreen.tsx` |
| Landing CTA | `Medium/Light` | `landing.tsx` |
| Gate scan sim (success) | `Heavy` + `Success` notification | `TicketVaultScreen.tsx` |
| Gate scan sim (failure) | `Heavy` + `Error` notification | `TicketVaultScreen.tsx` |
| Wallet add | `Light` then `Heavy` | `TicketVaultScreen.tsx` |
| Resale confirm | `Success` notification | `TicketVaultScreen.tsx` |
| QR pan gesture | `Light` | `TicketVaultScreen.tsx` |

---

## 11. Accessibility & Platform Considerations

### 11.1 Accessibility

- `accessibilityRole="button"` on cards and tabs.
- `accessibilityLabel` on `AstralEventCard` includes name, venue, date, price, stock status.
- `accessibilityState={{ selected }}` on tab items.
- Reduced-motion safe: animations are decorative; no motion is required for functionality.

### 11.2 Platform Differences

| Feature | Web | Native |
|---------|-----|--------|
| Hollow text | `-webkit-text-stroke` true outline | Faint translucent fill fallback |
| Hero scene | Pure CSS (`cb-scene-container` divs) | Reanimated `View` + `ImageBackground` |
| Blur | `backdrop-filter` + `mix-blend-mode` | `expo-blur` `BlurView` |
| Haptics | No-op (`Platform.OS !== 'web'`) | `expo-haptics` full suite |
| Notifications | No-op | `Haptics.notificationAsync` |
| Phone mockup | Visible in `landing.tsx` | Hidden (`Platform.OS === 'web'` guard) |
| FAQ expand | Native `<details>` element | Pressable with state toggle |
| StatusBar | N/A | `barStyle="light-content"`, `backgroundColor: Colors.void` |
| SafeArea | N/A | `react-native-safe-area-context` on all screens |

### 11.3 Web-Specific CSS (in `_layout.tsx`)

- Google Fonts loaded: Inter (300, 500), Oswald (700, 900).
- CSS custom properties: `--void-black`, `--periwinkle-accent`, `--electric-yellow`, etc.
- Keyframes: `cb-spectralShift` (gradient position + 3D rotate + scale), `cb-floatObject` (vertical drift).
- `cb-scene-container`: `perspective: 1000px`, `transform-style: preserve-3d`.

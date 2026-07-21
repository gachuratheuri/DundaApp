# Dunda — Mobile App (Expo / React Native)

The Dunda attendee app: discover live events, buy tickets, and present a
rotating cryptographic QR at the door. Built with Expo Router (file-based
routing) and the **Prismatic Brutalism** design language.

> Targets Expo SDK 54. Read the versioned docs at
> https://docs.expo.dev/versions/v54.0.0/ before making changes (see `AGENTS.md`).

## Stack

| Concern | Choice |
|---|---|
| Framework | Expo SDK 54, React Native 0.81, React 19 |
| Routing | `expo-router` native tabs (`Discover`, `Tickets`) |
| Animation | `react-native-reanimated` v4 (UI-thread worklets) |
| QR / crypto | `react-native-qrcode-svg`, protocol-v2 device-bound Ed25519 proofs, native Keychain/Keystore adapters |
| Design tokens | `src/theme/dunda.ts` (typed source of truth) |

## Getting started

```bash
npm install
npx expo start
```

Then open on an Android emulator, iOS simulator, Expo Go, or the web (`w`).

## Project structure

```
src/
  app/            # Routes: index.tsx (Discover feed), explore.tsx (Ticket wallet)
  components/     # EventCard, PrismGlassPanel, themed primitives
  screens/        # TicketScreen (cryptographic QR vault)
  hooks/          # device-bound QR proof lifecycle
  theme/dunda.ts  # Canonical design tokens
  types/domain.ts # DundaEvent, DundaTicket
  data/sample.ts  # Placeholder data until the API is wired in
```

## Brand fonts

The design system references **Clash Display ExtraBold** (display) and
**JetBrains Mono** (data/mono). Add the `.ttf` files under
`assets/fonts/` and load them with `expo-font` in `src/app/_layout.tsx`. Until
then the app gracefully falls back to the platform default fonts.

## Quality gates

```bash
npm run typecheck   # tsc --noEmit
npm run lint        # eslint (flat config)
```

## Connecting the backend

The app talks to the Dunda Elixir API (see `../backend`) via `src/api/client.ts`.
Data flows through `useEvents` / `useTickets`. Discovery may use sample events
in development, but ticket data is never fabricated offline and an unbound
ticket cannot render a usable QR.

Set the API base URL with an environment variable:

```bash
# .env (or shell)
EXPO_PUBLIC_API_URL=http://localhost:4000
```

Resolution order (see `src/constants/config.ts`): `EXPO_PUBLIC_API_URL` →
dev-only fallback (`http://10.0.2.2:4000` on Android emulators,
`http://localhost:4000` elsewhere). `app.json` contains no API origin.
Non-development EAS profiles must set an explicit `https://` origin in their
`env` block or the app throws on startup by design. Origins containing paths or
embedded credentials are rejected. The Phoenix WebSocket URL is derived from
the same origin.
The Phoenix WebSocket URL is derived from the same origin. Endpoints consumed:

| Hook / call | Endpoint |
|---|---|
| `useEvents()` | `GET /api/events` |
| `useTickets()` | `GET /api/tickets` |
| `checkout()` | `POST /api/checkout` |

The `DundaEvent` / `DundaTicket` types in `src/types/domain.ts` define the
contract shared with the backend JSON views.

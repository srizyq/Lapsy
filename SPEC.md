# Lapsy v1 spec

Status: draft for approval. Nothing is built yet.

## 1. Product

Lapsy generates a random route from a location the user picks, for any activity, guides them along it turn by turn, and records the workout to Apple Health. Native iPhone app (SwiftUI), launched worldwide on the App Store. Name: **Lapsy**. Plain-word copy throughout.

## 2. Decisions locked

- Native iOS, SwiftUI, iOS only for v1.
- Maps: MapKit (map, search, GPS drawing). CoreLocation for GPS.
- Routing: OpenRouteService or GraphHopper (OSM based), called through a Supabase edge function so the key is never in the app.
- Backend: Supabase (auth, Postgres, storage, edge functions).
- Accounts required. Sign in with Apple, email, Google.
- Local cache: SwiftData. Supabase is the source of truth.
- Health: HealthKit. Heart rate, workouts and other health data stay on the device. Only route and activity summaries sync.
- Monetisation: monthly Pro subscription (StoreKit 2). Free and Pro split and trial are deferred.
- Apple Watch app: v1.1.
- Club share, public profiles: later. v1 shares by link or GPX.

## 3. Design system

| Token | Value |
|---|---|
| Neutral (background) | `#121317` |
| Primary | `#D4B996` |
| Secondary | `#C6A679` |
| Tertiary | `#E6D5C3` |
| Destructive | soft coral red |
| Headline font | Space Grotesk |
| Body font | Geist |
| Label font | JetBrains Mono |

- Flat panels, 1px hairline borders, tight corners (about 4-6pt), tabular numerals, small mono caps labels.
- Buttons: Primary (cream fill), Secondary (dark), Inverted (light gray), Outlined (hairline).
- Thin cream progress bars. Floating pill tab bar, selected tab is a cream square.
- Fonts bundled in the app (all open source).
- Each color has a 10 step ramp for pressed and disabled states.

## 4. Navigation

Four tabs. Profile is the avatar button at top right of every tab.

| Tab | Purpose |
|---|---|
| Generator | Pick activity, start point, distance, path type. Generate, preview, start. Recent runs list. |
| Live Run | Active workout: turn banner, mini map, progress, pace, time, heart rate, slide to pause. Empty state when no run is active. |
| Activity | Weekly stats, volume chart, surface split, logged runs with detail. |
| Saved | Search and filter saved routes, rating, share, export. |

## 5. Screens

1. **Sign in**: Apple, Google, email. Required before anything else.
2. **Onboarding**: location permission, Health permission, units, basic body info (optional).
3. **Generator**: activity chips, start point (current or search), distance slider, route shape (loop, out and back, point to point), path type, avoid toggles, Generate, Regenerate. Route preview with surface mix, elevation profile scrubber, projected time and energy.
4. **Live Run**: turn banner, map following the user, objective progress, pace, time, heart rate, cadence, energy, pause and finish, off-route rerouting.
5. **Run summary**: distance, time, pace, heart rate graph and zones (from Health), surface mix, elevation, rate this route, save, share.
6. **Activity**: week / month / year / all-time, volume bars, route discovery, logged runs, run detail with splits and GPX export.
7. **Saved**: search, filters (favorites, distance, surface), saved route detail, rating, share link, GPX export.
8. **Profile**: avatar, display name, streak; lifetime distance, total runs, member since; units, default activity, home location; weight, age, max heart rate (optional, can read from Health); subscription status and manage; sign out; delete account.

## 6. Activities

Data driven list. Each activity has a name, icon, Health workout type, and a routing profile or none.

| Group | Examples | Routing profile |
|---|---|---|
| Foot | Walk, run, trail run, hike | foot-walking, foot-hiking |
| Wheels | Road bike, gravel, mountain bike, e-bike | cycling-road, cycling-regular, cycling-mountain, cycling-electric |
| Accessible | Wheelchair | wheelchair |
| Track only | Kayak, ski, skate, row, swim, and others | none (GPS tracking only, no generated route) |

Track-only activities skip the route preview and go straight to Live Run with an open-ended workout.

## 7. Route generation

- Input: start point, distance, activity profile, shape, path type, avoid options, seed.
- Request goes to a Supabase edge function, which checks the user and rate limit, then calls the routing API and returns geometry, steps, surface and elevation data.
- Regenerate = new seed. Generate several candidates, score them (doubling back, dead ends, surface match, distance error) and show the best.
- Path type maps to profile options and avoid features (steps, busy roads, unpaved).
- Data extras (lit streets, canopy, water, restrooms) come from OSM tags. Show them only where data exists, otherwise hide.
- Turn banner is driven by the API step list. Off-route triggers a re-request from the current position.
- Attribution to OpenStreetMap shown in the app.

## 8. Data model (Supabase)

- `profiles`: id (auth user), display_name, avatar_url, units, default_activity, home_location, weight_kg, age, max_hr, created_at
- `routes`: id, user_id, name, activity, shape, distance_m, geometry, elevation_gain, surface_mix, created_at
- `activities`: id, user_id, route_id (nullable), activity_type, started_at, duration_s, distance_m, avg_pace, energy_kcal, polyline, surface_mix. No heart rate stored.
- `ratings`: id, user_id, route_id, stars, created_at
- `shared_links`: id, route_id, token, created_at
- Row level security on every table: users read and write only their own rows. Shared links readable by token.
- Streak is computed from `activities`.

## 9. Account rules

- Required sign up. Review notes justify it with sync, Pro and saved routes.
- In-app account deletion removes all server data.
- Privacy policy, App Store privacy labels, location and Health usage strings.
- Offline: runs record with no signal and sync later through a queue.

## 10. Risks

- Loop quality (doubling back, dead ends).
- Routing API cost at scale, so per-user rate limits from day one.
- Battery drain from background GPS.
- Patchy OSM tag coverage for the data extras.
- Required accounts may draw App Store review pushback.
- Needs a real iPhone for GPS and HealthKit testing.

## 11. Build order

0. Xcode project, git, design tokens, fonts, tab bar shell.
1. Route generation test: edge function plus MapKit drawing. Riskiest, done first.
2. Auth and profile (Supabase, three providers).
3. Generator and preview screens.
4. Live Run: GPS, turn banner, rerouting, background location.
5. Health: permissions, workout session, save to Health, summary.
6. Activity and Saved screens, sync, ratings, share links, GPX export.
7. Subscription (StoreKit 2) and gating.
8. Polish, privacy, TestFlight, App Store submission.

## 12. Open items

- Free and Pro split, price and trial (deferred).
- Which routing provider (ORS hosted, ORS self-hosted, GraphHopper), decided after the cost check in step 1.
- Apple Developer account ($99 a year) needed from step 2 for Sign in with Apple, and for TestFlight.
- Real iPhone and Apple ID for device testing.

# Roadmap: RescueLink

## Phase 1: Foundation & BLE Bridge
- **Goal:** Establish a reliable BLE connection between the Flutter app and the ESP32 node.
- **Tasks:**
  - [x] Implement BLE scanning and auto-connect logic.
  - [x] Define BLE service and characteristic structure.
  - [x] Create a "Mesh Connection" status screen.
  - [x] Implement a basic handshake protocol.

## Phase 2: SOS & Payload Design
- [x] Integrate `geolocator` for precise coordinate gathering.
- [x] Develop the SOS UI (GPS, Health, Person Count).
- [x] Implement compact packet formatting for LoRa transmission.
- [x] Add basic local persistence for SOS history.

## Phase 3: Mesh Integration & Queue
- [x] Implement an outgoing message queue for the mesh (Simplified: Single reliable SOS with Cooldown).
- [x] Create UI for incoming HQ announcements and status updates.
- [x] Develop multi-hop status visualization (e.g., "In-transit").

## Phase 4: Profile & Local Services
- **Goal:** Manage user data and provide local emergency features.
- **Tasks:**
  - [x] Implement `LocaleService` for TR/EN support.
  - [x] Create `ProfileScreen` for personal data and emergency contacts.
  - [x] Implement `WhistleService` (Fixed 5-second burst).
  - [x] Develop `ConnectivityService` and `SmsQueueService` for offline alerts.
  - [x] Implement **BLE Foreground Service** to keep background listening alive.

## Phase 5: Offline Mapping & Location
- **Goal:** Provide a functional offline map for location selection.
- **Tasks:**
  - [x] Integrate `flutter_map` with an MBTiles base map.
  - [x] Implement **Smart Map Prompt** (City detection + MBTiles download prompt).
  - [x] Build a manual "Location Picker" interface.

## Phase 6: UI Refinement & Hardening
- [x] Implement **Binary Payload Encoding** (Byte/Hex array) for all SOS data.
- [x] Apply the High-Contrast Material 3 theme across all screens.
- [x] Implement comprehensive error handling for BLE/Mesh failures.
- [x] Conduct E2E testing with simulated mesh nodes.

## Phase 7: Survival & Resilience Optimizations (V1.7.0)
- **Goal:** Maximize battery life and transmission reliability.
- **Tasks:**
  - [x] Implement **Dynamic GPS Sleep-Wake** logic via accelerometer.
  - [x] Develop **Critical Battery Survival Mode** (<= 15%) with AMOLED black theme.
  - [x] Implement **Siren Volume Throttling** for battery conservation.
  - [x] Enhance **BLE Retry Queue** for automated background recovery.
  - [x] Apply **Strict Anti-Spam** payload validation to prevent mesh congestion.

**V1.7.0 STABLE - Ready for Field Testing**

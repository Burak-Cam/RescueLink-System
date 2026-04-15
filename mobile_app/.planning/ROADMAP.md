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

## Phase 7: Survival & Resilience Optimizations (V1.7.3)
- **Goal:** Maximize battery life and hardware-software synchronization.
- **Tasks:**
  - [x] Implement **Watchdog (0x0E Heartbeat)**: Monitor hardware health every 60s.
  - [x] Develop **%15 Battery 'Koma' Mode**: Disable accelerometer movement detection to save power.
  - [x] Implement **Emergency GPS Wake**: Force high-accuracy 10s fix only on SOS or Earthquake.
  - [x] Fix **GPS Status Persistence**: Maintain 'Fixed' status indicator during sleep cycles.
  - [x] Production UI Cleanup: Remove all debug/developer labels.

## Phase 8: Field Intelligence & Network (Upcoming)
- [ ] **Smart BLE Packet Priority**: Prioritize emergency packets in the transmission queue.
- [ ] **Micro-Map Auto-Download**: Background download of a 2km radius map for the user's registered home.
- [ ] **Field Data Analysis**: Analyze signal penetration from simulated rubble environments.
- [ ] **Mesh Delivery Feedback**: Implement visual confirmation when a message hops through multiple nodes.

**V1.7.3 OPTIMIZED - Production Ready**

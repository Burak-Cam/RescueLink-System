# Roadmap: RescueLink

## Phase 1: Foundation & BLE Bridge
- [x] Implement BLE scanning and auto-connect logic.
- [x] Define UART-based communication protocol.
- [x] Build onboarding and MAC persistence.

## Phase 2: Core Survival Logic
- [x] Implement SosStatusService (State Machine).
- [x] Build GpsService with emergency wake locks.
- [x] Create SmsQueueService for telemetry storage.

## Phase 3-7: Hardening & Optimization
- [x] Heartbeat Watchdog (0x0E).
- [x] Battery-Aware GPS Management.
- [x] High-Volume Siren (Whistle) Integration.
- [x] Auto-Reconnection & Persistent Profile.

## Phase 8: Field Intelligence & Network (ACTIVE)
- [x] **Smart BLE Packet Priority**: High-priority SOS packets bypass routine telemetry.
- [x] **Dual-Scene UX**: Segmented UI for Earthquake vs Fire/Gas scenarios.
- [x] **Dead Man's Switch**: Autonomous SOS if user is unconscious.
- [x] **Micro-Map Auto-Download**: Offline XYZ Tile caching (2km radius).
- [x] **V4.1 Protocol Sync**: Synchronize app with Multi-Hazard ESP32 Node (V4.3).

## Phase 9: Advanced Deployment & Protocol Hardening (ACTIVE)
- [x] **Background HQ Messaging**: System notifications for Karargah broadcasts, ACKs, and Heartbeat.
- [x] **Battery & Protocol Optimization**: Edge Node sliding window optimization, memory leak fixes, and autonomous GPS caching.
- [x] **Live UI Telemetry**: Fire/Gas scene dynamically displays BME680 sensor data.
- [ ] **End-to-End Field Stress Test**: 24h survival simulation in rubble.

**V4.6 - Production Ready**

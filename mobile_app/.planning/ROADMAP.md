# Roadmap: RescueLink

## Phase 1: Foundation & BLE Bridge
- [x] Implement BLE scanning and auto-connect logic.
- [x] Define UART-based communication protocol.
- [x] Build onboarding and MAC persistence.

## Phase 2: Core Survival Logic
- [x] Implement SosStatusService (State Machine).
- [x] Build GpsService with emergency wake locks.
- [x] Integrated storage and state management.

## Phase 3-7: Hardening & Optimization
- [x] Heartbeat Watchdog.
- [x] Battery-Aware GPS Management.
- [x] High-Volume Siren (Whistle) Integration.
- [x] Auto-Reconnection & Persistent Profile.

## Phase 8: Field Intelligence & Network
- [x] **Smart BLE Packet Priority**: High-priority SOS packets bypass routine telemetry.
- [x] **Dual-Scene UX**: Segmented UI for Earthquake vs Fire/Gas scenarios.
- [x] **Dead Man's Switch**: Autonomous SOS if user is unconscious.
- [x] **Micro-Map Auto-Download**: Offline XYZ Tile caching (2km radius).
- [x] **V4.1 Protocol Sync**: Synchronize app with Multi-Hazard ESP32 Node.

## Phase 9: Advanced Deployment & Protocol Hardening (COMPLETED)
- [x] **Direct BLE OTA Update**: Implementation of chunked firmware flashing over BLE.
- [x] **Smart SOS Timers**: Type-based dynamic locks and 15-minute cooldowns for Fire/Gas.
- [x] **AI Feedback Pipeline**: Interactive Edge Impulse labeling for anomalies.
- [x] **Legacy Cleanup**: Removal of SMS/Contact logic for cleaner mesh architecture.

**V1.7.0 - Production Ready**

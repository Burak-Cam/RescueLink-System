# Project State: RescueLink

## Current Status
- **Phase:** Phase 9 - Advanced Deployment & Protocol Hardening
- **Progress:** System is completely synchronized with ESP32 V4.6 firmware. Foreground notifications, live environmental telemetry, and advanced Tapping SOS logic are fully implemented and tested.

## Active Phase: Phase 9 (Advanced Deployment & Protocol Hardening)
- **Goal:** Finalize background notifications, harden the V4.6 LoRa binary protocol, and optimize emergency workflows.
- **Achievements Today:**
  - [x] **V4.6 Protocol Sync:** Perfected 12-byte binary LoRa payload with autonomous coordinate caching.
  - [x] **Tapping SOS Refactor:** Removed redundant metrics, added strict earthquake locks, and updated UI formatting.
  - [x] **Live Environmental Telemetry:** BME680 sensor data (Temp, Hum, Press, IAQ) dynamically displayed in the Fire/Gas scene.
  - [x] **Foreground Notifications:** Integrated `flutter_foreground_task` for silent push alerts (HQ messages, ACKs, Heartbeat loss, Fire/Gas danger).
  - [x] **Power/Logic Optimization:** Fixed memory leaks in Flutter stream subscriptions and optimized Edge Node sliding window AI (`memmove`).
  - [x] **Smart Anti-Spam & Proof of Life:** Implemented a 30-minute cooldown for Tapping SOS to prevent network congestion, and a 24-hour "Proof of Life" bypass for manual SOS messages. Added Date/Time UI to History logs.
  - [x] **Protocol Endianness & Payload Fix:** Fixed GPS corruption by enforcing `Endian.little` in Dart, and mapped missing Health/Person Count data into the 16-byte LoRa packet on ESP32.
  - [x] **Resilience & Connectivity:** Restored Offline SOS Queue logic (allowing SOS intents while disconnected to fire upon reconnection) and built a robust BLE background Auto-Reconnect loop in `BleService`.

## Next Steps
1. **End-to-End Field Stress Test:** 24h survival simulation in rubble, validating LoRa mesh hopping.
2. **Gateway Integration Check:** Ensure the RPi4 Gateway correctly parses the `RESCUELINK_V4.1_PROTOCOL.md` (V4.6 compatible) specification.
3. **Production Build:** Prepare the final release APK for field teams.

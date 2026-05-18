# Project State: RescueLink

## Current Status
- **Phase:** Phase 9 - Advanced Deployment & Protocol Hardening (COMPLETED)
- **Progress:** System is completely synchronized with ESP32 V5.0 firmware. Direct BLE OTA stability has been hardened with custom ACKs and 256-byte chunking. The architectural decision was made to drop Supabase integration to maintain a pure offline-first focus.
- **Last Updated:** 2026-05-10

## Accomplishments
### Phase 9: Protocol & Feature Hardening
- [x] **Direct BLE OTA (Hardened):** Mobile app can flash ESP32 firmware chunk-by-chunk. Fixed Android GATT timeouts by switching to `WriteWithoutResponse: true` and utilizing a custom `0x21` application-level ACK. Optimized chunk size to 256 bytes to prevent buffer overflows despite ESP32 MTU set to 512.
- [x] **Smart SOS Logic:** Implemented 15-minute dynamic unlock windows and independent 15-minute cooldowns for Fire and Gas emergencies.
- [x] **Wi-Fi Provisioning:** Automatic SSID detection and BLE-based credential sharing for AI data ingestion.
- [x] **AI Labeling Pipeline:** Interactive user feedback for Edge Impulse anomaly detection.
- [x] **Legacy Cleanup:** Removed all emergency contact and SMS logic to focus on pure LoRa Mesh reliability.
- [x] **Architecture Decision:** Supabase remote monitoring feature was evaluated and intentionally scrapped to prevent internet-dependency creep.

### IEEE Paper & Quality Assurance
- [x] **SIL Simulations:** Developed and executed Software-in-the-Loop tests proving battery efficiency (4.9x extension), anti-spam network protection (99.1% reduction in congestion), and BLE fault tolerance (100% delivery in chaotic RF). Results exported for academic plotting.
- [x] **Test Suite Recovery:** Stabilized unit/widget testing baseline by injecting required providers. Project synced to V1.7.0.

## Technical Debt / Risks
- **GitHub API Limits:** Anonymous fetching of releases for OTA may hit rate limits if checked too frequently.

## Next Steps (Pending User Input/Hardware Access)
1. **Gateway Verification:** Verify that the RPi4 Gateway correctly bridges and parses the custom binary mesh packets generated from the app's 11-byte BLE triggers. (Awaiting RPi4 Python codebase injection into workspace).
2. **Physical 24-Hour Rubble Simulation:** Develop an in-app background CSV logger to capture empirical hardware data (battery drain, real BLE reconnection latency) during a physical 24-hour test to complement the SIL data.
3. **Production Build:** Prepare final APK (V1.7.0) for SAR teams once physical tests conclude.

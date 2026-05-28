# Project State: RescueLink

## Current Status
- **Phase:** Documentation & Academic Verification (ACTIVE)
- **Progress:** System is completely synchronized with ESP32 V5.0 firmware. V1.7.0 is stable. Current focus is on transforming Software-in-the-Loop (SIL) simulation data into formal academic results for Section 4 and 5 of the project report/IEEE paper.
- **Last Updated:** 2026-05-27

## Accomplishments
### Phase 9: Protocol & Feature Hardening
- [x] **Direct BLE OTA (Hardened):** Mobile app can flash ESP32 firmware chunk-by-chunk. Fixed Android GATT timeouts by switching to `WriteWithoutResponse: true` and utilizing a custom `0x21` application-level ACK. Optimized chunk size to 256 bytes to prevent buffer overflows despite ESP32 MTU set to 512.
- [x] **Smart SOS Logic:** Implemented 15-minute dynamic unlock windows and independent cooldowns for Fire and Gas emergencies.
- [x] **Wi-Fi Provisioning:** Automatic SSID detection and BLE-based credential sharing for AI data ingestion.
- [x] **AI Labeling Pipeline:** Interactive user feedback for Edge Impulse anomaly detection.
- [x] **Legacy Cleanup:** Removed all emergency contact and SMS logic to focus on pure LoRa Mesh reliability.
- [x] **Architecture Decision:** Supabase remote monitoring feature was evaluated and intentionally scrapped to prevent internet-dependency creep.
- [x] **Gateway Location Sync:** Added a bridge between the BLE and GPS services to automatically transmit the user's location (`LOC|lat|lon`) both upon initial connection and when requested by the gateway via the `0x13` command.
- [x] **UI/UX Tweaks & Gateway Sync (V1.7.1):** 
  - Added visual SnackBar and injected localized "Rescue teams on the way" message into HQ channel upon receiving `0x06` ACK.
  - Fixed 'ghost message' rendering issue for control bytes in `ble_service`.
  - Enforced default payload values (1 person, 0 health/unknown) for Fire and Gas emergencies.
  - Resolved Gas/Fire SOS button lockouts by patching payload anti-spam filter scoping and `startSending` parameter propagation.
  - Improved Dead Man's Switch: UI danger state now persists for 1 minute post-silence, while immediately unlocking the SOS buttons for manual use.

### IEEE Paper & Quality Assurance
- [x] **SIL Simulations:** Developed and executed Software-in-the-Loop tests proving battery efficiency (4.9x extension), anti-spam network protection (99.1% reduction in congestion), and BLE fault tolerance (100% delivery in chaotic RF). Results verified on 2026-05-21.
- [x] **Test Suite Recovery:** Stabilized unit/widget testing baseline by injecting required providers. Project synced to V1.7.0.

## Technical Debt / Risks
- **GitHub API Limits:** Anonymous fetching of releases for OTA may hit rate limits if checked too frequently.

## Next Steps (Documentation & Verification)
1. **Section 4: Experimental Results:** Formalize SIL simulation data into Markdown tables and academic text.
2. **Section 5: Discussion:** Author the interpretation of RF propagation, battery trade-offs, and ethical constraints of the anti-spam algorithm.
3. **Gateway Verification:** (Awaiting RPi4 Python codebase injection) Final packet parsing check.
4. **Production Build:** Prepare final APK (V1.7.0) for SAR teams once physical tests conclude.
hor the interpretation of RF propagation, battery trade-offs, and ethical constraints of the anti-spam algorithm.
3. **Gateway Verification:** (Awaiting RPi4 Python codebase injection) Final packet parsing check.
4. **Production Build:** Prepare final APK (V1.7.0) for SAR teams once physical tests conclude.

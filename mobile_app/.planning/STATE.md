# Project State: RescueLink

## Current Status
- **Phase:** V1.7.3 OPTIMIZED SURVIVAL
- **Progress:** Core functionality and advanced hardware-software watchdog are complete. The app is now fully synchronized with the final ESP32 Edge AI hardware contract.
- **Active Task:** Ready for long-term battery stress testing and Phase 8 (Field Data Analysis).

## Recent Milestones
- **V1.7.3 (Optimized Survival - Today):**
  - **Watchdog (0x0E Heartbeat):** Implemented a 180s (3-minute) hardware health monitor. If the ESP32 stops fırlat-ing 0x0E bytes, the app triggers a critical "Donanım Erişilemez" warning.
  - **%15 Battery 'Koma' Mode:** Upgraded the survival logic. Below 15%, the accelerometer movement listener is completely killed to save every miliampere.
  - **Emergency GPS Wake:** GPS now stays in deep sleep during 'Koma' mode and *only* wakes for a 10s high-accuracy fix when a manual SOS is pressed or a 0x0A (Earthquake) signal is received.
  - **GPS Fix Persistence:** Resolved the bug where the GPS status would reset to 'Searching' during sleep cycles. The app now holds the 'Fixed' status (Yellow icon) as long as coordinates exist.
  - **UI/UX Cleanup:** Removed all debug labels ("Conn:", "Window:") for production quality. Added `loc_acquired` translation for localized feedback.
  - **V1.7.3 Build:** Compiled and installed the final optimized ARM64 release APK on the Redmi Note 9S.

- **V1.7.2 (Gold Standard Integration):**
  - **AI Hardware Handshake:** SOS button remains locked by default, unlocking only on Earthquake (0x0A) or confirmed Anomaly (0x0B).
  - **Hardware Awareness:** Integrated alerts for grid-loss (0x0C) and rhythmic tapping (0x0D).
  - **Unthrottled Survival Whistle:** Forced 100% volume output regardless of battery.

## Recent Architectural Upgrades

### 1. Watchdog Heartbeat (V1.7.3)
- **Mechanism:** ESP32 sends 0x0E every 60s. App listens in `BleService`.
- **Safety:** Prevents a "False Sense of Security" where the user thinks they are protected but the hardware is actually dead/disconnected.

### 2. 'Koma' Mode GPS (V1.7.3)
- **Logic:** Below 15%, the phone stops "listening" for movement. 
- **Impact:** Massive battery savings in high-vibration environments (e.g., aftershocks or rubble clearing) where the accelerometer would otherwise keep waking the GPS.

### 3. Dynamic GPS Polling (Battery Optimization)
- **Mechanism:** Uses `sensors_plus` to wake GPS only on movement (>1.5 m/s²).
- **Accuracy:** Only overwrites coordinates if the new ping's accuracy (meters) is better than the existing one.

## Hardware Environment
- **Client App:** Flutter (Android/iOS) - V1.7.3 Build.
- **Edge Node:** ESP32 (0x0A-0x0E Contract).
- **Gateway:** Raspberry Pi 4 LoRa.

## Future Plans (Backlog)
1. **Smart BLE Packet Priority:** Prioritize SOS packets in the `BleService` queue over telemetry.
2. **Micro-Map Package:** Automatically download a 2km radius high-detail map around the user's home coordinate during registration.
3. **Phase 8:** Analysis of field test data from simulated rubble environments.

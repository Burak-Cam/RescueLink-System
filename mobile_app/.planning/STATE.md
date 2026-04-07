# Project State: RescueLink

## Current Status
- **Phase:** V1.7.0 ADVANCED SURVIVAL STABLE
- **Progress:** Core functionality complete. Major architectural upgrades for battery life, resilience, and anti-spam have been finalized and tested on physical hardware (Redmi Note 9S & RPi4/ESP32 Gateway).
- **Active Task:** Codebase is stable. Ready for field testing in simulated rubble environments.

## Recent Architectural Upgrades (V1.0.0 -> V1.7.0)

### 1. Dynamic GPS Polling (Battery Optimization)
- **Problem:** Continuous GPS polling (`LocationAccuracy.high`) rapidly drains the battery, which is fatal in disaster scenarios.
- **Solution:** Implemented a dynamic sleep/wake architecture in `GpsService` using `sensors_plus`.
  - The GPS stream is put to **sleep by default** (saving massive battery).
  - An ultra-low-power accelerometer stream listens for physical movement. If a shake or walk is detected (threshold > 1.5 m/s²), it wakes the GPS for 30 seconds.
  - A periodic timer wakes the GPS for 10 seconds every 30 minutes for a baseline check.
  - **Accuracy Safety:** The app strictly compares the `accuracy` value of new GPS pings against the last known saved location. It will *only* overwrite the location if the new ping is statistically more precise, preventing bad signal bounces under rubble from ruining the payload.
  - **UI Reflection:** The GPS icon dynamically turns Yellow (Searching/Asleep) when saving battery and Green (Fixed) when actively tracking.

### 2. Unstoppable Siren (Audio Engine Wake-Lock)
- **Problem:** When the user turns off the screen or puts the phone in their pocket, the OS suspends the app, killing the emergency whistle loop.
- **Solution:** Integrated `wakelock_plus` into the `WhistleService`.
  - When the siren is activated, it acquires a deep CPU wake-lock, forcing the phone to stay awake indefinitely.
  - The app now perfectly loops the local `whistle.mp3` at a forced volume (100% or 80% based on battery), uninterrupted by screen locks.

### 3. Automated BLE Retry Queue
- **Problem:** In disaster chaos, BLE connections drop frequently.
- **Solution:** Restructured the `writeBinary` method in `BleService`.
  - If a write fails or the connection drops mid-send, a silent background `while` loop aggressively attempts to reconnect to the `_lastConnectedDevice` and rewrite the payload every 3 seconds.
  - The UI gracefully holds the "Telefon -> Cihaz" (Sending...) state until the queue successfully flushes.

### 4. Strict Anti-Spam Architecture
- **Problem:** Users could bypass the 15-minute absolute block by exploiting a +1 / -1 hack in the UI or spamming the button.
- **Solution:** 
  - Implemented a strict payload comparison (`hasPayloadChanged`).
  - The app now stores the exact parameters (Health Status, Person Count) of the last *successfully sent* SOS.
  - Any attempt to send a new SOS is rejected if the parameters match the database, preventing LoRa mesh congestion.

### 5. Critical Battery "Survival Mode"
- **Threshold:** Activates automatically at **<= 15% Battery**.
- **Display:** Switched to **Pure AMOLED Black UI** (#000000) to physically turn off screen pixels.
- **Throttling:** Disables all periodic GPS wake-ups and limits the emergency siren volume to 80% to reduce peak wattage drain.

## Hardware Environment
- **Client App:** Flutter (Android/iOS) tested on Redmi Note 9S.
- **Edge Node:** ESP32 with LoRa module (Breadboard).
- **Gateway:** Raspberry Pi 4 with LoRa HAT.

## Next Steps / Roadmap
1. Conduct deep-rubble field tests to verify LoRa packet delivery rates with the new compressed battery-saving GPS logic.
2. Monitor battery degradation over a 24-hour simulated survival test with periodic siren bursts.
3. Clean up legacy files and add unit tests for core services.

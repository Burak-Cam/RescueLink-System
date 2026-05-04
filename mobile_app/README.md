# RescueLink (V1.8.0 Advanced Deployment)

Emergency communication bridge between Flutter mobile apps and LoRa mesh networks via ESP32 gateways.

## Features
- **BLE Bridge:** Auto-connect to ESP32 LoRa nodes.
- **V4.6 Protocol Payload:** Compact 12-byte binary and localized string payloads (TR/EN).
- **Live Environmental Telemetry:** Real-time display of BME680 sensor data (Temp, Hum, Press, IAQ).
- **Background Push Notifications:** Silent, high-priority alerts for HQ messages, ACKs, and emergency detection.
- **3-Step Progress:** Real-time tracking from Device -> Node -> Gateway ACK.
- **Offline Micro-Maps:** Automatic local tile caching (2km radius) for offline disaster mapping.
- **Dead Man's Switch:** 60s autonomous SOS dispatch if the user is unconscious during Fire/Gas events.

## Status
- **Phase 9 Complete.** Fully synchronized with Edge Node V4.6.
- **Auto-connect:** Optimized for zero-touch discovery with robust memory management.
- **Bilingual:** Full Dynamic TR/EN support.

## Getting Started
1. Ensure Bluetooth and Location services are enabled.
2. Pair with an ESP32 node (UART Service 6E400001).
3. The app will auto-connect on subsequent launches.

---
Part of the RescueLink Disaster Management Suite.

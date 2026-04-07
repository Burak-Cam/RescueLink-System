# RescueLink (V1.0.0 Stable)

Emergency communication bridge between Flutter mobile apps and LoRa mesh networks via ESP32 gateways.

## Features
- **BLE Bridge:** Auto-connect to ESP32 LoRa nodes.
- **SOS Payload:** Compact binary and localized string payloads (TR/EN).
- **3-Step Progress:** Real-time tracking from Device -> Node -> Gateway ACK.
- **Offline Maps:** MBTiles support for offline disaster mapping.
- **Siren Alert:** High-decibel whistle bypassing media volume limits.
- **Background Service:** Foreground service to maintain mesh connectivity.

## Status
- **Phase 6 Complete.** Ready for field testing.
- **Auto-connect:** Optimized for zero-touch discovery.
- **Bilingual:** Full Dynamic TR/EN support.

## Getting Started
1. Ensure Bluetooth and Location services are enabled.
2. Pair with an ESP32 node (UART Service 6E400001).
3. The app will auto-connect on subsequent launches.

---
Part of the RescueLink Disaster Management Suite.

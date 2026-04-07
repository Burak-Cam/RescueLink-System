# RescueLink Project Report: V1.7.0 Advanced Survival Edition

**Document Purpose:** Technical hand-off for SAR Dashboard Development (e.g., AFAD coordination) and team alignment.
**Project Status:** V1.7.0 STABLE (Release Build verified on physical hardware).

---

## 1. System Architecture Overview
`RescueLink` bridges the gap between trapped victims and Search & Rescue (SAR) teams using a high-resilience communication tunnel:
**Victim Phone (App) <--(BLE)--> Edge Node (ESP32) <--(LoRa Mesh)--> SAR Gateway (RPi4) <--(Dashboard Integration)--> Rescue HQ**

## 2. Technical Specifications for Dashboard Integration
The SAR Dashboard developer should note the following payload and behavior specifications:

### 2.1. SOS Payload Format (Custom Binary)
To minimize LoRa airtime and congestion, the app sends a compact **11-byte binary packet** (NOT JSON/String):
- **Byte 0:** Prefix `0x01` (SOS Identifier)
- **Bytes 1-4:** Latitude (32-bit Float, Big Endian)
- **Bytes 5-8:** Longitude (32-bit Float, Big Endian)
- **Byte 9:** Health Status (0: Healthy, 1: Lightly Injured, 2: Severely Injured)
- **Byte 10:** Person Count (Integer, 1-255)

### 2.2. Ack-Back Verification
The app expects an **Acknowledgment (ACK)** byte back from the Gateway to confirm the victim that help is on the way.
- **ACK Byte:** `0x06` (ASCII: ACK)
- When the RPi4 Gateway receives a valid SOS, it must broadcast this ACK back through the mesh to trigger the **"HQ confirmed"** green state on the victim's UI.

---

## 3. Major Survival Innovations (V1.0.0 to V1.7.0)

### 3.1. Dynamic GPS "Sleep-Wake" (Battery Priority)
- **Logic:** GPS hardware is kept **OFF** by default to prevent battery death. 
- **Trigger:** An ultra-low-power accelerometer (`sensors_plus`) monitors for physical movement. Only when the phone is shaken or moved (threshold > 1.5 m/s²) does the GPS wake up for 30 seconds to fetch coordinates.
- **Accuracy Filter:** The app compares the `accuracy` (radius in meters) of every new ping. It will **REJECT** any new location that is less precise than the currently saved one. This prevents bad signal reflections (typical in rubble) from corrupting the dashboard coordinates.

### 3.2. Critical Battery "Survival Mode"
- **Threshold:** Activates automatically at **<= 15% Battery**.
- **Display:** Switched to **Pure AMOLED Black UI** (#000000) to physically turn off screen pixels on compatible devices.
- **Throttling:** Disables all periodic GPS wake-ups and limits the emergency siren volume to 80% to reduce peak wattage drain from the speaker.

### 3.3. Unstoppable Emergency Siren
- Uses `wakelock_plus` to acquire a deep CPU wake-lock.
- The siren (`whistle.mp3`) loops infinitely at maximum volume and **cannot be killed by the OS background optimizer**, even if the phone is locked and in a pocket.

### 3.4. BLE Auto-Recovery Queue
- Implements a background retry loop. If a victim presses SOS and the BLE connection to the ESP32 drops, the app silently retries the connection and write every 3 seconds. The UI holds a "Sending" state instead of failing, ensuring a "One-Press" reliable experience for the user.

### 3.5. Anti-Spam Strict Payload Validation
- The app stores the exact parameters of the last *successful* transmission. It will block any attempt to send a duplicate SOS (same health/count/location) to prevent clogging the LoRa mesh with redundant data.

---

## 4. Hardware Environment Tested
- **Redmi Note 9S:** Verified Release Build (57MB), fast AOT performance.
- **ESP32 Edge Node:** Breadboarded with LoRa transceiver.
- **RPi4 Gateway:** Central hub for Mesh-to-Dashboard bridging.

**End of Report.**

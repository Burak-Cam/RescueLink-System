# Requirements: RescueLink

## Functional Requirements (FR)

### 1. BLE Bridge (ESP32 Gateway)
- **FR-1.1:** Secure pairing and automatic reconnection with the designated ESP32 node.
- **FR-1.2:** Robust data transmission between Flutter and ESP32 using dedicated BLE characteristics.
- **FR-1.3:** Handshake protocol to verify the node is "Mesh Ready."
- **FR-1.4:** **Foreground Service:** The app MUST use a Foreground Service to keep the BLE connection alive when the screen is locked or in the background to listen for HQ messages.

### 2. SOS Payload & Data
- **FR-2.1:** Generation of SOS packets including GPS coordinates (WGS84), health status, and person count.
- **FR-2.2:** **Binary Encoding:** The SOS payload must be strictly encoded as a compact Byte/Hex array (NOT plain strings) to minimize LoRa airtime.
- **FR-2.3:** Real-time confirmation of packet arrival at the nearest node.

### 3. Mesh & HQ Messaging
- **FR-3.1:** Bidirectional messaging queue for outgoing SOS and incoming HQ updates.
- **FR-3.2:** Support for multi-hop status tracking (e.g., "Sent to Node 1," "Delivered to Gateway").
- **FR-3.3:** Notification system for high-priority HQ announcements.

### 4. Offline Mapping & Location
- **FR-4.1:** Integration of `flutter_map` with local MBTiles for internet-independent mapping.
- **FR-4.2:** **Smart Map Prompt:** Detect user's current city (while online) and prompt them to download the specific city MBTiles package.
- **FR-4.3:** Manual location picker interface for precise pinpointing.

### 5. Profile & Emergency Services
- **FR-5.1:** Dedicated Profile Screen for managing personal data and emergency contacts.
- **FR-5.2:** Manual location update from the Profile Screen.
- **FR-5.3:** **Burst Whistle:** Virtual whistle plays a fixed 5-second burst per press to conserve battery.
- **FR-5.4:** Offline-to-Online SMS Queue to send SOS alerts to emergency contacts once connection is restored.
- **FR-5.5:** Dynamic Bilingual Support (TR/EN) managed via Provider.

## Non-Functional Requirements (NFR)

### 1. UI/UX
- **NFR-1.1:** Urgent & High-Contrast theme using Material 3 for maximum outdoor readability.
- **NFR-1.2:** Minimalist interactions to reduce cognitive load during high-pressure situations.

### 2. Performance & Reliability
- **NFR-2.1:** Low-latency BLE/LoRa handovers (target < 500ms for internal bridge).
- **NFR-2.2:** Offline-first architecture using SQLite/SharedPreferences for message persistence.

### 3. Safety & Security
- **NFR-3.1:** Validation of all incoming and outgoing packets to prevent mesh flooding.
- **NFR-3.2:** Minimal local data retention for privacy.

# Architecture

**Analysis Date:** 2025-02-14

## Pattern Overview

**Overall:** Model-View (Flutter State Management with `StatefulWidget`)

**Key Characteristics:**
- **Stateful Management:** Primarily uses `StatefulWidget` for local screen state and UI updates.
- **Persistence Layer:** Uses `SharedPreferences` for storing user registration, personal info, and last connected BLE device MAC address.
- **Service Integration:** Integrates with BLE (Bluetooth Low Energy) using `flutter_blue_plus` and GPS using `geolocator`.

## Layers

**Presentation (UI):**
- Purpose: Provides user interface for onboarding, device connection, and SOS messaging.
- Location: `lib/screens/`
- Contains: `onboarding_screen.dart`, `auto_connect_screen.dart`, `home_screen.dart`
- Depends on: `lib/globals.dart`, `flutter_blue_plus`, `shared_preferences`, `geolocator`
- Used by: Flutter framework (`runApp`)

**Global / Shared Logic:**
- Purpose: Shared constants, localization, and global state.
- Location: `lib/globals.dart`
- Contains: Color constants, localization map (`lang`), translation function (`t`), and global language state (`isEnglish`).
- Depends on: `package:flutter/material.dart`
- Used by: All screens in `lib/screens/` and `lib/main.dart`

**External Integrations:**
- Purpose: Handle communication with BLE devices and system services.
- Location: Integrated within screen logic (e.g., `lib/screens/auto_connect_screen.dart`, `lib/screens/onboarding_screen.dart`).
- Contains: Bluetooth scanning, connection, service discovery, and GPS location fetching.
- Depends on: `flutter_blue_plus`, `geolocator`
- Used by: UI screens to perform actions.

## Data Flow

**User Onboarding & Registration:**
1. `main.dart` checks `isRegistered` in `SharedPreferences`.
2. If `false`, navigates to `OnboardingScreen`.
3. `OnboardingScreen` collects name, surname, and location (GPS or manual).
4. Data is saved to `SharedPreferences` and `isRegistered` is set to `true`.

**Device Connection:**
1. Navigates to `AutoConnectScreen`.
2. Checks for `saved_mac` in `SharedPreferences`.
3. If `saved_mac` exists, attempts background scan and auto-connect.
4. If no `saved_mac` or auto-connect fails, displays manual scan results.
5. Upon connection, discovers services and characteristics (RX/TX).
6. Saves `saved_mac` to `SharedPreferences` and navigates to `HomeScreen`.

**SOS Alert Flow:**
1. `HomeScreen` displays user info and SOS options (health status, person count).
2. User taps "SEND SOS ALERT".
3. App encodes a payload: `TEST_SOS|Name|Location|Health|Count`.
4. App writes payload to the BLE device's RX characteristic.
5. App displays a snackbar confirming success or failure.

**HQ Message Flow:**
1. `HomeScreen` listens to the TX characteristic of the connected BLE device.
2. When a message is received, it decodes the UTF-8 payload.
3. Decoded message is added to the `_incomingMessages` list and displayed in the UI.

## Key Abstractions

**Localization:**
- Purpose: Centralized string translation.
- Examples: `lib/globals.dart`
- Pattern: Simple key-value mapping with a global language toggle.

**BLE Communication:**
- Purpose: Handling Bluetooth Low Energy life cycle (scan, connect, discover, communicate).
- Examples: `lib/screens/auto_connect_screen.dart`, `lib/screens/home_screen.dart`
- Pattern: Reactive streams (`lastValueStream`, `scanResults`) provided by `flutter_blue_plus`.

## Entry Points

**Main Entry Point:**
- Location: `lib/main.dart`
- Triggers: Application launch.
- Responsibilities: Initializes `WidgetsFlutterBinding`, checks persistent registration state, and launches `RescueLinkApp`.

## Error Handling

**Strategy:** Localized error handling with user feedback via SnackBar.

**Patterns:**
- **Try-Catch Blocks:** Used around BLE connection and write operations (`lib/screens/auto_connect_screen.dart`, `lib/screens/home_screen.dart`).
- **Permission Checks:** Used before accessing GPS (`lib/screens/onboarding_screen.dart`).
- **Connection Status Feedback:** UI updates based on connection success/failure.

## Cross-Cutting Concerns

**Logging:** Uses `debugPrint` for development logging (detected in `lib/ble_scan_screen.dart`).
**Validation:** Basic field validation in `OnboardingScreen` (e.g., checking if name/surname are empty).
**Authentication:** Implicitly handled by registration state in `SharedPreferences`.

---

*Architecture analysis: 2025-02-14*

# Codebase Structure

**Analysis Date:** 2025-02-14

## Directory Layout

```
RLAPP/
├── .planning/codebase/   # Architecture and mapping documentation
├── android/              # Android-specific platform code
├── build/                # Compiled build artifacts
├── ios/                  # iOS-specific platform code
├── lib/                  # Dart source code (core application logic)
│   ├── screens/          # Main application screens (Onboarding, Home, AutoConnect)
│   ├── ble_scan_screen.dart # Legacy or alternative BLE scan screen
│   ├── globals.dart      # Global constants, colors, and localization
│   ├── main.dart         # App entry point and initialization logic
│   └── sos_screen.dart   # Legacy or alternative SOS screen
├── linux/                # Linux-specific platform code
├── macos/                # macOS-specific platform code
├── test/                 # Unit and widget tests
├── web/                  # Web-specific platform code
├── windows/              # Windows-specific platform code
├── pubspec.yaml          # Project dependencies and configuration
└── README.md             # Project overview
```

## Directory Purposes

**lib/:**
- Purpose: Root of the Dart source code.
- Contains: Application entry point and global state/utility files.
- Key files: `main.dart`, `globals.dart`.

**lib/screens/:**
- Purpose: UI components for the current version of the application.
- Contains: StatefulWidget-based screen implementations.
- Key files: `onboarding_screen.dart`, `auto_connect_screen.dart`, `home_screen.dart`.

**android/, ios/, linux/, macos/, windows/, web/:**
- Purpose: Platform-specific implementation files for Flutter.
- Contains: Native project files (Gradle, Xcode, etc.).
- Key files: `android/app/build.gradle.kts`, `ios/Runner/Info.plist`.

**test/:**
- Purpose: Test suites for the application.
- Contains: Dart test files.
- Key files: `widget_test.dart`.

## Key File Locations

**Entry Points:**
- `lib/main.dart`: Initial point of execution for the Flutter application.

**Configuration:**
- `pubspec.yaml`: Defines dependencies (e.g., `flutter_blue_plus`, `geolocator`, `shared_preferences`) and app metadata.
- `analysis_options.yaml`: Configures the Dart linter.

**Core Logic:**
- `lib/screens/auto_connect_screen.dart`: Core logic for Bluetooth device scanning and connecting.
- `lib/screens/home_screen.dart`: Primary user interface after connection, including SOS and HQ messaging logic.
- `lib/globals.dart`: Centralized theme (colors) and translation mapping.

**Testing:**
- `test/widget_test.dart`: Basic Flutter widget test (auto-generated).

## Naming Conventions

**Files:**
- Lowercase with underscores (snake_case): `home_screen.dart`, `onboarding_screen.dart`.

**Directories:**
- Lowercase with underscores (snake_case): `screens/`, `lib/`.

## Where to Add New Code

**New Feature:**
- If it's a new screen, place it in `lib/screens/`.
- If it's a new global utility, add it to a new file in `lib/utils/` or add to `lib/globals.dart` (if simple).

**New Component/Module:**
- Reusable UI widgets should be placed in a new directory like `lib/widgets/`.

**Utilities:**
- Complex logic for BLE or data parsing should be separated into a `lib/services/` directory.

## Special Directories

**.planning/codebase/:**
- Purpose: GSD codebase mapping and planning documentation.
- Generated: Yes
- Committed: Yes

---

*Structure analysis: 2025-02-14*

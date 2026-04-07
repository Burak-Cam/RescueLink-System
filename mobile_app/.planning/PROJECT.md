# Project: RescueLink (Emergency Mesh Communication Bridge)

## Overview
`RescueLink` is a Flutter-based emergency communication tool designed for disaster scenarios where cellular networks are unavailable. It serves as a mobile interface that bridges users to a LoRa mesh network via an ESP32 gateway node.

## Goal
To provide a reliable, offline emergency communication channel that allows victims to send SOS data (location, health, status) and receive updates from a central Search & Rescue (SAR) Headquarters through a multi-hop LoRa mesh network.

## Target Audience
- **Disaster Victims:** Individuals in areas with no cellular coverage.
- **Rescue Teams:** Field personnel coordinating search and rescue operations.
- **SAR Headquarters:** Centralized command centers monitoring the gateway dashboard.

## Technical Strategy
- **Connectivity:** Flutter <--(BLE)--> ESP32 <--(LoRa Mesh)--> Rescue Gateway.
- **Protocol:** Custom compact binary/JSON payloads for BLE, compressed for LoRa airtime efficiency.
- **Mapping:** `flutter_map` with MBTiles for offline base maps and dynamic caching for user-selected regions.
- **Messaging:** Bidirectional queue for reliable message delivery between the app and the LoRa mesh.
- **UI/UX:** Urgent & High-Contrast (Material 3) for readability in high-stress, outdoor environments.

## Key Stakeholders
- Development Team
- SAR Organizations
- Local Emergency Management Agencies

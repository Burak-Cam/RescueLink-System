# RescueLink V4.1 Binary Protocol Specification

**Version:** 4.1 (Field Intelligence & Multi-Hazard Edition)  
**Scope:** Mobile App <-> Edge Node <-> Gateway (RPi4)  
**Packet Size:** 12 Bytes (Fixed)

## 1. SOS Packet Structure (Primary Uplink)
Sent when an emergency is triggered. This 12-byte payload is optimized for LoRa mesh efficiency.

| Byte Index | Field | Type | Description |
| :--- | :--- | :--- | :--- |
| 0 | **Packet Header** | `uint8` | **0x01**: Identifies this as an SOS packet. |
| 1 | **Disaster Type** | `uint8` | **0x00**: Manual SOS (General)<br>**0x01**: Earthquake (Sismic)<br>**0x02**: Fire (Thermal)<br>**0x03**: Gas (Chemical)<br>**0x04**: Rhythmic Tapping (Acoustic) |
| 2-5 | **Latitude** | `float32` | GPS Latitude (Little-Endian). |
| 6-9 | **Longitude** | `float32` | GPS Longitude (Little-Endian). |
| 10 | **Health Status** | `uint8` | **0x00**: Healthy / Stable<br>**0x01**: Lightly Injured<br>**0x02**: Severely Injured |
| 11 | **Person Count** | `uint8` | Number of people at the coordinates. |

---

## 2. System Event Codes (Hardware -> Mobile)
Single-byte notifications sent by the Edge Node via BLE notifications.

| Hex Code | Event Name | Gateway Action / HQ Alert |
| :--- | :--- | :--- |
| **0x0A** | EARTHQUAKE | Seismic threshold exceeded. |
| **0x0C** | FIRE | Critical temperature or flame detected. |
| **0x0D** | TAPPING | Rhythmic tapping patterns recognized. |
| **0x0E** | BAD_AIR | Dangerous gas levels or IAQ drop. |
| **0x0F** | HUMIDITY | Flood or critical moisture detected. |
| **0x11** | POWER_LOST | Node power cut; running on battery. |
| **0x12** | HEARTBEAT | Node status check (Alive). |

---

## 3. Control Commands (Mobile -> Hardware)
Single-byte downlink commands sent to the Edge Node.

| Hex Code | Command | Description |
| :--- | :--- | :--- |
| **0x55** | COMA_MODE_ON | Enable Disaster Mode (Low power, Tapping only). |
| **0x56** | COMA_MODE_OFF | Resume normal operation (Full sensor scan). |
| **0x99** | SILENCE | Stop local sirens/whistles (User safe). |
| **0x06** | ACK | Message delivery confirmation. |

---

## 4. Environmental Telemetry (String Format)
Real-time environmental monitoring data.

- **Format:** `TEL|temp|hum|press|iaq`
- **Example:** `TEL|28.4|35|1012|42`
- **Notes:** Gateway should parse this for the "Environmental Dashboard" view.

---
**Confidential:** RescueLink-System Integration Docs.  
*Date: 2026-05-04*

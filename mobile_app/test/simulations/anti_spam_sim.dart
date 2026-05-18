import 'dart:math';

/// IEEE Paper Data Generator: Anti-Spam & LoRa Network Congestion Simulation
/// 
/// This script mathematically simulates a panic scenario where a victim repeatedly
/// presses the SOS button. 
/// It demonstrates the necessity and effectiveness of the `SosStatusService` 
/// 15-minute cooldown mechanism (smart timers) in preventing LoRa network collapse.
///
/// Assumptions:
/// - A panicked user presses the SOS button randomly but frequently.
/// - LoRa Airtime per SOS Packet (11 bytes at SF10, BW 125kHz) is approx ~300ms.
/// - Duty cycle limits (e.g., 1%) restrict how much time a node can transmit per hour.
/// - RescueLink Architecture only allows a status change every 15 minutes unless it's a critical new event.

void main() {
  print('==========================================================');
  print('IEEE Simulation 2: LoRa Anti-Spam Network Congestion Analysis');
  print('==========================================================');

  final int simulationTimeMinutes = 60; // 1 hour scenario
  final int totalPanicPresses = 450; // User spams the button 450 times in an hour
  
  // Constants
  final int cooldownMinutes = 15;
  final double packetAirtimeSeconds = 0.3; // 300ms per packet
  
  // Generate random press timestamps (in minutes)
  Random rnd = Random(42); // Fixed seed for reproducibility
  List<double> pressTimestamps = [];
  for (int i = 0; i < totalPanicPresses; i++) {
    pressTimestamps.add(rnd.nextDouble() * simulationTimeMinutes);
  }
  pressTimestamps.sort(); // Sort chronologically
  
  // ---------------------------------------------------------
  // Model A: Unrestricted Application (Naive approach)
  // ---------------------------------------------------------
  int packetsTransmittedA = 0;
  
  for (double time in pressTimestamps) {
    // Every press sends a packet
    packetsTransmittedA++;
  }
  
  double totalAirtimeA = packetsTransmittedA * packetAirtimeSeconds;

  // ---------------------------------------------------------
  // Model B: RescueLink Smart Cooldown Architecture
  // ---------------------------------------------------------
  int packetsTransmittedB = 0;
  double lastTransmissionTime = -cooldownMinutes.toDouble(); // Allow first transmission immediately
  
  for (double time in pressTimestamps) {
    if (time >= lastTransmissionTime + cooldownMinutes) {
      // Cooldown has passed, allow transmission
      packetsTransmittedB++;
      lastTransmissionTime = time;
    } else {
      // Blocked by anti-spam mechanism
    }
  }
  
  double totalAirtimeB = packetsTransmittedB * packetAirtimeSeconds;

  // ---------------------------------------------------------
  // Output Results (CSV Format for Excel/MATLAB)
  // ---------------------------------------------------------
  print('\n[RESULTS]');
  print('Scenario: Panicked user presses SOS $totalPanicPresses times over $simulationTimeMinutes minutes.');
  
  print('\n[Model A] Naive Implementation:');
  print('- Packets Sent to LoRa Edge Node: $packetsTransmittedA');
  print('- Total LoRa Airtime Consumed: ${totalAirtimeA.toStringAsFixed(1)} seconds');
  print('- Duty Cycle (1 Hour): ${((totalAirtimeA / 3600) * 100).toStringAsFixed(2)}%');
  
  print('\n[Model B] RescueLink Smart Cooldown:');
  print('- Packets Sent to LoRa Edge Node: $packetsTransmittedB');
  print('- Total LoRa Airtime Consumed: ${totalAirtimeB.toStringAsFixed(1)} seconds');
  print('- Duty Cycle (1 Hour): ${((totalAirtimeB / 3600) * 100).toStringAsFixed(4)}%');
  
  double reduction = ((packetsTransmittedA - packetsTransmittedB) / packetsTransmittedA) * 100;
  print('\n[CONCLUSION]');
  print('The RescueLink Anti-Spam algorithm reduces LoRa network congestion by ${reduction.toStringAsFixed(1)}%, ensuring the gateway is not overwhelmed by duplicate SOS signals from a single user.');

  print('\n[CSV DATA FOR GRAPHING: TimeMinute,CumulativePacketsNaive,CumulativePacketsRescueLink]');
  print('Minute,Naive_Approach,RescueLink_Architecture');
  
  int cumulativeA = 0;
  int cumulativeB = 0;
  double lastB = -cooldownMinutes.toDouble();
  
  int currentEventIndex = 0;
  for (int minute = 0; minute <= simulationTimeMinutes; minute++) {
    // Count events up to this minute
    while(currentEventIndex < pressTimestamps.length && pressTimestamps[currentEventIndex] <= minute.toDouble()) {
        cumulativeA++;
        if (pressTimestamps[currentEventIndex] >= lastB + cooldownMinutes) {
            cumulativeB++;
            lastB = pressTimestamps[currentEventIndex];
        }
        currentEventIndex++;
    }
    print('$minute,$cumulativeA,$cumulativeB');
  }
}

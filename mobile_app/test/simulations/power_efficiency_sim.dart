import 'dart:math';

/// IEEE Paper Data Generator: Power Efficiency & Time-To-First-Fix (TTFF) Simulation
/// 
/// This script mathematically simulates a 24-hour "Rubble Survival" scenario.
/// It compares two architectural approaches for GPS tracking in emergency apps:
/// 1. Traditional Continuous Polling (GPS active 100% of the time).
/// 2. RescueLink's Accelerometer-Triggered Architecture (GPS sleeps, wakes only on movement > 1.5 m/s²).
/// 
/// Assumptions for the mathematical model (based on typical modern smartphone specs):
/// - Battery Capacity: 4000 mAh
/// - Idle System Drain: 20 mA / hour
/// - Screen On Drain (AMOLED Black UI): 50 mA / hour (Assumed screen is mostly off or black)
/// - Continuous GPS Hardware Drain: ~150 mA / hour
/// - Accelerometer Sensor (Low Power) Drain: ~2 mA / hour
/// - App Baseline Drain (WakeLocks/BLE Scanning): 15 mA / hour

void main() {
  print('==========================================================');
  print('IEEE Simulation 1: 24-Hour Power Efficiency Analysis');
  print('==========================================================');
  
  final int totalDurationHours = 24;
  final double batteryCapacity = 4000.0; // mAh
  
  // Power Draw Constants (mA)
  final double baseIdleDraw = 20.0;
  final double appBaselineDraw = 15.0; // BLE + Services
  final double gpsContinuousDraw = 150.0;
  final double accelerometerDraw = 2.0;
  
  // Scenario Events
  // We simulate "aftershocks" or user movement events over 24 hours.
  // Let's assume there are 12 significant movement events where the user shakes the phone or an aftershock occurs.
  final int movementEventsPer24h = 12;
  // When triggered, GPS stays awake for exactly 30 seconds (0.0083 hours) to acquire a fix.
  final double gpsWakeDurationHours = 30.0 / 3600.0; 
  
  // ---------------------------------------------------------
  // Model A: Traditional Continuous GPS Polling
  // ---------------------------------------------------------
  double batteryModelA = batteryCapacity;
  double hoursSurvivedA = 0;
  
  for (int hour = 1; hour <= totalDurationHours; hour++) {
    double hourlyDrain = baseIdleDraw + appBaselineDraw + gpsContinuousDraw;
    batteryModelA -= hourlyDrain;
    
    if (batteryModelA > 0) {
      hoursSurvivedA = hour.toDouble();
    } else {
      // Calculate exact survival fraction
      double fraction = (batteryModelA + hourlyDrain) / hourlyDrain;
      hoursSurvivedA = (hour - 1) + fraction;
      batteryModelA = 0;
      break; 
    }
  }

  // ---------------------------------------------------------
  // Model B: RescueLink Accelerometer-Triggered GPS
  // ---------------------------------------------------------
  double batteryModelB = batteryCapacity;
  double hoursSurvivedB = 0;
  double totalGpsActiveTimeB = 0; // Hours
  
  for (int hour = 1; hour <= totalDurationHours; hour++) {
    // Determine how many movement events happen this hour. 
    // Simplified: Distribute events evenly or randomly. Let's do a simple average per hour.
    double eventsThisHour = movementEventsPer24h / totalDurationHours;
    double gpsActiveHoursThisHour = eventsThisHour * gpsWakeDurationHours;
    totalGpsActiveTimeB += gpsActiveHoursThisHour;
    
    double hourlyDrain = baseIdleDraw + 
                         appBaselineDraw + 
                         accelerometerDraw + 
                         (gpsContinuousDraw * gpsActiveHoursThisHour); // GPS only drains when active
                         
    batteryModelB -= hourlyDrain;
    
    if (batteryModelB > 0) {
      hoursSurvivedB = hour.toDouble();
    } else {
      double fraction = (batteryModelB + hourlyDrain) / hourlyDrain;
      hoursSurvivedB = (hour - 1) + fraction;
      batteryModelB = 0;
      break;
    }
  }

  // ---------------------------------------------------------
  // Output Results (CSV Format for Excel/MATLAB)
  // ---------------------------------------------------------
  print('\n[RESULTS]');
  print('Total Simulated Time: $totalDurationHours hours');
  print('Simulated Movement Events: $movementEventsPer24h');
  print('\n[Model A] Continuous Polling:');
  print('- Total Uptime: ${hoursSurvivedA.toStringAsFixed(2)} hours');
  print('- Remaining Battery: ${batteryModelA.toStringAsFixed(1)} mAh');
  print('- Energy Consumed: ${(batteryCapacity - batteryModelA).toStringAsFixed(1)} mAh');

  print('\n[Model B] RescueLink Accelerometer-Triggered:');
  print('- Total Uptime: ${hoursSurvivedB > totalDurationHours ? '>24' : hoursSurvivedB.toStringAsFixed(2)} hours');
  print('- Remaining Battery at 24h: ${batteryModelB.toStringAsFixed(1)} mAh (${((batteryModelB/batteryCapacity)*100).toStringAsFixed(1)}%)');
  print('- Energy Consumed: ${(batteryCapacity - batteryModelB).toStringAsFixed(1)} mAh');
  print('- Total GPS Active Time: ${(totalGpsActiveTimeB * 3600).toStringAsFixed(1)} seconds');

  print('\n[CONCLUSION]');
  double extensionFactor = (batteryCapacity / (batteryCapacity - batteryModelB)) / (batteryCapacity / (batteryCapacity - batteryModelA));
  if (batteryModelB > 0 && batteryModelA == 0) {
      double hourlyDrainB = (batteryCapacity - batteryModelB) / totalDurationHours;
      double projectedUptimeB = batteryCapacity / hourlyDrainB;
      extensionFactor = projectedUptimeB / hoursSurvivedA;
      print('The RescueLink architecture extends the device survival time by approximately ${extensionFactor.toStringAsFixed(1)}x compared to traditional continuous polling.');
  }

  print('\n[CSV DATA FOR GRAPHING: Hour,BatteryModelA(%),BatteryModelB(%)]');
  print('Hour,Continuous_Polling,RescueLink_Architecture');
  
  double traceBatteryA = batteryCapacity;
  double traceBatteryB = batteryCapacity;
  for (int hour = 0; hour <= totalDurationHours; hour++) {
    if(hour == 0) {
        print('0,100.0,100.0');
        continue;
    }
    
    double hourlyDrainA = baseIdleDraw + appBaselineDraw + gpsContinuousDraw;
    traceBatteryA = max(0, traceBatteryA - hourlyDrainA);
    
    double eventsThisHour = movementEventsPer24h / totalDurationHours;
    double gpsActiveHoursThisHour = eventsThisHour * gpsWakeDurationHours;
    double hourlyDrainB = baseIdleDraw + appBaselineDraw + accelerometerDraw + (gpsContinuousDraw * gpsActiveHoursThisHour);
    traceBatteryB = max(0, traceBatteryB - hourlyDrainB);
    
    print('$hour,${(traceBatteryA/batteryCapacity*100).toStringAsFixed(1)},${(traceBatteryB/batteryCapacity*100).toStringAsFixed(1)}');
  }
}

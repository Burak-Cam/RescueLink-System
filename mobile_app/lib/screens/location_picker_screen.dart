import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../services/map_service.dart';
import '../services/gps_service.dart';
import '../services/locale_service.dart';

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  _LocationPickerScreenState createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(39.9334, 32.8597); // Default to Ankara

  @override
  void initState() {
    super.initState();
    final gps = context.read<GpsService>();
    if (gps.currentPosition != null) {
      _center = LatLng(gps.currentPosition!.latitude, gps.currentPosition!.longitude);
    }
  }

  void _confirmLocation() {
    final gps = context.read<GpsService>();
    gps.setManualLocation(_center.latitude, _center.longitude);
    Navigator.pop(context, _center);
  }

  @override
  Widget build(BuildContext context) {
    final mapService = context.watch<MapService>();
    final locale = context.watch<LocaleService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(locale.t('update_location').toUpperCase()),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 28),
            onPressed: _confirmLocation,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (!mapService.isInitialized)
            const Center(child: CircularProgressIndicator())
          else ...[
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 13,
                backgroundColor: Colors.black,
                onPositionChanged: (camera, hasGesture) {
                  if (hasGesture) {
                    setState(() {
                      _center = camera.center;
                    });
                  }
                },
              ),
              children: [
                if (mapService.tileProvider != null)
                  TileLayer(
                    tileProvider: mapService.tileProvider,
                  )
                else
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.rescuelink.app',
                  ),
              ],
            ),
          ],
          
          // Crosshair Overlay (Polished)
          IgnorePointer(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 2,
                    height: 40,
                    color: const Color(0xFFD32F2F),
                  ),
                  Container(
                    width: 40,
                    height: 2,
                    color: const Color(0xFFD32F2F),
                  ),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Coordinate Badge (Refined)
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFFFC107), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.gps_fixed, color: Color(0xFFFFC107), size: 16),
                    const SizedBox(width: 10),
                    Text(
                      "${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontFamily: 'monospace', fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Action Buttons
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FloatingActionButton(
                      heroTag: 'gps_fab',
                      backgroundColor: Colors.black,
                      foregroundColor: const Color(0xFFFFC107),
                      mini: true,
                      onPressed: () {
                        final gps = context.read<GpsService>();
                        if (gps.currentPosition != null) {
                          _mapController.move(LatLng(gps.currentPosition!.latitude, gps.currentPosition!.longitude), 15);
                        }
                      },
                      child: const Icon(Icons.my_location),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _confirmLocation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    minimumSize: const Size(double.infinity, 0),
                    elevation: 10,
                    shadowColor: const Color(0xFFD32F2F).withOpacity(0.5),
                  ),
                  child: Text(
                    locale.t('save').toUpperCase(),
                    style: const TextStyle(letterSpacing: 2, fontSize: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

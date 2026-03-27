import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Default location (Charlotte, NC) if GPS is unavailable
const defaultLocation = LatLng(35.2271, -80.8431);

/// Provider for the user's current location
final userLocationProvider = FutureProvider<LatLng>((ref) async {
  try {
    final position = await getUserLocation();
    return LatLng(position.latitude, position.longitude);
  } catch (_) {
    return defaultLocation;
  }
});

/// Get the user's current GPS position.
/// Handles permission requests automatically.
/// Times out after 10 seconds total to avoid hanging on permission prompts
/// (especially on Chrome/web where the browser prompt can block indefinitely).
Future<Position> getUserLocation() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Location services are disabled');
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission()
        .timeout(const Duration(seconds: 5));
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception('Location permission permanently denied');
  }

  return await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: Duration(seconds: 5),
    ),
  );
}

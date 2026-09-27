import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Foreground-only location; never sent to the backend or speech provider.
class UserLocationService {
  LatLng? lastPosition;

  Future<LatLng?> locate({bool requestPermission = false}) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestPermission) {
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return lastPosition;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      lastPosition = LatLng(position.latitude, position.longitude);
    } catch (_) {
      // Denied, unavailable, unsupported, or timed out: retain the fallback.
    }
    return lastPosition;
  }
}

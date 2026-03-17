import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';

/// Full-width map widget using OpenStreetMap tiles.
///
/// Shows current location marker and optional polyline trail.
/// Designed to fill 60%+ of screen height.
class MapWidget extends StatefulWidget {
  /// Current user location (lat, lon).
  final double? latitude;
  final double? longitude;

  /// Trail of GPS points recorded during trip.
  final List<LatLng> trail;

  /// Terrain-coded segment markers.
  final List<MapSegmentMarker> segmentMarkers;

  /// Map controller for programmatic movement.
  final MapController? controller;

  /// Initial zoom level.
  final double zoom;

  /// Whether to follow current location.
  final bool followLocation;

  const MapWidget({
    super.key,
    this.latitude,
    this.longitude,
    this.trail = const [],
    this.segmentMarkers = const [],
    this.controller,
    this.zoom = 15.0,
    this.followLocation = true,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> {
  bool _tileFailure = false;

  void _onTileError(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    if (_tileFailure) return;
    setState(() => _tileFailure = true);
  }

  @override
  Widget build(BuildContext context) {
    final center = (widget.latitude != null && widget.longitude != null)
        ? LatLng(widget.latitude!, widget.longitude!)
        : const LatLng(11.2588, 75.7804); // Default: Kozhikode

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: ColoredBox(
            color: const Color(0xFFE5E7EB),
            child: FlutterMap(
              mapController: widget.controller,
              options: MapOptions(
                initialCenter: center,
                initialZoom: widget.zoom,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                // ─── Tile Layer ────────────────────────────────────────────
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.ksrtc_benchmarking',
                  maxZoom: 19,
                  errorTileCallback: (tile, error, stackTrace) {
                    _onTileError(error, stackTrace);
                  },
                ),

                // Fallback provider (parallel layer; may load if primary fails)
                TileLayer(
                  urlTemplate: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.ksrtc_benchmarking',
                  maxZoom: 19,
                  errorTileCallback: (tile, error, stackTrace) {
                    _onTileError(error, stackTrace);
                  },
                ),

                // ─── Route Trail ───────────────────────────────────────────
                if (widget.trail.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: widget.trail,
                        strokeWidth: 4.0,
                        color: AppColors.primary.withOpacity(0.8),
                      ),
                    ],
                  ),

                // ─── Segment Markers ───────────────────────────────────────
                if (widget.segmentMarkers.isNotEmpty)
                  MarkerLayer(
                    markers: widget.segmentMarkers
                        .map((sm) => Marker(
                              point: sm.position,
                              width: 14,
                              height: 14,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.terrainColor(sm.terrain),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ))
                        .toList(),
                  ),

                // ─── Current Location Marker ───────────────────────────────
                if (widget.latitude != null && widget.longitude != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: center,
                        width: 28,
                        height: 28,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (_tileFailure)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Map tiles unavailable — GPS tracking active',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Data class for terrain-coded segment markers on the map.
class MapSegmentMarker {
  final LatLng position;
  final String terrain;

  const MapSegmentMarker({
    required this.position,
    required this.terrain,
  });
}

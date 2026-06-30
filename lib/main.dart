import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

/// The root widget of the application.
///
/// routes the user to the main Radiomap screen.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wi-Fi Radiomap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const RadiomapApp(),
    );
  }
}

// Data models
/// Represents a single Wi-Fi access point scan result.
///
/// `bssid` is the unique hardware address, `ssid` is the network name,
/// and `level` is the signal strength in dBm.
class WiFiNetwork {
  final String bssid;
  final String ssid;
  final int level;

  WiFiNetwork({required this.bssid, required this.ssid, required this.level});

  @override
  String toString() => '$ssid ($bssid) - $level dBm';
}

/// Stores one radiomap measurement.
///
/// The coordinates are in centimeters in the app, but exported as meters.
/// `bssidRssiMap` maps each discovered BSSID to its averaged RSSI.
class ScanResult {
  final double x;
  final double y;
  final Map<String, int> bssidRssiMap; // bssid -> rssi

  ScanResult({
    required this.x,
    required this.y,
    required this.bssidRssiMap,
  });
}

/// One point along a guided path between two main nodes.
///
/// `distanceToNextCm` is the step length to the next point.
/// Route direction is defined at the route level and computed dynamically.
enum Direction { north, south, east, west }

extension DirectionHelpers on Direction {
  Direction reversed() {
    switch (this) {
      case Direction.north:
        return Direction.south;
      case Direction.south:
        return Direction.north;
      case Direction.east:
        return Direction.west;
      case Direction.west:
        return Direction.east;
    }
  }

  /// Returns the dx, dy vector in centimeters for a distance of 1 cm.
  /// Multiply by the desired distance to get the full offset.
  Offset toUnitOffset() {
    switch (this) {
      case Direction.north:
        return const Offset(0, 1);
      case Direction.south:
        return const Offset(0, -1);
      case Direction.east:
        return const Offset(1, 0);
      case Direction.west:
        return const Offset(-1, 0);
    }
  }
}

/// One point along a guided path between two main nodes.
///
/// `distanceToNextCm` is the step length to the next point. A route is
/// defined by a single cardinal `direction` and a list of distances.
class PathPoint {
  final double distanceToNextCm;

  const PathPoint({
    required this.distanceToNextCm,
  });
}

class PathRoute {
  final String from;
  final String to;
  final Direction direction;
  final List<PathPoint> points;

  PathRoute({
    required this.from,
    required this.to,
    required this.direction,
    required this.points,
  });

  PathRoute reversed() {
    final reversedPoints = points.reversed.toList();
    return PathRoute(
      from: to,
      to: from,
      direction: direction.reversed(),
      points: reversedPoints,
    );
  }
}

/// The predefined positions of the main anchor points A-L.
///
/// These coordinates are in centimeters. Fill in your real map values before
/// collecting measurements.
const Map<String, Offset> mainPointPositions = {
  'A': Offset(0, 0),
  'B': Offset(856.58, 0),
  'C': Offset(0, 3796.68),
  'D': Offset(856.58, 3796.68),
  'E': Offset(0, 4647.59),
  'F': Offset(856.58, 4647.59),
  'G': Offset(856.58, 4239.08),
  'H': Offset(-2156.55, 3796.68),
  'I': Offset(-2172.3, 4647.59),
  'J': Offset(0, 6136.74),
  'K': Offset(856.58, 6137.64),
  'L': Offset(1574.43, 4239.08),
};

/// Returns the absolute X/Y position for a path point in a route.
Offset computePathPointPosition(PathRoute route, int pointIndex) {
  final start = mainPointPositions[route.from] ?? const Offset(0, 0);
  var x = start.dx;
  var y = start.dy;

  for (var i = 0; i < pointIndex; i++) {
    final distance = route.points[i].distanceToNextCm;
    final step = route.direction.toUnitOffset();
    x += step.dx * distance;
    y += step.dy * distance;
  }

  return Offset(x, y);
}

/// Returns the absolute position of the route's final endpoint.
Offset computeRouteEndPosition(PathRoute route) {
  return computePathPointPosition(route, route.points.length - 1);
}

/// Hard-coded adjacency routes between main map nodes.
///
/// Each route defines the sequence of points between two adjacent nodes.
/// You can add or update these routes for your floor layout.
final List<PathRoute> pathRoutes = [
  PathRoute(
    from: 'A',
    to: 'B',
    direction: Direction.east,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 30.25),
      PathPoint(distanceToNextCm: 35.8),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 38.0),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 57.8),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'A',
    to: 'C',
    direction: Direction.north,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 48.15),
      PathPoint(distanceToNextCm: 30.1),
      PathPoint(distanceToNextCm: 23.4),
      PathPoint(distanceToNextCm: 30.1),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 55.8),
      PathPoint(distanceToNextCm: 30.1),
      PathPoint(distanceToNextCm: 51.35),
      PathPoint(distanceToNextCm: 57.45),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'B',
    to: 'D',
    direction: Direction.north,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 58.2),
      PathPoint(distanceToNextCm: 30.9),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 47.35),
      PathPoint(distanceToNextCm: 30.1),
      PathPoint(distanceToNextCm: 24.45),
      PathPoint(distanceToNextCm: 30.1),
      PathPoint(distanceToNextCm: 57.9),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'C',
    to: 'D',
    direction: Direction.east,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 56.75),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 38.05),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 38.1),
      PathPoint(distanceToNextCm: 30.25),
      PathPoint(distanceToNextCm: 58.0),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'C',
    to: 'H',
    direction: Direction.west,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 55.6),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 25.7),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'C',
    to: 'E',
    direction: Direction.north,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 57.0),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 34.9),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 41.56),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 55.65),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'D',
    to: 'G',
    direction: Direction.north,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 57.8),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 53.7),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'G',
    to: 'L',
    direction: Direction.east,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 57.2),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 29.0),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'G',
    to: 'F',
    direction: Direction.north,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 20.15),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 55.8),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'E',
    to: 'F',
    direction: Direction.east,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 56.65),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 16.0),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 57.69),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'E',
    to: 'I',
    direction: Direction.west,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 55.6),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 24.25),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 47.2),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'E',
    to: 'J',
    direction: Direction.north,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 57.2),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 56.5),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
  PathRoute(
    from: 'F',
    to: 'K',
    direction: Direction.north,
    points: const [
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 58.5),
      PathPoint(distanceToNextCm: 30.15),
      PathPoint(distanceToNextCm: 56.1),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
      PathPoint(distanceToNextCm: 60.15),
    ],
  ),
];

// Main app controller
/// The main app controller widget.
///
/// This widget manages the app phase (discovery vs measurement), keeps track
/// of networks we discovered, and holds the collected measurements.
class RadiomapApp extends StatefulWidget {
  const RadiomapApp({super.key});

  @override
  State<RadiomapApp> createState() => _RadiomapAppState();
}

class _RadiomapAppState extends State<RadiomapApp> {
  // All unique BSSIDs discovered during the discovery phase.
  Set<String> discoveredBSSIDs = {}; // All unique BSSIDs found

  // All recorded measurement points along the route.
  List<ScanResult> measurements = []; // All measurements

  // The current screen view: discovery first, then measurement.
  AppPhase currentPhase = AppPhase.discovery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wi-Fi Radiomap'),
        centerTitle: true,
      ),
      body: currentPhase == AppPhase.discovery
          ? DiscoveryScreen(
              discoveredBSSIDs: discoveredBSSIDs,
              onDiscoveryComplete: () {
                if (discoveredBSSIDs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No networks discovered!')),
                  );
                  return;
                }
                setState(() {
                  currentPhase = AppPhase.measurement;
                });
              },
            )
          : MeasurementScreen(
              discoveredBSSIDs: discoveredBSSIDs,
              measurements: measurements,
              onAddMeasurement: (measurement) {
                setState(() {
                  measurements.add(measurement);
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Measurement recorded!')),
                );
              },
              onExportCSV: () async {
                await _exportToCSV();
              },
              onBackToDiscovery: () {
                setState(() {
                  currentPhase = AppPhase.discovery;
                  discoveredBSSIDs.clear();
                  measurements.clear();
                });
              },
            ),
    );
  }

  /// Export the collected measurements to a CSV file and open the share sheet.
  ///
  /// The app stores coordinates in centimeters internally, but the CSV converts
  /// them to meters so the exported file is easier to use.
  Future<void> _exportToCSV() async {
    if (measurements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No measurements to export!')),
      );
      return;
    }

    try {
      // Create header row with x_m, y_m (convert from stored cm to meters), and all BSSIDs
      List<String> header = ['x_m', 'y_m'];
      List<String> sortedBSSIDs = discoveredBSSIDs.toList()..sort();
      header.addAll(sortedBSSIDs);

      // Create data rows
      List<List<dynamic>> rows = [header];
      for (var measurement in measurements) {
        // Measurements are stored in cm; convert to meters for export
        List<dynamic> row = [measurement.x / 100.0, measurement.y / 100.0];
        for (var bssid in sortedBSSIDs) {
          row.add(measurement.bssidRssiMap[bssid] ?? '');
        }
        rows.add(row);
      }

      // Convert to CSV
      String csv = const ListToCsvConverter().convert(rows);

      // Create a temporary CSV file for sharing
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final file = File('${directory.path}/radiomap_$timestamp.csv');
      await file.writeAsString(csv);

      if (!mounted) {
        return;
      }
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Wi-Fi Radiomap export',
        subject: 'Wi-Fi Radiomap CSV',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select an app to share the CSV file.'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting CSV: $e')),
        );
      }
    }
  }
}

enum AppPhase { discovery, measurement }

// Discovery Phase Screen
/// The discovery phase screen.
///
/// This screen is used to scan for nearby Wi-Fi networks and build the set of
/// BSSIDs that will be included in later measurements.
class DiscoveryScreen extends StatefulWidget {
  final Set<String> discoveredBSSIDs;
  final VoidCallback onDiscoveryComplete;

  const DiscoveryScreen({
    super.key,
    required this.discoveredBSSIDs,
    required this.onDiscoveryComplete,
  });

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  List<WiFiNetwork> currentScan = [];
  bool isScanning = false;

  Future<void> _performScan() async {
    setState(() {
      isScanning = true;
      currentScan = [];
    });

    try {
      // Check if we can start scan
      final canScan = await WiFiScan.instance.canStartScan(askPermissions: true);
      if (canScan != CanStartScan.yes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot scan: $canScan')),
          );
        }
        setState(() => isScanning = false);
        return;
      }

      // Start scan
      await WiFiScan.instance.startScan();

      // Check if we can get results
      final canGetResults = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
      if (canGetResults != CanGetScannedResults.yes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot get results: $canGetResults')),
          );
        }
        setState(() => isScanning = false);
        return;
      }

      // Get scanned results
      final results = await WiFiScan.instance.getScannedResults();

      setState(() {
        currentScan = results
            .map((ap) => WiFiNetwork(
                  bssid: ap.bssid,
                  ssid: ap.ssid,
                  level: ap.level,
                ))
            .toList();

        // Add all discovered BSSIDs
        for (var network in currentScan) {
          widget.discoveredBSSIDs.add(network.bssid);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e')),
        );
      }
    } finally {
      setState(() {
        isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.35,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  'Phase 1: Discovery',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Walk through the building and press "Scan" multiple times to discover all available Wi-Fi networks.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Discovered BSSIDs: ${widget.discoveredBSSIDs.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onDiscoveryComplete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Text('Start Measurements'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isScanning ? null : _performScan,
                icon: const Icon(Icons.wifi_find),
                label: isScanning ? const Text('Scanning...') : const Text('Scan Networks'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: currentScan.isEmpty
                ? Center(
                    child: Text(
                      isScanning ? 'Scanning...' : 'Press "Scan Networks" to start',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    itemCount: currentScan.length,
                    itemBuilder: (context, index) {
                      final network = currentScan[index];
                      return ListTile(
                        title: Text(network.ssid),
                        subtitle: Text(
                          '${network.bssid} • ${network.level} dBm',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: widget.discoveredBSSIDs.contains(network.bssid)
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// Measurement Phase Screen
/// The measurement phase screen.
///
/// This screen allows the user to scan points, add measurements, and export
/// those measurements to a CSV file.
class MeasurementScreen extends StatefulWidget {
  final Set<String> discoveredBSSIDs;
  final List<ScanResult> measurements;
  final Function(ScanResult) onAddMeasurement;
  final VoidCallback onExportCSV;
  final VoidCallback onBackToDiscovery;

  const MeasurementScreen({
    super.key,
    required this.discoveredBSSIDs,
    required this.measurements,
    required this.onAddMeasurement,
    required this.onExportCSV,
    required this.onBackToDiscovery,
  });

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  static const int numScansPerMeasurement = 10;
  static const int pathPointScanCount = 3;
  static const double routeValidationToleranceCm = 150.0;

  // Manual coordinate entry removed — guided path coordinates are used instead.
  List<WiFiNetwork> currentScan = [];
  bool isScanning = false;
  int currentScanCount = 0;
  List<List<WiFiNetwork>> scans = [];
  String selectedStartPoint = 'A';
  String? selectedEndPoint = 'B';
  PathRoute? selectedRoute;
  bool pathActive = false;
  int currentPathIndex = 0;
  bool currentPointScanned = false;
  List<String> routeSummaries = [];
  bool hasRouteValidationErrors = false;
  Set<String> newBssids = {};
  int currentPathPointScanCount = 0;

  @override
  void initState() {
    super.initState();
    _validateRouteSummaries();
  }

  void _validateRouteSummaries() {
    routeSummaries = [];
    hasRouteValidationErrors = false;

    for (final route in pathRoutes) {
      final start = mainPointPositions[route.from];
      final expectedEnd = mainPointPositions[route.to];
      final computedEnd = computeRouteEndPosition(route);

      if (start == null || expectedEnd == null) {
        routeSummaries.add('${route.from}→${route.to}: missing anchor position');
        hasRouteValidationErrors = true;
        continue;
      }

      final diff = (computedEnd - expectedEnd).distance;
      final status = diff <= routeValidationToleranceCm ? 'OK' : 'ERROR';
      if (status == 'ERROR') {
        hasRouteValidationErrors = true;
      }

      routeSummaries.add(
        '${route.from}→${route.to}: computed (${computedEnd.dx.toStringAsFixed(1)}, ${computedEnd.dy.toStringAsFixed(1)}) '
        'expected (${expectedEnd.dx.toStringAsFixed(1)}, ${expectedEnd.dy.toStringAsFixed(1)}) '
        '(Δ ${diff.toStringAsFixed(1)} cm) $status',
      );
    }
  }

  void _detectNewBssids(List<WiFiNetwork> scan) {
    final foundBssids = scan.map((network) => network.bssid).toSet();
    final newFound = foundBssids.difference(widget.discoveredBSSIDs);
    if (newFound.isNotEmpty) {
      setState(() {
        newBssids.addAll(newFound);
      });
    }
  }

  Future<void> _performScan() async {
    setState(() {
      isScanning = true;
      currentScan = [];
    });

    try {
      // Check if we can start scan
      final canScan = await WiFiScan.instance.canStartScan(askPermissions: true);
      if (canScan != CanStartScan.yes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot scan: $canScan')),
          );
        }
        setState(() => isScanning = false);
        return;
      }

      // Start scan
      await WiFiScan.instance.startScan();

      // Check if we can get results
      final canGetResults = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
      if (canGetResults != CanGetScannedResults.yes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot get results: $canGetResults')),
          );
        }
        setState(() => isScanning = false);
        return;
      }

      // Get scanned results
      final results = await WiFiScan.instance.getScannedResults();
      final scanResults = results
          .map((ap) => WiFiNetwork(
                bssid: ap.bssid,
                ssid: ap.ssid,
                level: ap.level,
              ))
          .toList();

      _detectNewBssids(scanResults);

      setState(() {
        currentScan = scanResults;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e')),
        );
      }
    } finally {
      setState(() {
        isScanning = false;
      });
    }
  }

  /// Perform multiple scans at one location and average the RSSI values.
  ///
  /// This helps smooth out temporary signal drops or missed packets by
  /// taking `numScansPerMeasurement` scans and averaging each BSSID's RSSI.
  Future<void> _performMultipleScanAndAverage() async {
    // This flow now requires guided path mode: use the current guided
    // path point coordinates as the measurement location.
    if (!pathActive || selectedRoute == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start a guided path first to record measurements.')),
      );
      return;
    }

    final pointPosition = computePathPointPosition(selectedRoute!, currentPathIndex);
    final x = pointPosition.dx;
    final y = pointPosition.dy;

    setState(() {
      isScanning = true;
      currentScanCount = 0;
      scans = [];
      currentScan = [];
    });

    try {
      for (int i = 0; i < numScansPerMeasurement; i++) {
        // Check if we can start scan
        final canScan = await WiFiScan.instance.canStartScan(askPermissions: true);
        if (canScan != CanStartScan.yes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cannot scan: $canScan')),
            );
          }
          return;
        }

        // Start scan
        await WiFiScan.instance.startScan();

        // Check if we can get results
        final canGetResults = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
        if (canGetResults != CanGetScannedResults.yes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cannot get results: $canGetResults')),
            );
          }
          return;
        }

        // Get scanned results
        final results = await WiFiScan.instance.getScannedResults();
        final scanResults = results
            .map((ap) => WiFiNetwork(
                  bssid: ap.bssid,
                  ssid: ap.ssid,
                  level: ap.level,
                ))
            .toList();

        _detectNewBssids(scanResults);

        setState(() {
          scans.add(scanResults);
          currentScanCount = i + 1;
          currentScan = scanResults;
        });

        // Small delay between scans
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Average the RSSI values
      Map<String, List<int>> bssidRssiValues = {};
      for (var bssid in widget.discoveredBSSIDs) {
        bssidRssiValues[bssid] = [];
      }

      for (var scan in scans) {
        for (var network in scan) {
          if (bssidRssiValues.containsKey(network.bssid)) {
            bssidRssiValues[network.bssid]!.add(network.level);
          }
        }
      }

      // Calculate averages
      Map<String, int> averagedRssi = {};
      for (var bssid in widget.discoveredBSSIDs) {
        final values = bssidRssiValues[bssid] ?? [];
        if (values.isNotEmpty) {
          final avg = (values.reduce((a, b) => a + b) / values.length).round();
          averagedRssi[bssid] = avg;
        } else {
          averagedRssi[bssid] = -120; // Default for missing networks
        }
      }

      if (mounted) {
        widget.onAddMeasurement(
          ScanResult(
            x: x,
            y: y,
            bssidRssiMap: averagedRssi,
          ),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Measurement averaged and recorded!')),
        );

        setState(() {
          currentScan = [];
          scans = [];
          currentScanCount = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Multi-scan error: $e')),
        );
      }
    } finally {
      setState(() {
        isScanning = false;
      });
    }
  }

  /// Return a sorted list of adjacent endpoints for a given start node.
  ///
  /// This is used to fill the path selection dropdown.
  List<String> _availableEndPoints(String start) {
    final options = <String>{};
    for (final route in pathRoutes) {
      if (route.from == start) options.add(route.to);
      if (route.to == start) options.add(route.from);
    }
    final sorted = options.toList()..sort();
    return sorted;
  }

  /// Find a configured path route between two main points.
  ///
  /// If the route exists in reverse direction, it returns a reversed copy.
  PathRoute? _findRoute(String start, String end) {
    for (final route in pathRoutes) {
      if (route.from == start && route.to == end) return route;
    }
    for (final route in pathRoutes) {
      if (route.from == end && route.to == start) return route.reversed();
    }
    return null;
  }

  /// Scan the Wi-Fi network at the current guided path point.
  ///
  /// This performs multiple scans and averages the RSSI values for better
  /// accuracy before the point is saved.
  Future<void> _scanPathPoint() async {
    if (selectedRoute == null) {
      return;
    }

    setState(() {
      isScanning = true;
      currentPathPointScanCount = 0;
      scans = [];
      currentScan = [];
      currentPointScanned = false;
    });

    try {
      for (var i = 0; i < pathPointScanCount; i++) {
        final canScan = await WiFiScan.instance.canStartScan(askPermissions: true);
        if (canScan != CanStartScan.yes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cannot scan: $canScan')),
            );
          }
          return;
        }

        await WiFiScan.instance.startScan();
        final canGetResults = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
        if (canGetResults != CanGetScannedResults.yes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cannot get results: $canGetResults')),
            );
          }
          return;
        }

        final results = await WiFiScan.instance.getScannedResults();
        final scanResults = results
            .map((ap) => WiFiNetwork(
                  bssid: ap.bssid,
                  ssid: ap.ssid,
                  level: ap.level,
                ))
            .toList();

        _detectNewBssids(scanResults);

        setState(() {
          scans.add(scanResults);
          currentPathPointScanCount = i + 1;
          currentScan = scanResults;
        });

        if (i < pathPointScanCount - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      final averagedScan = _averageScansToNetworkList(scans);
      setState(() {
        currentScan = averagedScan;
        currentPointScanned = true;
        currentPathPointScanCount = 0;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Averaged $pathPointScanCount scans for this point.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Path scan error: $e')),
        );
      }
    } finally {
      setState(() {
        isScanning = false;
      });
    }
  }

  /// Build a map from the current scan results to the full discovered BSSID set.
  ///
  /// Missing networks are given a default low RSSI so the CSV still includes them.
  Map<String, int> _buildBssidRssiMap(List<WiFiNetwork> scan) {
    final map = <String, int>{};
    for (var bssid in widget.discoveredBSSIDs) {
      final network = scan.firstWhere(
        (n) => n.bssid == bssid,
        orElse: () => WiFiNetwork(bssid: bssid, ssid: 'N/A', level: -120),
      );
      map[bssid] = network.level;
    }
    return map;
  }

  List<WiFiNetwork> _averageScansToNetworkList(List<List<WiFiNetwork>> scans) {
    final values = <String, List<int>>{};
    final ssidByBssid = <String, String>{};

    for (final scan in scans) {
      for (final network in scan) {
        values.putIfAbsent(network.bssid, () => []).add(network.level);
        ssidByBssid[network.bssid] = network.ssid;
      }
    }

    final averaged = <WiFiNetwork>[];
    for (final bssid in values.keys.toList()..sort()) {
      final levels = values[bssid]!;
      final avg = (levels.reduce((a, b) => a + b) / levels.length).round();
      averaged.add(WiFiNetwork(
        bssid: bssid,
        ssid: ssidByBssid[bssid] ?? 'N/A',
        level: avg,
      ));
    }

    for (final bssid in widget.discoveredBSSIDs) {
      if (!values.containsKey(bssid)) {
        averaged.add(WiFiNetwork(bssid: bssid, ssid: 'N/A', level: -120));
      }
    }

    averaged.sort((a, b) => a.bssid.compareTo(b.bssid));
    return averaged;
  }

  /// Save the current path point measurement and move to the next one.
  ///
  /// The current point must be scanned before moving to the next point.
  void _nextPathPoint() {
    if (!pathActive || selectedRoute == null) {
      return;
    }
    if (!currentPointScanned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please scan the current point before moving next.')),
      );
      return;
    }

    final pointPosition = computePathPointPosition(selectedRoute!, currentPathIndex);
    widget.onAddMeasurement(
      ScanResult(
        x: pointPosition.dx,
        y: pointPosition.dy,
        bssidRssiMap: _buildBssidRssiMap(currentScan),
      ),
    );

    final isLastPoint = currentPathIndex == selectedRoute!.points.length;
    if (isLastPoint) {
      setState(() {
        pathActive = false;
        selectedRoute = null;
        currentPathIndex = 0;
        currentPointScanned = false;
        currentScan = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Path complete. All points recorded.')),
      );
      return;
    }

    setState(() {
      currentPathIndex += 1;
      currentPointScanned = false;
      currentScan = [];
    });
  }

  /// Start a guided path between the selected main points.
  ///
  /// This enables the guided scan flow and initializes the first point.
  void _startPath() {
    if (selectedEndPoint == null) {
      return;
    }
    final route = _findRoute(selectedStartPoint, selectedEndPoint!);
    if (route == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selected path is not configured.')),
      );
      return;
    }

    setState(() {
      selectedRoute = route;
      pathActive = true;
      currentPathIndex = 0;
      currentPointScanned = false;
      currentScan = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  'Phase 2: Measurement',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Measurements: ${widget.measurements.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (routeSummaries.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: hasRouteValidationErrors
                          ? Colors.red.shade50
                          : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Route validation',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          hasRouteValidationErrors
                              ? 'Some routes differ from anchors by more than ${routeValidationToleranceCm.toInt()} cm.'
                              : 'All routes validate within ${routeValidationToleranceCm.toInt()} cm.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 120,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: routeSummaries
                                  .map(
                                    (summary) => Padding(
                                      padding: const EdgeInsets.only(bottom: 4.0),
                                      child: Text(
                                        summary,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (newBssids.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Warning: new access point(s) discovered during measurement: ${newBssids.join(', ')}.\nThese were not found in discovery phase.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55,
                  ),
                  child: SingleChildScrollView(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Guided path scan',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          // If no active path, show the route selectors and Start button.
                          if (!pathActive)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DropdownButtonFormField<String>(
                                  initialValue: selectedStartPoint,
                                  decoration: const InputDecoration(
                                    labelText: 'From',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: pathRoutes
                                      .map((route) => route.from)
                                      .toSet()
                                      .toList()
                                      .map((label) => DropdownMenuItem(
                                            value: label,
                                            child: Text(label),
                                          ))
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() {
                                      selectedStartPoint = value;
                                      final options = _availableEndPoints(value);
                                      selectedEndPoint = options.isNotEmpty ? options.first : null;
                                    });
                                  },
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: selectedEndPoint,
                                  decoration: const InputDecoration(
                                    labelText: 'To',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _availableEndPoints(selectedStartPoint)
                                      .map((label) => DropdownMenuItem(
                                            value: label,
                                            child: Text(label),
                                          ))
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      selectedEndPoint = value;
                                    });
                                  },
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: _startPath,
                                    child: const Text('Start Path'),
                                  ),
                                ),
                              ],
                            )
                          else
                            // If a path is active, show the guided path controls.
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Path: ${selectedRoute?.from} → ${selectedRoute?.to}',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Point ${currentPathIndex + 1} of ${(selectedRoute?.points.length ?? 0) + 1}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  selectedRoute == null
                                      ? ''
                                      : 'Current point: point ${currentPathIndex + 1} at (${computePathPointPosition(selectedRoute!, currentPathIndex).dx.toStringAsFixed(1)} , ${computePathPointPosition(selectedRoute!, currentPathIndex).dy.toStringAsFixed(1)}) cm',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: isScanning ? null : _scanPathPoint,
                                        child: const Text('Scan Current Point'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: currentPointScanned ? _nextPathPoint : null,
                                        child: const Text('Next Point'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  currentPointScanned
                                      ? 'Scanned. Press Next Point to save and proceed.'
                                      : 'Scan the current point before moving to the next.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setState(() {
                                        pathActive = false;
                                        selectedRoute = null;
                                        currentPathIndex = 0;
                                        currentPointScanned = false;
                                        currentScan = [];
                                      });
                                    },
                                    child: const Text('Cancel Path'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Coordinate inputs
                // Manual coordinate inputs removed — use Guided Path scanning.
                if (pathActive && selectedRoute != null) ...[
                  Text(
                    'Current point coords: (${computePathPointPosition(selectedRoute!, currentPathIndex).dx.toStringAsFixed(1)}, ${computePathPointPosition(selectedRoute!, currentPathIndex).dy.toStringAsFixed(1)}) cm',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  Text(
                    'Manual coordinate entry removed — start a Guided Path to record points.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isScanning ? null : _performScan,
                    icon: const Icon(Icons.wifi_find),
                    label: isScanning ? const Text('Scanning...') : const Text('Scan Networks'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isScanning ? null : _performMultipleScanAndAverage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: Text(isScanning
                        ? 'Recording ($currentScanCount/$numScansPerMeasurement)'
                        : 'Record Measurement (avg $numScansPerMeasurement scans)'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
          Expanded(
            child: currentScan.isEmpty
                ? Center(
                    child: Text(
                      'Networks detected: ${widget.discoveredBSSIDs.length}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    itemCount: currentScan.length,
                    itemBuilder: (context, index) {
                      final network = currentScan[index];
                      final isDiscovered =
                          widget.discoveredBSSIDs.contains(network.bssid);
                      return ListTile(
                        title: Text(network.ssid),
                        subtitle: Text(
                          '${network.bssid} • ${network.level} dBm',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: isDiscovered
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : const Icon(Icons.warning, color: Colors.orange),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onExportCSV,
                    icon: const Icon(Icons.file_download),
                    label: const Text('Export to CSV'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: widget.onBackToDiscovery,
                    child: const Text('Start Over'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const MyApp());
}

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
class WiFiNetwork {
  final String bssid;
  final String ssid;
  final int level;

  WiFiNetwork({required this.bssid, required this.ssid, required this.level});

  @override
  String toString() => '$ssid ($bssid) - $level dBm';
}

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

// Main app controller
class RadiomapApp extends StatefulWidget {
  const RadiomapApp({super.key});

  @override
  State<RadiomapApp> createState() => _RadiomapAppState();
}

class _RadiomapAppState extends State<RadiomapApp> {
  Set<String> discoveredBSSIDs = {}; // All unique BSSIDs found
  List<ScanResult> measurements = []; // All measurements
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

      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Wi-Fi Radiomap export',
          subject: 'Wi-Fi Radiomap CSV',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select an app to share the CSV file.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
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
          Padding(
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
  final TextEditingController xController = TextEditingController();
  final TextEditingController yController = TextEditingController();
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

  void _recordMeasurement() {
    final x = double.tryParse(xController.text);
    final y = double.tryParse(yController.text);

    if (x == null || y == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid X and Y coordinates (cm)')),
      );
      return;
    }

    if (currentScan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please scan networks first')),
      );
      return;
    }

    // Create RSSI map for all discovered BSSIDs
    Map<String, int> bssidRssiMap = {};
    for (var bssid in widget.discoveredBSSIDs) {
      final network = currentScan.firstWhere(
        (n) => n.bssid == bssid,
        orElse: () => WiFiNetwork(bssid: bssid, ssid: 'N/A', level: -120),
      );
      bssidRssiMap[bssid] = network.level;
    }

    widget.onAddMeasurement(
      ScanResult(
        x: x,
        y: y,
        bssidRssiMap: bssidRssiMap,
      ),
    );

    // Clear inputs
    xController.clear();
    yController.clear();
    setState(() {
      currentScan = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
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
              const SizedBox(height: 16),
              // Coordinate inputs
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: xController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'X (cm)',
                        hintText: 'e.g., 123.4',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: yController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Y (cm)',
                        hintText: 'e.g., 45.0',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                  onPressed: _recordMeasurement,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                  ),
                  child: const Text('Record Measurement'),
                ),
              ),
            ],
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
    );
  }

  @override
  void dispose() {
    xController.dispose();
    yController.dispose();
    super.dispose();
  }
}

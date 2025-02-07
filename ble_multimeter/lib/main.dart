// main.dart
// ignore_for_file: deprecated_member_use, constant_identifier_names, avoid_print, avoid_redundant_argument_values, avoid_dynamic_calls

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MultimeterApp());
}

class MultimeterApp extends StatelessWidget {
  const MultimeterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Akıllı BLE Multimetre',
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
          background: Colors.black,
        ),
        textTheme: GoogleFonts.unboundedTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
          background: Colors.black,
        ),
        textTheme: GoogleFonts.unboundedTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  // BLE State Management
  BluetoothDevice? _connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  // UI State
  bool _isScanning = false;
  String _statusMessage = '';
  final Map<String, dynamic> _measurements = {
    'continuity': 0.0,
    'resistance': 0.0,
    'dc_voltage': {'high': 0.0, 'low': 0.0},
    'ac_voltage': 0.0,
    'current': 0.0,
  };

  // Animation
  late AnimationController _animationController;

  // BLE Configuration
  static const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String CHARACTERISTIC_UUID =
      "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    if (!(await FlutterBluePlus.isSupported)) {
      _updateStatus('Bluetooth desteklenmiyor');
      return;
    }
    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.any((status) => !status.isGranted)) {
      _updateStatus('Gerekli izinler verilmedi');
    }
  }

  void _updateStatus(String message) {
    setState(() => _statusMessage = message);
  }

  Future<void> _startScan() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _statusMessage = 'Cihazlar taranıyor...';
    });

    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription =
          FlutterBluePlus.scanResults.listen(_handleScanResults);
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    } catch (e) {
      _updateStatus('Tarama hatası: $e');
    } finally {
      await Future.delayed(const Duration(seconds: 4));
      setState(() => _isScanning = false);
    }
  }

  void _handleScanResults(List<ScanResult> results) {
    for (final result in results) {
      if (result.device.name == "ESP32-Multimeter") {
        _connectToDevice(result.device);
        FlutterBluePlus.stopScan();
        break;
      }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      _updateStatus('Bağlanılıyor...');
      await device.connect();

      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.toString() == SERVICE_UUID) {
          await _setupCharacteristics(service);
        }
      }

      setState(() => _connectedDevice = device);
      _updateStatus('Bağlantı başarılı');
    } catch (e) {
      _updateStatus('Bağlantı hatası: $e');
    }
  }

  Future<void> _setupCharacteristics(BluetoothService service) async {
    for (final characteristic in service.characteristics) {
      if (characteristic.uuid.toString() == CHARACTERISTIC_UUID) {
        await characteristic.setNotifyValue(true);
        characteristic.value.listen(_handleDataUpdate);
      }
    }
  }

  void _handleDataUpdate(List<int> value) {
    try {
      final rawData = String.fromCharCodes(value);
      print("[BLE DATA] $rawData");

      setState(() {
        if (rawData.startsWith("CONT:")) {
          _measurements['continuity'] = rawData.contains("1") ? 1.0 : 0.0;
        } else if (rawData.startsWith("RES:")) {
          _measurements['resistance'] = double.parse(rawData.split(":")[1]);
        } else if (rawData.startsWith("DCV:")) {
          final parts = rawData.split(":")[1].split(",");
          _measurements['dc_voltage'] = {
            'high': double.parse(parts[0]),
            'low': double.parse(parts[1]),
          };
        } else if (rawData.startsWith("ACV:")) {
          _measurements['ac_voltage'] = double.parse(rawData.split(":")[1]);
        } else if (rawData.startsWith("CUR:")) {
          _measurements['current'] = double.parse(rawData.split(":")[1]);
        }
      });
    } catch (e) {
      print('[DATA ERROR] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            floating: true,
            pinned: true,
            backgroundColor: colorScheme.background,
            title: Text(
              ' Akıllı BLE Multimetre',
              style: GoogleFonts.unbounded(
                fontWeight: FontWeight.bold,
                color: colorScheme.onBackground,
              ),
            ),
            actions: [
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle:
                        _isScanning ? _animationController.value * 2 * 3.14 : 0,
                    child: IconButton(
                      icon: Icon(
                        _connectedDevice != null
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: _connectedDevice != null
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                      onPressed: null,
                    ),
                  );
                },
              ),
            ],
          ),
          if (_connectedDevice == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(100.0),
                child: Column(
                  children: [
                    if (_statusMessage.isNotEmpty)
                      _StatusMessage(message: _statusMessage),
                    const SizedBox(height: 36),
                    if (_isScanning)
                      _ScanningAnimation()
                    else
                      _ScanButton(onPressed: _startScan),
                  ],
                ),
              ),
            ),
          if (_connectedDevice != null)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _MeasurementCard(
                    title: 'İletkenlik',
                    value: _measurements['continuity'] == 1
                        ? 'Bağlı'
                        : 'Bağlı Değil',
                    icon: Icons.power,
                    color: _measurements['continuity'] == 1
                        ? Colors.green
                        : Colors.red,
                    isFullWidth: true,
                  ),
                  const SizedBox(height: 36),
                  Row(
                    children: [
                      Expanded(
                        child: _MeasurementCard(
                          title: 'Direnç',
                          value:
                              '${_measurements['resistance'].toStringAsFixed(2)} Ω',
                          icon: Icons.track_changes,
                          color: const Color(0xFF6C63FF),
                        ),
                      ),
                      const SizedBox(width: 36),
                      Expanded(
                        child: _MeasurementCard(
                          title: 'DC Voltaj',
                          value:
                              'Y: ${(_measurements['dc_voltage'] as Map)['high'].toStringAsFixed(2)}V\nA: ${(_measurements['dc_voltage'] as Map)['low'].toStringAsFixed(2)}V',
                          icon: Icons.bolt,
                          color: const Color.fromARGB(255, 255, 23, 185),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Row(
                    children: [
                      Expanded(
                        child: _MeasurementCard(
                          title: 'AC Voltaj',
                          value:
                              '${_measurements['ac_voltage'].toStringAsFixed(2)}V',
                          icon: Icons.electrical_services,
                          color: const Color(0xFF4ECDC4),
                        ),
                      ),
                      const SizedBox(width: 36),
                      Expanded(
                        child: _MeasurementCard(
                          title: 'Akım',
                          value:
                              '${_measurements['current'].toStringAsFixed(3)}A',
                          icon: Icons.waves,
                          color: const Color(0xFFFFBE0B),
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scanSubscription?.cancel();
    _connectedDevice?.disconnect();
    super.dispose();
  }
}

// Custom Widgets
class _StatusMessage extends StatelessWidget {
  final String message;
  const _StatusMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message,
          style: GoogleFonts.unbounded(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ScanningAnimation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 400,
      width: 400,
      child: Lottie.asset(
        'assets/loader.json',
        height: 360,
        width: 360,
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ScanButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      icon: const Icon(Icons.search),
      label: Text(
        'Taramayı Başlat',
        style: GoogleFonts.unbounded(),
      ),
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.all(20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _MeasurementCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool isFullWidth;

  const _MeasurementCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: isFullWidth ? 200 : 180,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ColorFilter.mode(
            color.withOpacity(0.05),
            BlendMode.srcOver,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: color, size: isFullWidth ? 40 : 32),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.unbounded(
                    fontSize: isFullWidth ? 16 : 14,
                    fontWeight: FontWeight.w500,
                    color: color.withOpacity(0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: GoogleFonts.unbounded(
                    fontSize: isFullWidth ? 20 : 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

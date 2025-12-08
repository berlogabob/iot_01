import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'firebase_options.dart'; // ← этот файл создадим на шаге 4

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // автоматически подтянет веб-конфиг
  );
  runApp(const BikeStorageApp());
}

class BikeStorageApp extends StatelessWidget {
  const BikeStorageApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bike Storage Pod',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
  final db = FirebaseDatabase.instance.ref();
  late TabController _tabController;

  String qrCode = '';
  int? bookedCell;
  String mainDoorState = 'closed';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    db.child('door_main/state').onValue.listen((e) {
      setState(() => mainDoorState = e.snapshot.value as String? ?? 'closed');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightGreen[100],
      appBar: AppBar(
        backgroundColor: Colors.teal[600],
        title: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'User'),
            Tab(text: 'Dev'),
            Tab(text: 'Scan'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ==================== TOP BLOCK (changes with tab) ====================
          Expanded(
            flex: 4,
            child: TabBarView(
              controller: _tabController,
              children: [
                // USER TAB → Calendar / GrafPlotter placeholder
                Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[400],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'CALENDAR FOR BOOKING\n/\nGRAF PLOTTER',
                      style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // DEV TAB → 12 cells status
                const DeveloperCellsView(),

                // SCAN TAB → full screen scanner
                const ScannerView(),
              ],
            ),
          ),

          // ==================== THREE BIG BUTTONS (always visible) ====================
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (qrCode.isNotEmpty) ...[
                  SizedBox(
                    height: 200,
                    child: QrImageView(data: qrCode, size: 200),
                  ),
                  const SizedBox(height: 20),
                ],
                BigRedButton(
                  text: 'SHOW QR-CODE',
                  onTap: () => db.child('active_booking/code').get().then((s) {
                    if (s.value != null) setState(() => qrCode = s.value as String);
                  }),
                ),
                BigRedButton(
                  text: 'OPEN DOOR\n$mainDoorState'.toUpperCase(),
                  onTap: () => _tryOpenMainDoor(),
                ),
                BigRedButton(
                  text: bookedCell == null ? 'OPEN CELL' : 'OPEN CELL $bookedCell',
                  onTap: () => _tryOpenCellDoor(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _tryOpenMainDoor() async {
    final snap = await db.child('active_booking').get();
    final data = snap.value as Map<dynamic, dynamic>?;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (data == null || now < data['start_time'] || now > data['end_time']) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking time not active')));
      return;
    }
    // 5-second cycle
    db.child('door_main/state').set('opening');
    await Future.delayed(const Duration(seconds: 2));
    db.child('door_main/state').set('open');
    await Future.delayed(const Duration(seconds: 3));
    db.child('door_main/state').set('closed');
  }

  Future<void> _tryOpenCellDoor() async {
    final snap = await db.child('active_booking').get();
    final data = snap.value as Map<dynamic, dynamic>?;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (data == null || now < data['start_time'] || now > data['end_time']) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking time not active')));
      return;
    }
    final cell = data['cell'] as int;
    setState(() => bookedCell = cell);
    // later real servo command – for now just simulate
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cell $cell opening...')));
  }
}

// Big red button exactly like in your sketch
class BigRedButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const BigRedButton({super.key, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        height: 80,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[600],
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: onTap,
          child: Text(text, style: const TextStyle(fontSize: 28, color: Colors.white)),
        ),
      ),
    );
  }
}

// Dev tab – 12 cells status
class DeveloperCellsView extends StatelessWidget {
  const DeveloperCellsView({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('cells').onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!.snapshot.value as Map<dynamic, dynamic>? ?? {};
        return GridView.count(
          crossAxisCount: 3,
          padding: const EdgeInsets.all(20),
          children: List.generate(12, (i) {
            final status = data[(i + 1).toString()]?['status'] ?? 'free';
            return Card(
              color: status == 'free' ? Colors.green[200] : Colors.red[200],
              child: Center(child: Text('Cell ${i + 1}\n${status.toUpperCase()}', textAlign: TextAlign.center)),
            );
          }),
        );
      },
    );
  }
}

// Scan tab – full screen scanner with timer overlay
class ScannerView extends StatelessWidget {
  const ScannerView({super.key});
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (barcode) {
            final code = barcode.barcodes.first.rawValue ?? '';
            if (code.isNotEmpty) _validateAndEnableDoor(code);
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: StreamBuilder<DatabaseEvent>(
            stream: FirebaseDatabase.instance.ref('door_main/enabled_until').onValue,
            builder: (context, snapshot) {
              final until = snapshot.data?.snapshot.value as int? ?? 0;
              final left = (until - DateTime.now().millisecondsSinceEpoch) ~/ 1000;
              if (left > 0) {
                return Container(
                  width: double.infinity,
                  color: Colors.green.withOpacity(0.9),
                  padding: const EdgeInsets.all(20),
                  child: Text('ACCESS: $left sec', style: const TextStyle(fontSize: 40, color: Colors.white), textAlign: TextAlign.center),
                );
              }
              return const SizedBox();
            },
          ),
        ),
      ],
    );
  }

  Future<void> _validateAndEnableDoor(String code) async {
    final snap = await FirebaseDatabase.instance.ref('active_booking').get();
    final data = snap.value as Map<dynamic, dynamic>? ?? {};
    final now = DateTime.now().millisecondsSinceEpoch;
    if (data['code'] == code && now >= data['start_time'] && now <= data['end_time']) {
      FirebaseDatabase.instance.ref('door_main').update({
        'enabled': true,
        'enabled_until': now + 90000,
      });
    }
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const BikeStorageApp());
}

class BikeStorageApp extends StatelessWidget {
  const BikeStorageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bike Storage Pod',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1A1A1A),
          secondary: Color(0xFF7CA8D6),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        textTheme: GoogleFonts.spaceGroteskTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A3D62),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[600],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
      ),
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
  late TabController _tabController;
  final db = FirebaseDatabase.instance.ref();

  String qrCode = '';
  int? bookedCell;
  DateTime? startTime;
  DateTime? endTime;
  String mainDoorStatus = 'CLOSED';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    db.child('door_main/state').onValue.listen((event) {
      setState(() {
        mainDoorStatus = (event.snapshot.value as String?)?.toUpperCase() ?? 'CLOSED';
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bookCell() async {
    if (startTime == null || endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select time')));
      return;
    }

    final snapshot = await db.child('cells').get();
    final cells = snapshot.value as Map<dynamic, dynamic>? ?? {};
    int? freeCell;
    for (int i = 1; i <= 12; i++) {
      if (cells[i.toString()]?['status'] == 'free') {
        freeCell = i;
        break;
      }
    }

    if (freeCell == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No free cells')));
      return;
    }

    final code = DateTime.now().millisecondsSinceEpoch.toString();
    await db.update({
      'cells/$freeCell/status': 'booked',
      'cells/$freeCell/booking_code': code,
      'active_booking/code': code,
      'active_booking/cell': freeCell,
      'active_booking/start_time': startTime!.millisecondsSinceEpoch,
      'active_booking/end_time': endTime!.millisecondsSinceEpoch,
    });

    setState(() {
      qrCode = code;
      bookedCell = freeCell;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'User'),
            Tab(text: 'Dev'),
            Tab(text: 'Scan'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          UserTab(
            startTime: startTime,
            endTime: endTime,
            onStartChanged: (d) => setState(() => startTime = d),
            onEndChanged: (d) => setState(() => endTime = d),
            onBook: _bookCell,
            qrCode: qrCode,
            bookedCell: bookedCell,
            mainDoorStatus: mainDoorStatus,
          ),
          const DevTab(),
          const ScannerTab(),
        ],
      ),
    );
  }
}

// USER TAB
class UserTab extends StatelessWidget {
  final DateTime? startTime;
  final DateTime? endTime;
  final Function(DateTime?) onStartChanged;
  final Function(DateTime?) onEndChanged;
  final VoidCallback onBook;
  final String qrCode;
  final int? bookedCell;
  final String mainDoorStatus;

  const UserTab({
    super.key,
    required this.startTime,
    required this.endTime,
    required this.onStartChanged,
    required this.onEndChanged,
    required this.onBook,
    required this.qrCode,
    required this.bookedCell,
    required this.mainDoorStatus,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.red[600],
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Text('Select booking time', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 7)),
                  );
                  if (date != null) {
                    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (time != null) {
                      onStartChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
                    }
                  }
                },
                child: Text(
                  startTime == null ? 'Start time' : 'Start: ${startTime!.toString().substring(11, 16)}',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 7)),
                  );
                  if (date != null) {
                    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                    if (time != null) {
                      onEndChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
                    }
                  }
                },
                child: Text(
                  endTime == null ? 'End time' : 'End: ${endTime!.toString().substring(11, 16)}',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: onBook,
                child: const Text('BOOK', style: TextStyle(fontSize: 32)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        if (qrCode.isNotEmpty) ...[
          Center(child: QrImageView(data: qrCode, size: 300)),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => FirebaseDatabase.instance.ref('door_main/state').set('opening'),
            child: Text('OPEN MAIN DOOR\n$mainDoorStatus', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28)),
          ),
          const SizedBox(height: 20),
          if (bookedCell != null)
            ElevatedButton(
              onPressed: () => FirebaseDatabase.instance.ref('cells/$bookedCell/state').set('opening'),
              child: Text('OPEN CELL $bookedCell', style: const TextStyle(fontSize: 28)),
            ),
        ],
        const SizedBox(height: 30),
        Text(
          'Main Door Status: $mainDoorStatus',
          style: TextStyle(fontSize: 22, color: mainDoorStatus == 'OPEN' ? Colors.green : Colors.red[800]),
        ),
      ],
    );
  }
}

// DEV TAB — full dashboard (no red screen)
class DevTab extends StatefulWidget {
  const DevTab({super.key});

  @override
  State<DevTab> createState() => _DevTabState();
}

class _DevTabState extends State<DevTab> {
  int selectedCell = 1;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Pod Control: POD-GCT-001A', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const Text('Firmware: v2.7.1', style: TextStyle(fontSize: 18, color: Colors.grey)),
        const SizedBox(height: 20),
        const Row(children: [Icon(Icons.check_circle, color: Colors.green, size: 50), SizedBox(width: 16), Text('Available', style: TextStyle(fontSize: 24))]),
        const SizedBox(height: 30),

        const Text('Slot-Level Occupancy', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance.ref('cells').onValue,
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: CircularProgressIndicator());
            }

            Map<dynamic, dynamic> data = {};
            final raw = snapshot.data!.snapshot.value;
            if (raw is Map) {
              data = raw;
            } else if (raw is List) {
              for (int i = 0; i < raw.length; i++) {
                if (raw[i] != null) data[(i + 1).toString()] = raw[i];
              }
            }

            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.2,
              children: List.generate(12, (i) {
                final num = i + 1;
                final status = (data[num.toString()] as Map?)?['status'] ?? 'free';
                return Container(
                  decoration: BoxDecoration(
                    color: status == 'free' ? Colors.green : Colors.red[700],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text('SLOT $num\n$status', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                );
              }),
            );
          },
        ),
        const SizedBox(height: 30),

        ElevatedButton(
          onPressed: () => FirebaseDatabase.instance.ref('door_main/state').set('opening'),
          child: const Text('FORCE OPEN MAIN DOOR'),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () => FirebaseDatabase.instance.ref('door_main/state').set('closed'),
          child: const Text('FORCE CLOSE MAIN DOOR'),
        ),
        const SizedBox(height: 30),

        const Text('Select cell to open:', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          children: List.generate(12, (i) {
            final n = i + 1;
            return ChoiceChip(
              label: Text('$n', style: const TextStyle(fontSize: 20)),
              selected: selectedCell == n,
              selectedColor: Colors.orange,
              onSelected: (v) => setState(() => selectedCell = n),
            );
          }),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => FirebaseDatabase.instance.ref('cells/$selectedCell/state').set('opening'),
          child: Text('OPEN CELL $selectedCell'),
        ),
        const SizedBox(height: 40),

        Container(
          height: 200,
          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(16)),
          child: const Center(child: Text('Occupancy Forecast (24h)', style: TextStyle(fontSize: 24))),
        ),
      ],
    );
  }
}

// SCAN TAB
class ScannerTab extends StatelessWidget {
  const ScannerTab({super.key});

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      onDetect: (barcode) {
        final code = barcode.barcodes.first.rawValue ?? '';
        if (code.isNotEmpty) {
          final now = DateTime.now().millisecondsSinceEpoch;
          FirebaseDatabase.instance.ref('door_main').update({
            'enabled': true,
            'enabled_until': now + 90000,
          });
        }
      },
    );
  }
}

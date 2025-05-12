// Imports required packages for Flutter, geolocation, HTTP requests, file storage, permissions, icons, and file sharing
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

// Entry point of the application
void main() {
  runApp(const AirPollutionTrackerApp());
}

/// Main application widget that sets up the app's theme and home page
class AirPollutionTrackerApp extends StatelessWidget {
  const AirPollutionTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Air Pollution Tracker',
      debugShowCheckedModeBanner: false, // Disables the debug banner
      theme: ThemeData(
        primaryColor: const Color(0xFFA5D6A7), // Soft green primary color
        scaffoldBackgroundColor: const Color(0xFFE8F5E9), // Light green background
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50), // Dark green button color
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), // Rounded button corners
            ),
            elevation: 5, // Button shadow
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xFF333333), fontSize: 16), // Dark gray text
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFA5D6A7), // Soft green AppBar
          foregroundColor: Color(0xFF333333),
          centerTitle: true, // Centers the AppBar title
          elevation: 0, // No AppBar shadow
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 3, // Card shadow
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      home: const HomePage(),
    );
  }
}

/// Home page widget that displays tracking controls and location data
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

/// State for HomePage, managing tracking state and location data
class _HomePageState extends State<HomePage> {
  bool _isTracking = false; // Tracks whether location polling is active
  Position? _currentPosition; // Stores the latest geolocation data
  String? _currentCity; // Stores the city name from reverse geocoding
  Timer? _timer; // Timer for periodic data collection
  final String _apiKey = 'c77677c5167fdf73fd2841880efc5299'; // OpenWeatherMap API key

  @override
  void initState() {
    super.initState();
    _requestPermissions(); // Request location and storage permissions on startup
  }

  /// Requests location and storage permissions from the user
  Future<void> _requestPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Location permission permanently denied. Please enable it in settings.')),
      );
      return;
    }
    await Permission.storage.request(); // Request storage permission
  }

  /// Toggles location tracking on or off
  Future<void> _toggleTracking() async {
    setState(() {
      _isTracking = !_isTracking; // Toggle tracking state
    });

    if (_isTracking) {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable GPS/Location services')),
        );
        setState(() {
          _isTracking = false; // Disable tracking if GPS is off
        });
        return;
      }

      // Start periodic data collection every 5 minutes
      _timer = Timer.periodic(const Duration(minutes: 5), (timer) async {
        await _collectData();
      });
      await _collectData(); // Collect data immediately
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracking started')),
      );
    } else {
      _timer?.cancel(); // Stop the timer
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracking stopped')),
      );
    }
  }

  /// Collects geolocation, pollution data, and city name
  Future<void> _collectData() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GPS is disabled. Please enable it.')),
        );
        return;
      }

      // Get high-accuracy location data
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10), // Timeout after 10 seconds
      );

      // Fetch PM10 pollution data
      double pm10 = await _fetchPollutionData(position.latitude, position.longitude);
      // Fetch city name via reverse geocoding
      String city = await _fetchCityName(position.latitude, position.longitude);

      setState(() {
        _currentPosition = position; // Update current position
        _currentCity = city; // Update current city
      });

      await _saveData(position, pm10); // Save data to file
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error collecting data: $e')),
      );
    }
  }

  /// Fetches PM10 pollution data from OpenWeatherMap API
  Future<double> _fetchPollutionData(double lat, double lon) async {
    final url =
        'http://api.openweathermap.org/data/2.5/air_pollution?lat=$lat&lon=$lon&appid=$_apiKey';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['list'][0]['components']['pm10'].toDouble();
    }
    return 0.0; // Return 0.0 on failure
  }

  /// Fetches city name from coordinates using OpenWeatherMap Geocoding API
  Future<String> _fetchCityName(double lat, double lon) async {
    final url =
        'http://api.openweathermap.org/geo/1.0/reverse?lat=$lat&lon=$lon&limit=1&appid=$_apiKey';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data.isNotEmpty) {
        return data[0]['name'] ?? 'Unknown'; // Return city name or 'Unknown'
      }
    }
    return 'Unknown';
  }

  /// Saves location and pollution data to a file
  Future<void> _saveData(Position position, double pm10) async {
    final now = DateTime.now();
    final dateStr = now.toString().split(' ')[0]; // Format: YYYY-MM-DD
    final timestamp = now.toString().split('.')[0]; // Format: YYYY-MM-DD HH:MM:SS
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory('${directory.path}/AirPollutionData');
    if (!await folder.exists()) {
      await folder.create(recursive: true); // Create folder if it doesn't exist
    }
    final file = File('${folder.path}/pollution_$dateStr.txt');
    // Data format: Datetime | Lat | Lon | Elv | Spd | PM10
    final dataLine =
        '$timestamp | ${position.latitude} | ${position.longitude} | ${position.altitude} | ${position.speed} | $pm10\n';
    await file.writeAsString(dataLine, mode: FileMode.append);
  }

  /// Navigates to the data table page
  void _navigateToDataTable() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DataTablePage()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel(); // Cancel timer to prevent memory leaks
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Air Pollution Tracker'), // Centered title
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0), // Add padding around content
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Button to start/stop tracking with icon
              ElevatedButton.icon(
                onPressed: _toggleTracking,
                icon: FaIcon(
                  _isTracking ? FontAwesomeIcons.stop : FontAwesomeIcons.play,
                  size: 20,
                ),
                label: Text(_isTracking ? 'Stop Tracking' : 'Start Tracking'),
              ),
              const SizedBox(height: 20), // Spacer
              // Button to view data table with icon
              ElevatedButton.icon(
                onPressed: _navigateToDataTable,
                icon: const FaIcon(FontAwesomeIcons.table, size: 20),
                label: const Text('View Data Table'),
              ),
              const SizedBox(height: 30), // Spacer
              // Card displaying location and city
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text(
                        _currentPosition == null
                            ? 'No location data'
                            : 'Lat: ${_currentPosition!.latitude}\nLon: ${_currentPosition!.longitude}',
                        style: const TextStyle(fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10), // Spacer
                      Text(
                        _currentCity == null
                            ? 'City: Unknown'
                            : 'City: $_currentCity',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget for displaying stored pollution data in a table
class DataTablePage extends StatefulWidget {
  const DataTablePage({super.key});

  @override
  _DataTablePageState createState() => _DataTablePageState();
}

/// State for DataTablePage, managing data loading and display
class _DataTablePageState extends State<DataTablePage> {
  List<Map<String, String>> _data = []; // Stores table data
  String? _selectedDate; // Currently selected date for data display

  @override
  void initState() {
    super.initState();
    _loadData(); // Load data on page initialization
  }

  /// Loads list of available data files (dates)
  Future<void> _loadData() async {
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory('${directory.path}/AirPollutionData');
    if (!await folder.exists()) {
      setState(() {
        _data = []; // No data if folder doesn't exist
      });
      return;
    }

    final files = folder.listSync().whereType<File>().toList();
    final dates = files
        .map((file) => file.path.split('pollution_').last.replaceAll('.txt', ''))
        .toList();

    if (dates.isNotEmpty) {
      _selectedDate = dates.first; // Select first date by default
      await _loadFileData(_selectedDate!); // Load data for selected date
    }

    setState(() {}); // Update UI
  }

  /// Loads data from a specific file for the given date
  Future<void> _loadFileData(String date) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/AirPollutionData/pollution_$date.txt');
    if (!await file.exists()) {
      setState(() {
        _data = []; // No data if file doesn't exist
      });
      return;
    }

    final lines = await file.readAsLines();
    final List<Map<String, String>> loadedData = [];
    for (var line in lines) {
      final parts = line.split(' | ');
      if (parts.length == 6) {
        // Parse data into map for table display
        loadedData.add({
          'Datetime': parts[0],
          'Lat': parts[1],
          'Lon': parts[2],
          'Elv': parts[3],
          'Spd': parts[4],
          'PM10': parts[5],
        });
      }
    }

    setState(() {
      _data = loadedData; // Update table data
    });
  }

  /// Shares the pollution data file for the selected date
  Future<void> _downloadData() async {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No date selected')),
      );
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/AirPollutionData/pollution_$_selectedDate.txt');
    if (!await file.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data file found for selected date')),
      );
      return;
    }

    // Share the file using share_plus
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Pollution data for $_selectedDate',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pollution Data')),
      body: Column(
        children: [
          // Dropdown to select date
          FutureBuilder<Directory>(
            future: getApplicationDocumentsDirectory(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final folder = Directory('${snapshot.data!.path}/AirPollutionData');
              if (!folder.existsSync()) {
                return const Center(child: Text('No data available'));
              }
              final files = folder.listSync().whereType<File>().toList();
              final dates = files
                  .map((file) =>
                  file.path.split('pollution_').last.replaceAll('.txt', ''))
                  .toList();

              if (dates.isEmpty) {
                return const Center(child: Text('No data available'));
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    DropdownButton<String>(
                      value: _selectedDate ?? dates.first,
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedDate = newValue; // Update selected date
                          });
                          _loadFileData(newValue); // Load data for new date
                        }
                      },
                      items: dates.map<DropdownMenuItem<String>>((String date) {
                        return DropdownMenuItem<String>(
                          value: date,
                          child: Text(date),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10), // Spacer
                    // Button to download data file
                    ElevatedButton.icon(
                      onPressed: _downloadData,
                      icon: const FaIcon(FontAwesomeIcons.download, size: 20),
                      label: const Text('Download Data'),
                    ),
                  ],
                ),
              );
            },
          ),
          // Table displaying pollution data
          Expanded(
            child: _data.isEmpty
                ? const Center(child: Text('No data for selected date'))
                : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Datetime')),
                    DataColumn(label: Text('Lat')),
                    DataColumn(label: Text('Lon')),
                    DataColumn(label: Text('Elv')),
                    DataColumn(label: Text('Spd')),
                    DataColumn(label: Text('PM10')),
                  ],
                  rows: _data.map((row) {
                    return DataRow(cells: [
                      DataCell(Text(row['Datetime']!)),
                      DataCell(Text(row['Lat']!)),
                      DataCell(Text(row['Lon']!)),
                      DataCell(Text(row['Elv']!)),
                      DataCell(Text(row['Spd']!)),
                      DataCell(Text(row['PM10']!)),
                    ]);
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
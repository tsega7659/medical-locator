import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:clipboard/clipboard.dart';

class HospitalLocation extends StatefulWidget {
  final List<String> testNames;

  const HospitalLocation({super.key, required this.testNames});

  @override
  _HospitalLocationState createState() => _HospitalLocationState();
}

class _HospitalLocationState extends State<HospitalLocation> {
  bool _locationPermissionGranted = false;
  final Logger _logger = Logger();
  bool _isLoading = false;
  List<dynamic> hospitals = [];
  bool _noHospitalsFound = false;
  bool _hasAttemptedFetch = false; // Track if fetch has been attempted

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    final status = await Permission.location.status;

    setState(() {
      if (status.isGranted) {
        _locationPermissionGranted = true;
      } else if (status.isPermanentlyDenied) {
        _showSettingsDialog();
        _locationPermissionGranted = false;
      } else {
        _locationPermissionGranted = false;
      }
    });

    // Fetch hospitals regardless of permission status
    if (mounted) {
      _fetchHospitals();
    }
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    setState(() {
      if (status.isGranted) {
        _locationPermissionGranted = true;
      } else if (status.isPermanentlyDenied) {
        _showSettingsDialog();
        _locationPermissionGranted = false;
      } else {
        _locationPermissionGranted = false;
      }
    });

    // Fetch hospitals after permission state is updated
    if (mounted) {
      _fetchHospitals();
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Location permission is permanently denied. Please enable it from app settings to use your current location.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchHospitals() async {
    if (!mounted || widget.testNames.isEmpty) return;

    setState(() {
      _isLoading = true;
      _noHospitalsFound = false;
      hospitals = [];
      _hasAttemptedFetch = true; // Mark that we've attempted to fetch
    });

    try {
      double userLat = 9.0300; // Default to Addis Ababa coordinates
      double userLon = 38.7400;

      if (_locationPermissionGranted) {
        try {
          final location = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          userLat = location.latitude;
          userLon = location.longitude;
          _logger.i('Using user location: ($userLat, $userLon)');
        } catch (e) {
          _logger.w('Failed to get user location: $e');
          _logger.i('Falling back to default coordinates (Addis Ababa): ($userLat, $userLon)');
        }
      } else {
        _logger.i(
          'Location permission not granted, using default coordinates (Addis Ababa): ($userLat, $userLon)',
        );
      }

      final testsQuery = widget.testNames.join(',');
      _logger.i(
        'API query: test=$testsQuery, userLat=$userLat, userLon=$userLon',
      );

      final url =
          'https://medical-test-locator-1-zbbq.onrender.com/api/v1/institution/searchByTest?test=$testsQuery&userLat=$userLat&userLon=$userLon';

      final dio = Dio();
      final response = await dio.get(
        url,
        options: Options(headers: {'Accept': 'application/json'}),
      );

      _logger.i('API response status: ${response.statusCode}');
      _logger.i('API response data: ${response.data}');

      if (response.statusCode == 200) {
        final responseData = response.data;
        if (responseData is Map<String, dynamic> &&
            responseData.containsKey('institutions')) {
          final institutions = responseData['institutions'];
          if (institutions is List) {
            _logger.i('Found ${institutions.length} hospitals');
            setState(() {
              hospitals = institutions;
              _noHospitalsFound = institutions.isEmpty;
            });
            if (institutions.isEmpty && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'No hospitals found for "${widget.testNames.join(', ')}" near this location.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          } else {
            _logger.w('Institutions field is not a list: $institutions');
            setState(() {
              hospitals = [];
              _noHospitalsFound = true;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Invalid response from server: Institutions field is not a list.',
                  ),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        } else {
          _logger.w('Invalid response format: $responseData');
          setState(() {
            hospitals = [];
            _noHospitalsFound = true;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Invalid response format from server.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        throw Exception(
          response.data['message'] ?? 'Failed to fetch hospitals',
        );
      }
    } on DioException catch (e) {
      _logger.e('Dio error fetching hospitals: ${e.message}');
      _logger.e('Fetch hospitals response: ${e.response?.data}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.response?.data['message'] ??
                  'Network error fetching hospitals: ${e.message}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      setState(() {
        hospitals = [];
        _noHospitalsFound = true;
      });
    } catch (e) {
      _logger.e('Error fetching hospitals', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching hospitals: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      setState(() {
        hospitals = [];
        _noHospitalsFound = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('images/L.png', width: 50, height: 50),
            const SizedBox(width: 8),
            Text(
              'MediMap',
              style: GoogleFonts.poppins(
                color: const Color(0xFF00796B),
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : hospitals.isNotEmpty
                    ? ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: hospitals.length,
                        itemBuilder: (context, index) {
                          final center = hospitals[index];
                          if (center is! Map<String, dynamic>) {
                            return const SizedBox.shrink();
                          }
                          return _DiagnosticCenterCard(
                            center: center,
                            testNames: widget.testNames,
                          );
                        },
                      )
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            _hasAttemptedFetch
                                ? _noHospitalsFound
                                    ? 'No hospitals found for "${widget.testNames.join(', ')}" near this location.'
                                    : 'No hospitals available.'
                                : 'Loading hospitals...',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              color: Colors.orange,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticCenterCard extends StatelessWidget {
  final Map<String, dynamic> center;
  final List<String> testNames;

  const _DiagnosticCenterCard({required this.center, required this.testNames});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Stack(
          children: [
            if ((center['credentials'] != null &&
                    center['credentials'].isNotEmpty &&
                    center['credentials'][0] == 'ISO Certified') ||
                center['certified'] == true)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    'ISO Certified',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: Center(
                      child: center['image'] != null
                          ? Image.network(
                              center['image'],
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                width: 70,
                                height: 70,
                                color: const Color(0xFF00796B),
                                child: const Center(
                                  child: Icon(
                                    Icons.local_hospital,
                                    size: 40,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              width: 70,
                              height: 70,
                              color: const Color(0xFF00796B),
                              child: const Center(
                                child: Icon(
                                  Icons.local_hospital,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          center['name'] ?? 'Unknown Hospital',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF00796B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.local_hospital,
                              color: Colors.black87,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                center['serviceType'] ?? 'Unknown Service',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.black87,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  final mapLink = center['location'];
                                  if (mapLink != null && mapLink.isNotEmpty) {
                                    if (await canLaunchUrl(
                                      Uri.parse(mapLink),
                                    )) {
                                      await launchUrl(
                                        Uri.parse(mapLink),
                                        mode: LaunchMode.externalApplication,
                                      );
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Could not open map link',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: Text(
                                  'Location',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.grey.shade800,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.phone,
                              color: Colors.black87,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  final phoneNumbers =
                                      center['contactInfo'] != null &&
                                              center['contactInfo']['phone'] !=
                                                  null
                                          ? (center['contactInfo']['phone']
                                                  as List?)
                                              ?.map((phone) => phone
                                                      .startsWith('+251')
                                                  ? phone
                                                  : '+251 $phone')
                                              .join(', ') ??
                                              'No Phone Provided'
                                          : 'No Phone Provided';

                                  if (phoneNumbers != 'No Phone Provided') {
                                    final phoneNumber =
                                        phoneNumbers.split(', ')[0];
                                    final phoneUri = Uri.parse(
                                      'tel:$phoneNumber',
                                    );
                                    if (await canLaunchUrl(phoneUri)) {
                                      await launchUrl(phoneUri);
                                    } else {
                                      await FlutterClipboard.copy(
                                          phoneNumbers);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Phone number copied to clipboard',
                                          ),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  }
                                },
                                child: Text(
                                  center['contactInfo'] != null &&
                                          center['contactInfo']['phone'] != null
                                      ? (center['contactInfo']['phone']
                                              as List?)
                                          ?.map((phone) =>
                                              phone.startsWith('+251')
                                                  ? phone
                                                  : '+251 $phone')
                                          .join(', ') ??
                                          'No Phone Provided'
                                      : 'No Phone Provided',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.black54,
                                    decoration: center['contactInfo'] != null &&
                                            center['contactInfo']['phone'] !=
                                                null &&
                                            (center['contactInfo']['phone']
                                                    as List?)
                                                ?.isNotEmpty ==
                                                true
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () async {
                            final url = center['website'];
                            if (url != null && url.isNotEmpty) {
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(
                                  Uri.parse(url),
                                  mode: LaunchMode.externalApplication,
                                );
                              } else {
                                await FlutterClipboard.copy(url);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'URL copied to clipboard.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          child: Row(
                            children: [
                              const Icon(
                                Icons.language,
                                color: Colors.black87,
                                size: 20,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  center['website'] ?? 'No Website',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    color: Colors.black54,
                                    decoration: TextDecoration.underline,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.access_time,
                              color: Colors.black87,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                "Working Hours: ${center['serviceHours'] ?? 'Working Hours Not Available'}",
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                        ..._buildTestDurationSection(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTestDurationSection(BuildContext context) {
    final testWidgets = _buildTestList(context);
    if (testWidgets.isEmpty) {
      return [];
    }

    return [
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.timer, color: Colors.black87, size: 20),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Test Duration:',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                ...testWidgets,
              ],
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildTestList(BuildContext context) {
    final List<dynamic>? tests = center['tests'] as List<dynamic>?;
    if (tests == null || tests.isEmpty) {
      return [];
    }

    final filteredTests = tests.where((test) {
      return testNames.contains(test['name']);
    }).toList();

    if (filteredTests.isEmpty) {
      return [];
    }

    return filteredTests.map((test) {
      if (test['turnaroundTime'] == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          ' ${test['turnaroundTime']?.toString() ?? 'N/A'}',
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
        ),
      );
    }).toList();
  }
}
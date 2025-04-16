import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:my_medical_app/screens/locations/hospital_location.dart';
import 'package:my_medical_app/uplaod/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  XFile? imagePicked;
  bool _isLoading = false;
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _carouselTimer;
  final Logger _logger = Logger();
  List<dynamic>? _hospitals;
  List<dynamic>? _extractedTests;
  bool _showLocationPrompt = false;
  bool _locationPermissionGranted = false;
  bool _noTestsFound = false;
  bool _noHospitalsFound = false;

  @override
  void initState() {
    super.initState();
    _startAutoSlide();
    _checkLocationPermission();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _carouselTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    final status = await Permission.location.status;
    
    if (status.isDenied) {
      setState(() {
        _showLocationPrompt = true;
        _locationPermissionGranted = false;
      });
    } else if (status.isPermanentlyDenied) {
      _showSettingsDialog();
      setState(() {
        _showLocationPrompt = false;
        _locationPermissionGranted = false;
      });
    } else if (status.isGranted) {
      setState(() {
        _showLocationPrompt = false;
        _locationPermissionGranted = true;
      });
    }
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      setState(() {
        _showLocationPrompt = false;
        _locationPermissionGranted = true;
      });
    } else if (status.isPermanentlyDenied) {
      _showSettingsDialog();
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
            'Location permission is permanently denied. Please enable it from app settings.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _startAutoSlide() {
    _carouselTimer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (_currentPage < 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<List<dynamic>?> _sendImageToApi(File file) async {
    if (!mounted) return null;

    setState(() {
      _isLoading = true;
      _noTestsFound = false;
      _noHospitalsFound = false;
      _hospitals = null;
      _extractedTests = null;
    });

    try {
      if (!await file.exists()) {
        throw Exception('File does not exist');
      }

      if (await file.length() == 0) {
        throw Exception('File is empty');
      }

      final fileExtension = file.path.split('.').last.toLowerCase();
      final mimeType = lookupMimeType(file.path);

      _logger.i('Detected MIME type: $mimeType');
      _logger.i('File extension: $fileExtension');

      if (mimeType == null || !(mimeType.startsWith('image/') || mimeType == 'application/pdf')) {
        throw Exception('Unsupported file type. Only images and PDFs are allowed.');
      }

      final dio = Dio();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: 'upload_${DateTime.now().millisecondsSinceEpoch}.$fileExtension',
          contentType: MediaType.parse(mimeType),
        ),
      });

      final options = Options(
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'multipart/form-data',
        },
        validateStatus: (status) => status != null && status < 500,
      );

      _logger.i('Attempting upload with file: ${file.path}');
      _logger.i('File size: ${(await file.length() / 1024).toStringAsFixed(2)} KB');

      final response = await dio.post(
        'https://mtl-dez3.onrender.com/api/v1/ocr/upload',
        data: formData,
        options: options,
      );

      _logger.i('Response status: ${response.statusCode}');
      _logger.i('Response data: ${response.data}');

      if ([200, 201, 204].contains(response.statusCode)) {
        final responseData = response.data;
        
        List<dynamic> extractedTests = [];
        if (responseData is Map<String, dynamic>) {
          if (responseData.containsKey('uploaded')) {
            final uploaded = responseData['uploaded'];
            if (uploaded is Map<String, dynamic> && uploaded.containsKey('tests')) {
              final tests = uploaded['tests'];
              if (tests is List) {
                extractedTests = tests;
              }
            }
          }
        }

        if (extractedTests.isEmpty) {
          setState(() => _noTestsFound = true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No medical tests found in the document'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return null;
        }

        _logger.i('Extracted tests: $extractedTests');
        
        final hospitals = await _fetchHospitals(extractedTests);
        _logger.i('Fetched hospitals: $hospitals');
        
        if (hospitals != null && hospitals.isNotEmpty) {
          setState(() {
            _hospitals = hospitals;
            _extractedTests = extractedTests;
            _noTestsFound = false;
            _noHospitalsFound = false;
          });
        } else {
          setState(() {
            _noHospitalsFound = true;
            _extractedTests = extractedTests;
            _noTestsFound = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No hospitals found for these tests'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }

        if (mounted && !_noTestsFound && !_noHospitalsFound) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upload successful!'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return extractedTests;
      } else {
        throw Exception(response.data['message'] ?? 'Upload failed');
      }
    } on DioException catch (e) {
      _logger.e('Dio error: ${e.message}');
      _logger.e('Response: ${e.response?.data}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.response?.data['message'] ?? 'Network error: ${e.message}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e, stack) {
      _logger.e('Upload error', error: e, stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
    return null;
  }

  Future<List<dynamic>?> _fetchHospitals(List<dynamic> extractedTests) async {
    if (!mounted || extractedTests.isEmpty) return null;

    if (!_locationPermissionGranted) {
      await _checkLocationPermission();
      if (!_locationPermissionGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required to find nearby hospitals'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }
    }

    setState(() => _isLoading = true);
    _logger.i('Fetching hospitals with tests: $extractedTests');

    try {
      final location = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final double userLat = location.latitude;
      final double userLon = location.longitude;
      final testsQuery = extractedTests.join(',');
      _logger.i('Fetching hospitals with: $testsQuery');

      final url =
          'https://mtl-dez3.onrender.com/api/v1/institution/searchByTest?test=$testsQuery&userLat=$userLat&userLon=$userLon';

      final dio = Dio();
      final response = await dio.get(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer <your_token>',
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final responseData = response.data;
        _logger.i('Response data: $responseData');
        if (responseData is Map<String, dynamic> && responseData.containsKey('institutions')) {
          final institutions = responseData['institutions'];
          if (institutions is List) {
            return institutions;
          }
        }
        throw Exception('Invalid hospitals data format');
      } else {
        throw Exception(response.data['message'] ?? 'Failed to fetch hospitals');
      }
    } catch (e) {
      _logger.e('Error fetching hospitals', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching hospitals: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
    return null;
  }

  Future<void> _searchHospitals(String query) async {
    if (!mounted || query.isEmpty) return;

    if (!_locationPermissionGranted) {
      await _checkLocationPermission();
      if (!_locationPermissionGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required to find nearby hospitals'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _hospitals = null;
      _extractedTests = null;
      _noHospitalsFound = false;
      imagePicked = null;
    });

    try {
      final location = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final double userLat = location.latitude;
      final double userLon = location.longitude;
      final testsQuery = query;
      _logger.i('Searching hospitals with: $testsQuery');

      final url =
          'https://mtl-dez3.onrender.com/api/v1/institution/searchByTest?test=$testsQuery&userLat=$userLat&userLon=$userLon';

      final dio = Dio();
      final response = await dio.get(
        url,
        options: Options(
          headers: {
            'Authorization': 'Bearer <your_token>',
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final responseData = response.data;
        _logger.i('Response data: $responseData');
        if (responseData is Map<String, dynamic> && responseData.containsKey('institutions')) {
          final institutions = responseData['institutions'];
          if (institutions is List) {
            setState(() {
              _hospitals = institutions;
              _extractedTests = [query];
              _noTestsFound = false;
              _noHospitalsFound = institutions.isEmpty;
            });
            if (institutions.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Search successful!'),
                  duration: Duration(seconds: 2),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No hospitals found for this test'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        }
      } else {
        throw Exception(response.data['message'] ?? 'Failed to fetch hospitals');
      }
    } catch (e) {
      _logger.e('Error searching hospitals', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error searching hospitals: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() {
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
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.grey[200],
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Medical Test Locator',
          style: TextStyle(
            color: Colors.teal,
            fontWeight: FontWeight.bold,
            fontSize: 25,
          ),
        ),
      ),
      body: Column(
        children: [
          if (_showLocationPrompt)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.teal[50],
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.teal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Enable location to find nearby medical centers',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _requestLocationPermission,
                    child: Text(
                      'Enable',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      Positioned.fill(
                        top: 50,
                        child: Image.asset(
                          'images/L.png',
                          width: 250,
                          height: 250,
                        ),
                      ),
                      Column(
                        children: [
                          const SizedBox(height: 60),
                          Text(
                            'Find Nearby Medical Test Centers Easily',
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF00796B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Search for medical tests or scan your request paper',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.normal,
                              color: Colors.black54,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 5,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    prefixIcon: GestureDetector(
                                      onTap: () {
                                        if (_searchController.text.isNotEmpty) {
                                          _searchHospitals(_searchController.text.trim());
                                        }
                                      },
                                      child: const Icon(Icons.search, color: Colors.grey),
                                    ),
                                    hintText: "Search here",
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                  onSubmitted: (value) {
                                    if (value.isNotEmpty) {
                                      _searchHospitals(value.trim());
                                    }
                                  },
                                ),
                                if (_isLoading)
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: SpinKitSpinningLines(
                                      color: const Color(0xFF00796B),
                                      size: 50,
                                    ),
                                  ),
                                if (_extractedTests != null && _extractedTests!.isNotEmpty && !_isLoading)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Wrap(
                                      spacing: 8,
                                      children: _extractedTests!.map((test) {
                                        return GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => HospitalLocation(
                                                  testNames: [test.toString()],
                                                ),
                                              ),
                                            );
                                          },
                                          child: Chip(
                                            label: Text(
                                              "See more ${test.toString()} Test Areas",
                                              style: GoogleFonts.poppins(
                                                fontSize: 14,
                                                color: Colors.white,
                                              ),
                                            ),
                                            backgroundColor: Colors.teal,
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                if (_hospitals != null && _hospitals!.isNotEmpty && !_isLoading)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: _hospitals!.map((hospital) {
                                        return Card(
                                          margin: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: 5,
                                          shadowColor: Colors.black26,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black12.withOpacity(0.1),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 5),
                                                ),
                                              ],
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(16.0),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    hospital['name'] ?? 'Unknown Hospital',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.bold,
                                                      color: const Color(0xFF00796B),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  if (hospital['location'] != null)
                                                    GestureDetector(
                                                      onTap: () async {
                                                        final url = hospital['location'];
                                                        if (await canLaunchUrl(Uri.parse(url))) {
                                                          await launchUrl(Uri.parse(url));
                                                        }
                                                      },
                                                      child: Row(
                                                        children: [
                                                          Icon(Icons.location_on, color: Colors.black87, size: 20),
                                                          const SizedBox(width: 10),
                                                          Text(
                                                            'Here',
                                                            style: GoogleFonts.poppins(
                                                              fontSize: 14,
                                                              color: Colors.black54,
                                                              decoration: TextDecoration.underline,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  const SizedBox(height: 3),
                                                  if (hospital['website'] != null)
                                                    GestureDetector(
                                                      onTap: () async {
                                                        final website = hospital['website'];
                                                        if (website is String && Uri.tryParse(website)?.hasAbsolutePath == true) {
                                                          final url = Uri.parse(website);
                                                          if (await canLaunchUrl(url)) {
                                                            await launchUrl(
                                                              url,
                                                              mode: LaunchMode.externalApplication,
                                                            );
                                                          } else {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              const SnackBar(
                                                                content: Text('Could not launch website'),
                                                              ),
                                                            );
                                                          }
                                                        } else {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            const SnackBar(
                                                              content: Text('Invalid website URL'),
                                                            ),
                                                          );
                                                        }
                                                      },
                                                      child: Row(
                                                        children: [
                                                          const Icon(Icons.public, color: Colors.black87, size: 20),
                                                          const SizedBox(width: 10),
                                                          Expanded(
                                                            child: Text(
                                                              hospital['website'],
                                                              style: GoogleFonts.poppins(
                                                                fontSize: 14,
                                                                decoration: TextDecoration.underline,
                                                                color: Colors.black54,
                                                              ),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  const SizedBox(height: 3),
                                                  if (hospital['contactInfo'] != null)
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.phone, color: Colors.black87, size: 20),
                                                        const SizedBox(width: 10),
                                                        Expanded(
                                                          child: Text(
                                                            (hospital['contactInfo']['phone'] as List?)?.join(', ') ?? 'No phone available',
                                                            style: GoogleFonts.poppins(
                                                              fontSize: 14,
                                                              color: Colors.black54,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  const SizedBox(height: 3),
                                                  Row(
                                                    children: [
                                                      const Icon(Icons.timer, color: Colors.black87, size: 20),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Text(
                                                          'Turnaround Time: ${hospital['turnaroundTime'] ?? 'Not specified'}',
                                                          style: GoogleFonts.poppins(
                                                            fontSize: 14,
                                                            color: Colors.black54,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                if (_noHospitalsFound && !_isLoading)
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Text(
                                      'No hospitals found for this test',
                                      style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildActionButton(
                                Icons.file_upload,
                                "Upload Image",
                                () async {
                                  final picked = await MyImagePicker().pickFromGallery();
                                  if (picked != null) {
                                    setState(() {
                                      imagePicked = picked;
                                      _hospitals = null;
                                      _extractedTests = null;
                                      _noHospitalsFound = false;
                                    });
                                    await _sendImageToApi(File(picked.path));
                                  }
                                },
                              ),
                              const SizedBox(width: 15),
                              _buildActionButton(
                                Icons.document_scanner,
                                "Scan Image",
                                () async {
                                  final picked = await MyImagePicker().pickFromCamera();
                                  if (picked != null) {
                                    setState(() {
                                      imagePicked = picked;
                                      _hospitals = null;
                                      _extractedTests = null;
                                      _noHospitalsFound = false;
                                    });
                                    await _sendImageToApi(File(picked.path));
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 25),
                        ],
                      ),
                    ],
                  ),
                  imagePicked == null
                      ? Column(
                          children: [
                            SizedBox(
                              height: 120,
                              child: PageView.builder(
                                controller: _pageController,
                                onPageChanged: (int page) {
                                  setState(() => _currentPage = page);
                                },
                                itemCount: 2,
                                itemBuilder: (context, index) {
                                  List<String> images = [
                                    'images/L.jpeg',
                                    'images/M.jpeg',
                                  ];
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.asset(
                                        images[index],
                                        width: MediaQuery.of(context).size.width * 0.9,
                                        height: 120,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(2, (index) {
                                return Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _currentPage == index
                                        ? const Color(0xFF00796B)
                                        : Colors.grey.withOpacity(0.4),
                                  ),
                                );
                              }),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            const SizedBox(height: 20),
                            Text(
                              _isLoading
                                  ? "Uploading Image..."
                                  : _noTestsFound
                                      ? "No tests found in document"
                                      : "Image Uploaded Successfully",
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: _noTestsFound ? Colors.red : const Color(0xFF00796B),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_isLoading)
                              SpinKitSpinningLines(
                                color: const Color(0xFF00796B),
                                size: 50,
                              )
                            else
                              Container(
                                height: 320,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  image: DecorationImage(
                                    image: FileImage(File(imagePicked!.path)),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                          ],
                        ),
                  const SizedBox(height: 25),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Most Searched",
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00796B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 4,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 3,
                      crossAxisSpacing: 15,
                      mainAxisSpacing: 15,
                    ),
                    itemBuilder: (context, index) {
                      List<Map<String, dynamic>> tests = [
                        {"title": "X-Ray", "icon": Icons.medical_services},
                        {"title": "CT-Scan", "icon": Icons.scanner},
                        {"title": "MRI", "icon": Icons.medical_services},
                        {"title": "Blood Test", "icon": Icons.bloodtype},
                      ];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HospitalLocation(testNames: [tests[index]["title"]]),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12.withOpacity(0.1),
                                blurRadius: 5,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                tests[index]["icon"],
                                color: Color(0xFF00796B),
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                tests[index]["title"],
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return ElevatedButton.icon(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all<Color>(Colors.black),
        foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
        padding: WidgetStateProperty.all<EdgeInsetsGeometry>(
          const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        ),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade800),
          ),
        ),
        elevation: WidgetStateProperty.all<double>(5),
        shadowColor: WidgetStateProperty.all<Color>(Colors.black54),
      ),
      icon: Icon(icon, size: 16, color: Colors.white),
      label: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      onPressed: onTap,
    );
  }
}
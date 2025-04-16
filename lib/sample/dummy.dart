import 'package:flutter/material.dart';

IconData _getIcon(String iconName) {
  switch (iconName) {
    case "scanner":
      return Icons.scanner;
    case "broken_image":
      return Icons.broken_image;
    case "bloodtype":
      return Icons.bloodtype;
    case "monitor_heart":
      return Icons.monitor_heart;
    default:
      return Icons.medical_services;
  }
}

List<Map<String, dynamic>> testCenters = [
  {"name": "MRI", "icon": _getIcon("scanner"), "color": Colors.blue},
  {"name": "X-Ray", "icon": _getIcon("broken_image"), "color": Colors.green},
  {"name": "Blood Test", "icon": _getIcon("bloodtype"), "color": Colors.red},
  {
    "name": "Ultrasound",
    "icon": _getIcon("monitor_heart"),
    "color": Colors.purple
  },
];

// Dummy data for most visited hospitals
List<Map<String, dynamic>> mostVisitedHospitals = [
  {
    'name': 'Pawlos Hospital',
    'address': '123 Main St',
    'phone': '123-456-7890',
    'website': 'www.pawlos.com',
    'description': 'A leading hospital in the city.',
    'rating': 4.5,
  },
  {
    'name': 'Tikur Anbesa Hospital',
    'address': '456 Elm St',
    'phone': '987-654-3210',
    'website': 'www.tikuranbesa.com',
    'description': 'Providing quality healthcare for over 50 years.',
    'rating': 4.0,
  },
];

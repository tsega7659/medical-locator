import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:developer' as dev;

// import 'package:medical_test_allocator/service/api_service.dart';
import 'package:my_medical_app/service/api_service.dart';


class APIScreen extends StatelessWidget {
  final ApiService apiService = ApiService();

  APIScreen({super.key});

  Future<void> fetchData() async {
    Response response = await apiService.getRequest('/posts/1');
    dev.log(response.data);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Dio API Service Example')),
        body: Center(
          child: ElevatedButton(
            onPressed: fetchData,
            child: Text('Fetch Data'),
          ),
        ),
      ),
    );
  }
}

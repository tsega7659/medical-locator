import 'package:dio/dio.dart';

class ApiService {
  late Dio _dio;

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'https://jsonplaceholder.typicode.com',
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
  }

  /// GET request
  Future<Response> getRequest(String endpoint, {Map<String, dynamic>? params}) async {
    try {
      Response response = await _dio.get(endpoint, queryParameters: params);
      return response;
    } catch (e) {
      return handleError(e);
    }
  }

  /// POST request
  Future<Response> postRequest(String endpoint, Map<String, dynamic> data) async {
    try {
      Response response = await _dio.post(endpoint, data: data);
      return response;
    } catch (e) {
      return handleError(e);
    }
  }

  /// PUT request
  Future<Response> putRequest(String endpoint, Map<String, dynamic> data) async {
    try {
      Response response = await _dio.put(endpoint, data: data);
      return response;
    } catch (e) {
      return handleError(e);
    }
  }

  /// DELETE request
  Future<Response> deleteRequest(String endpoint) async {
    try {
      Response response = await _dio.delete(endpoint);
      return response;
    } catch (e) {
      return handleError(e);
    }
  }

  /// File Upload
  Future<Response> uploadFile(String endpoint, String filePath) async {
    try {
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });

      Response response = await _dio.post(endpoint, data: formData);
      return response;
    } catch (e) {
      return handleError(e);
    }
  }

  /// Error handling
  Response handleError(dynamic e) {
    if (e is DioException) {
      return Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: e.response?.statusCode ?? 500,
        statusMessage: e.response?.statusMessage ?? 'Unknown Error',
        data: e.response?.data ?? {'message': 'Something went wrong'},
      );
    } else {
      return Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 500,
        statusMessage: 'Unknown Error',
        data: {'message': 'Unexpected error occurred'},
      );
    }
  }
}

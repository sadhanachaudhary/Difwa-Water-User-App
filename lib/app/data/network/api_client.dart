import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/api_config.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import '../../../core/api/auth_interceptor.dart';
import '../../../core/api/api_provider.dart'; // Added for storageServiceProvider
import '../../../core/storage/secure_storage_service.dart';
import '../../../../main.dart'; // To access rootScaffoldMessengerKey

/// Thrown when the server returns a non-2xx status or an error occurs.
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException({required this.message, this.statusCode});

  @override
  String toString() {
    if (statusCode != null) {
      return 'ApiException($statusCode): $message';
    }
    return 'ApiException: $message';
  }
}

/// Provider for ApiClient - The single source of truth for Dio configuration
final apiClientProvider = Provider<ApiClient>((ref) {
  final rawBaseUrl = ApiConfig.baseUrl;

  // Normalize base URL: ensure it doesn't have a trailing slash
  final normalizedBaseUrl = rawBaseUrl.endsWith('/')
      ? rawBaseUrl.substring(0, rawBaseUrl.length - 1)
      : rawBaseUrl;

  final dio = Dio(BaseOptions(
    baseUrl: normalizedBaseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    contentType: Headers.jsonContentType,
  ));

  // Inject storage service directly from Riverpod
  final storage = ref.watch(storageServiceProvider);

  dio.interceptors.addAll([
    AuthInterceptor(dio, storage),
    // PrettyDioLogger only runs in debug mode — never in APKs shared externally
    if (kDebugMode)
      PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        responseHeader: false,
        error: true,
        compact: true,
        maxWidth: 90,
      ),
  ]);

  return ApiClient(dio);
});

class ApiClient {
  // ── Module Base Paths ──────────────────────────────────────────────────
  static const String baseUrl = '/app';
  static const String riderBaseUrl = '/rider';
  static const String otpBaseUrl = '/otp';
  static const String walletBaseUrl = '/wallet';
  static const String paymentBaseUrl = '/payment';
  static const String subscriptionBaseUrl = '/subscription';
  static const String reviewBaseUrl = '/reviews';

  final Dio _dio;

  ApiClient(this._dio);

  /// Standard factory for non-DI contexts (like static services).
  /// Strictly follows the rule: only the ApiClient class knows how its Dio should be configured.
  factory ApiClient.createDefault() {
    final rawBaseUrl = ApiConfig.baseUrl;
    final normalizedBaseUrl = rawBaseUrl.endsWith('/')
        ? rawBaseUrl.substring(0, rawBaseUrl.length - 1)
        : rawBaseUrl;

    final dio = Dio(BaseOptions(
      baseUrl: normalizedBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
    ));

    final storage = SecureStorageService();
    dio.interceptors.addAll([
      AuthInterceptor(dio, storage),
    ]);

    return ApiClient(dio);
  }

  // ── Helper to ensure leading slash ──────────────────────────────────────
  String _normalizePath(String path) => path.startsWith('/') ? path : '/$path';

  // ── HTTP Methods ────────────────────────────────────────────────────────

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
  }) async {
    try {
      final response = await _dio.get(
        _normalizePath(path),
        queryParameters: queryParameters,
        options: Options(extra: {'requiresAuth': requiresAuth}),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> post(
    String path, {
    dynamic data,
    bool requiresAuth = false,
  }) async {
    try {
      final response = await _dio.post(
        _normalizePath(path),
        data: data,
        options: Options(extra: {'requiresAuth': requiresAuth}),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> put(
    String path, {
    dynamic data,
    bool requiresAuth = false,
  }) async {
    try {
      final response = await _dio.put(
        _normalizePath(path),
        data: data,
        options: Options(extra: {'requiresAuth': requiresAuth}),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> patch(
    String path, {
    dynamic data,
    bool requiresAuth = false,
  }) async {
    try {
      final response = await _dio.patch(
        _normalizePath(path),
        data: data,
        options: Options(extra: {'requiresAuth': requiresAuth}),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  Future<dynamic> delete(
    String path, {
    dynamic data,
    bool requiresAuth = false,
  }) async {
    try {
      final response = await _dio.delete(
        _normalizePath(path),
        data: data,
        options: Options(extra: {'requiresAuth': requiresAuth}),
      );
      return response.data;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  ApiException _handleError(DioException e) {
    // 1. Handle Timeouts and Connection Errors
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      
      final String errorMsg = e.type == DioExceptionType.connectionError 
          ? 'Cannot connect to server. Please ensure the server is running.'
          : 'Connection timed out. Please check your internet connection.';

      return ApiException(message: errorMsg);
    }

    // 2. Handle Response Errors
    if (e.response != null) {
      final data = e.response?.data;
      String message = 'An unexpected server error occurred.';

      if (data is Map) {
        // Extract message from common keys
        message =
            data['message']?.toString() ?? data['error']?.toString() ?? message;
      } else if (data is String && data.isNotEmpty && !data.contains('<html')) {
        message = data;
      }

      return ApiException(statusCode: e.response?.statusCode, message: message);
    }

    // 3. Handle Other Errors (Network, etc.)
    return ApiException(
        message: e.message ?? 'A network error occurred. Please try again.');
  }

  // ── Helper static methods for token access ──────────────────────────────
  static Future<String?> getToken() async =>
      await SecureStorageService().getAccessToken();

  static Future<void> saveToken(String token) async {
    final storage = SecureStorageService();
    final refresh = await storage.getRefreshToken();
    await storage.saveTokens(access: token, refresh: refresh ?? '');
  }

  static Future<void> clearToken() async =>
      await SecureStorageService().clearAll();
}

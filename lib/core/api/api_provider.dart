import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_interceptor.dart';
import '../storage/secure_storage_service.dart';
import '../../app/core/config/api_config.dart';

final storageServiceProvider = Provider((ref) => SecureStorageService());

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  final storage = ref.watch(storageServiceProvider);
  dio.interceptors.addAll([
    AuthInterceptor(dio, storage),
    LogInterceptor(requestBody: true, responseBody: true), // For debugging
  ]);

  return dio;
});

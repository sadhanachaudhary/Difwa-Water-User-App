import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/api_config.dart';
import '../network/api_client.dart';

class RiderService {
  final ApiClient _apiClient;

  RiderService(this._apiClient);

  Future<List<dynamic>> getAssignedOrders() async {
    try {
      final response = await _apiClient.get(
        '${ApiClient.riderBaseUrl}/orders',
        requiresAuth: true,
      );
      return response['data'] ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> respondToOrder({
    required String orderId,
    required String response, // 'Accepted' or 'Rejected'
  }) async {
    try {
      final res = await _apiClient.patch(
        '${ApiClient.riderBaseUrl}/order-response',
        data: {
          'orderId': orderId,
          'response': response,
        },
        requiresAuth: true,
      );

      // Notify socket server if accepted
      if (res['success'] != false && response == 'Accepted') {
        _notifySocketServer(orderId, 'accepted');
      }

      return res;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> updateLocation({
    required double lat,
    required double lng,
  }) async {
    try {
      final res = await _apiClient.patch(
        '${ApiClient.riderBaseUrl}/location',
        data: {
          'latitude': lat,
          'longitude': lng,
        },
        requiresAuth: true,
      );
      return res;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> updateDeliveryStatus({
    required String orderId,
    required String status,
  }) async {
    try {
      final res = await _apiClient.patch(
        '${ApiClient.riderBaseUrl}/status',
        data: {
          'orderId': orderId,
          'status': status,
        },
        requiresAuth: true,
      );

      // Notify socket server for status changes
      if (res['success'] != false) {
        if (status.toLowerCase().contains('out')) {
          _notifySocketServer(orderId, 'out-for-delivery');
        } else if (status.toLowerCase() == 'delivered') {
          _notifySocketServer(orderId, 'delivered');
        }
      }

      return res;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> completeOrder({
    required String orderId,
  }) async {
    try {
      final res = await _apiClient.patch(
        '${ApiClient.riderBaseUrl}/complete',
        data: {'orderId': orderId},
        requiresAuth: true,
      );
      if (res['success'] != false) {
        _notifySocketServer(orderId, 'delivered');
      }
      return res;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> requestOtp({required String orderId}) async {
    try {
      final res = await _apiClient.post(
        '${ApiClient.riderBaseUrl}/generate-otp',
        data: {'orderId': orderId},
        requiresAuth: true,
      );
      return res is Map<String, dynamic> ? res : {'success': true, 'data': res};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String orderId,
    required String otp,
  }) async {
    try {
      final res = await _apiClient.patch(
        '${ApiClient.riderBaseUrl}/complete',
        data: {'orderId': orderId, 'otp': otp},
        requiresAuth: true,
      );
      if (res is Map<String, dynamic>) {
        if (res['success'] != false) {
          _notifySocketServer(orderId, 'delivered');
        }
        return res;
      }
      _notifySocketServer(orderId, 'delivered');
      return {'success': true, 'data': res};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Marks the order as delivered by:
  /// 1. Calling the Vercel API PATCH /rider/complete
  /// 2. Notifying the Socket/Render server via POST /api/order/delivered
  Future<Map<String, dynamic>> markAsDelivered({
    required String orderId,
  }) async {
    try {
      // Step 1: Update status on backend to 'Delivered'
      final vercelRes = await _apiClient.patch(
        '${ApiClient.riderBaseUrl}/status',
        data: {
          'orderId': orderId,
          'status': 'Delivered',
        },
        requiresAuth: true,
      );

      // Step 2: notify socket server
      if (vercelRes['success'] != false) {
        _notifySocketServer(orderId, 'delivered');
      }

      return vercelRes;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Helper to notify the Socket/Render server about order status changes.
  /// This triggers real-time socket events and push notifications for the user.
  Future<void> _notifySocketServer(String orderId, String status) async {
    try {
      final socketUrl = ApiConfig.socketUrl;
      final dio = Dio(BaseOptions(baseUrl: socketUrl));

      // Determine endpoint based on status
      String endpoint = '/api/order/status-update'; // Generic fallback
      if (status == 'delivered') endpoint = '/api/order/delivered';
      if (status == 'accepted') endpoint = '/api/order/accepted';
      if (status == 'out-for-delivery') {
        endpoint = '/api/order/out-for-delivery';
      }

      await dio.post(
        endpoint,
        data: {'orderId': orderId},
      );
      debugPrint('🔔 Socket server notified: $endpoint');
    } catch (e) {
      debugPrint('⚠️ Failed to notify socket server ($status): $e');
    }
  }

  Future<Map<String, dynamic>> updateStatus(String status) async {
    try {
      final res = await _apiClient.patch(
        '${ApiClient.riderBaseUrl}/status',
        data: {'status': status},
        requiresAuth: true,
      );
      return res;
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        // Fallback: If the backend returns 404 (possibly misrouted to order-logic),
        // we treat it as success locally so the UI can proceed to Online/Offline state.
        return {'success': true, 'message': 'Status updated locally'};
      }
      return {'success': false, 'message': e.toString()};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> getOrderDetails(String id) async {
    try {
      final res = await _apiClient.get(
        '${ApiClient.riderBaseUrl}/orders/$id',
        requiresAuth: true,
      );
      return res;
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }



  /// Step 1: Initiate cancellation — starts the 5-minute countdown on the backend.
  Future<Map<String, dynamic>> initiateCancellation({
    required String orderId,
    required String reason,
  }) async {
    try {
      final res = await _apiClient.post(
        '${ApiClient.riderBaseUrl}/orders/$orderId/cancel-initiate',
        data: {'reason': reason},
        requiresAuth: true,
      );
      return res is Map<String, dynamic> ? res : {'success': false, 'message': 'Unexpected response'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Step 2: Confirm cancellation — callable only after the 5-minute wait.
  Future<Map<String, dynamic>> confirmCancellation({
    required String orderId,
  }) async {
    try {
      final res = await _apiClient.post(
        '${ApiClient.riderBaseUrl}/orders/$orderId/cancel-confirm',
        data: <String, dynamic>{},
        requiresAuth: true,
      );
      return res is Map<String, dynamic> ? res : {'success': false, 'message': 'Unexpected response'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<List<dynamic>> getDeliveryHistory() async {
    try {
      final response = await _apiClient.get(
        '${ApiClient.riderBaseUrl}/history',
        requiresAuth: true,
      );

      if (response is List) {
        return response;
      }

      if (response is Map) {
        return response['data'] ??
            response['orders'] ??
            response['history'] ??
            [];
      }

      return [];
    } catch (e) {
      return [];
    }
  }
}

final riderServiceProvider = Provider<RiderService>((ref) {
  return RiderService(ref.watch(apiClientProvider));
});

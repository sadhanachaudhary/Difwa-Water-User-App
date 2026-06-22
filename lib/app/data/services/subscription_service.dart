import '../models/subscription_model.dart';
import '../network/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for SubscriptionService
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService(client: ref.watch(apiClientProvider));
});

/// Notifier for fetching and managing user subscriptions with optimistic updates
final mySubscriptionsProvider =
    AsyncNotifierProvider<SubscriptionNotifier, List<UserSubscription>>(
        SubscriptionNotifier.new);

class SubscriptionNotifier extends AsyncNotifier<List<UserSubscription>> {
  @override
  Future<List<UserSubscription>> build() async {
    return ref.watch(subscriptionServiceProvider).getMySubscriptions();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => ref.read(subscriptionServiceProvider).getMySubscriptions());
  }

  /// Update subscription status (Active/Paused) with optimistic UI update.
  Future<bool> updateStatus(String subId, String status) async {
    final oldState = state;
    if (state.hasValue) {
      state = AsyncValue.data(state.value!.map((s) {
        return s.id == subId ? s.copyWith(status: status) : s;
      }).toList());
    }

    final success =
        await ref.read(subscriptionServiceProvider).updateStatus(subId, status);
    if (!success) {
      state = oldState;
    } else {
      refresh();
    }
    return success;
  }

  /// Pause or resume a specific date range / single day.
  ///
  /// - **Pause** (isResume=false): adds the date range to vacationDates.
  /// - **Resume** (isResume=true): removes the date range from vacationDates.
  Future<Map<String, dynamic>> updateVacation({
    required String subscriptionId,
    required DateTime startDate,
    required DateTime endDate,
    bool isResume = false,
  }) async {
    final oldState = state;

    // Normalize to midnight
    final nStart = DateTime(startDate.year, startDate.month, startDate.day);
    final nEnd = DateTime(endDate.year, endDate.month, endDate.day);

    // All dates in range
    final List<DateTime> rangeDates = [];
    var cur = nStart;
    while (!cur.isAfter(nEnd)) {
      rangeDates.add(cur);
      // Safety: always land on local midnight, avoiding DST issues
      cur = DateTime(cur.year, cur.month, cur.day + 1);
    }

    // --- Optimistic update ---
    if (state.hasValue) {
      state = AsyncValue.data(state.value!.map((s) {
        if (s.id != subscriptionId) return s;
        if (isResume) {
          // Remove these dates
          final updated = s.vacationDates
              .where((vd) => !rangeDates.any((rd) => rd == vd))
              .toList();
          return s.copyWith(vacationDates: updated);
        } else {
          // Add dates (no duplicates)
          final newDates = rangeDates
              .where((rd) => !s.vacationDates.any((vd) => vd == rd))
              .toList();
          return s.copyWith(vacationDates: [...s.vacationDates, ...newDates]);
        }
      }).toList());
    }

    // --- Backend call ---
    final res = await ref.read(subscriptionServiceProvider).updateVacation(
          subscriptionId: subscriptionId,
          startDate: nStart,
          endDate: nEnd,
          rangeDates: rangeDates,
          isResume: isResume,
        );

    if (res['success'] == true) {
      refresh();
    } else {
      state = oldState;
    }
    return res;
  }

  /// Clear ALL future vacation dates for a subscription (Vacation Mode OFF).
  ///
  /// This sends the exact list of future vacation dates with isResume:true
  /// so the backend removes them specifically from the "Do Not Pack" list.
  /// Does NOT use isReset (backend support is uncertain).
  /// Returns true if all dates were cleared successfully.
  Future<bool> clearAllVacations(String subscriptionId) async {
    if (!state.hasValue) return false;

    final subs = state.value!;
    final sub = subs.where((s) => s.id == subscriptionId).firstOrNull;
    if (sub == null) return false;

    final now = DateTime.now();
    // Resume from tomorrow — never touch today
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    // Get all vacation dates from tomorrow onwards that need to be cleared
    final futureDates =
        sub.vacationDates.where((vd) => !vd.isBefore(tomorrow)).toList();

    if (futureDates.isEmpty) return true; // Nothing to clear

    // --- Optimistic update: remove those dates immediately ---
    final oldState = state;
    state = AsyncValue.data(subs.map((s) {
      if (s.id != subscriptionId) return s;
      final retained =
          s.vacationDates.where((vd) => vd.isBefore(tomorrow)).toList();
      return s.copyWith(vacationDates: retained);
    }).toList());

    // Sort dates to build the range span
    futureDates.sort();
    // startDate is always tomorrow (first date in the cleared range)
    final rangeStart = futureDates.first;
    final rangeEnd = futureDates.last;

    // --- ONE API call: send all dates explicitly with isResume:true ---
    final res = await ref.read(subscriptionServiceProvider).updateVacation(
          subscriptionId: subscriptionId,
          startDate: rangeStart,
          endDate: rangeEnd,
          rangeDates: futureDates, // backend uses this to remove from Do-Not-Pack
          isResume: true,          // tells backend: REMOVE these dates
        );

    if (res['success'] != true) {
      state = oldState; // Rollback on failure
      return false;
    }
    // Caller does ONE final refresh after processing all subscriptions
    return true;
  }
}

/// Service layer for subscriptions.
class SubscriptionService {
  final ApiClient _client;

  SubscriptionService({ApiClient? client})
      : _client = client ?? ApiClient.createDefault();

  /// Fetch all available subscription plans.
  Future<List<SubscriptionPlan>> getSubscriptions() async {
    try {
      final json = await _client.get('${ApiClient.subscriptionBaseUrl}/',
          requiresAuth: true);
      final success = json['success'] as bool? ?? false;
      if (!success) {
        throw ApiException(
            message:
                json['message']?.toString() ?? 'Failed to load subscriptions');
      }
      final data = json['data'] as List<dynamic>? ?? [];
      return data
          .map((e) => SubscriptionPlan.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  /// Fetch user's active subscriptions.
  Future<List<UserSubscription>> getMySubscriptions() async {
    try {
      final json = await _client.get('${ApiClient.subscriptionBaseUrl}/my',
          requiresAuth: true);
      final success = json['success'] as bool? ?? false;
      if (!success) {
        throw ApiException(
            message: json['message']?.toString() ??
                'Failed to load user subscriptions');
      }
      final data = json['subscriptions'] as List<dynamic>? ?? [];
      return data
          .map((e) => UserSubscription.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiException(message: e.toString());
    }
  }

  /// Create a new subscription for a product.
  Future<Map<String, dynamic>> subscribeToProduct({
    required String productId,
    required String frequency,
    required int quantity,
    required Map<String, dynamic> deliveryAddress,
    List<String> customDays = const [],
    DateTime? startDate,
    String? deliverySlot,
    String paymentMethod = 'Wallet', // 'Wallet' (upfront) or 'PayLater'
    bool? hasEmptyBottles,
    int? returnedBottlesCount,
  }) async {
    try {
      final payload = {
        'productId': productId,
        'frequency': frequency,
        'quantity': quantity,
        'deliveryAddress': deliveryAddress,
        'customDays': customDays,
        'startDate': startDate?.toIso8601String(),
        if (deliverySlot != null) 'deliverySlot': deliverySlot,
        'paymentMethod': paymentMethod,
        if (hasEmptyBottles != null) 'hasEmptyBottles': hasEmptyBottles,
        if (returnedBottlesCount != null) 'returnedBottlesCount': returnedBottlesCount,
      };

      final json = await _client.post(
        '${ApiClient.subscriptionBaseUrl}/subscribe',
        data: payload,
        requiresAuth: true,
      );

      return {
        'success': json['success'] as bool? ?? false,
        'message': json['message']?.toString() ?? 'Subscription successful',
        'data': json['subscription'],
      };
    } catch (e) {
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  /// Pause or Resume a subscription entirely (Active/Paused status).
  Future<bool> updateStatus(String subscriptionId, String status) async {
    try {
      final json = await _client.patch(
        '${ApiClient.subscriptionBaseUrl}/status',
        data: {'subscriptionId': subscriptionId, 'status': status},
        requiresAuth: true,
      );
      return json['success'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Schedule vacation (pause/resume delivery for a date range).
  ///
  /// [rangeDates]:  Every individual date (YYYY-MM-DD) for the backend's
  ///                predictive "Do Not Pack" engine.
  /// [isResume]:    true → remove these dates from vacation (resume deliveries).
  ///                false → add these dates to vacation (pause deliveries).
  Future<Map<String, dynamic>> updateVacation({
    required String subscriptionId,
    required DateTime startDate,
    required DateTime endDate,
    required List<DateTime> rangeDates,
    bool isResume = false,
  }) async {
    try {
      // Format as YYYY-MM-DD — no ISO time, no UTC shift
      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final payload = <String, dynamic>{
        'subscriptionId': subscriptionId,
        'startDate': fmt(startDate),
        'endDate': fmt(endDate),
        'vacationDates': rangeDates.map(fmt).toList(), // always send the list
        if (isResume) 'isResume': true,
      };

      final json = await _client.post(
        '${ApiClient.subscriptionBaseUrl}/vacation',
        data: payload,
        requiresAuth: true,
      );

      return {
        'success': json['success'] as bool? ?? false,
        'message': json['message']?.toString() ?? 'Vacation updated',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }
}

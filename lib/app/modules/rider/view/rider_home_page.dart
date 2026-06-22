import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../auth/provider/auth_provider.dart';
import '../../../data/services/rider_service.dart';
import '../../../data/services/socket_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../routes/app_routes.dart';
import 'rider_order_details_page.dart';
import 'rider_history_page.dart'; // to invalidate deliveryHistoryProvider
import '../../../core/utils/auth_helper.dart';
import '../../../../core/api/api_provider.dart';

final riderOrdersProvider =
    FutureProvider<List<dynamic>>((ref) async {
  ref.watch(authProvider); // Invalidate on auth change
  final riderService = ref.watch(riderServiceProvider);
  final all = await riderService.getAssignedOrders();
  // Only show orders that are actively assigned (not delivered/cancelled/rejected)
  const doneStatuses = {'delivered', 'cancelled', 'rejected', 'completed'};
  return all.where((o) {
    final s = (o['status']?.toString() ?? '').toLowerCase();
    return !doneStatuses.contains(s);
  }).toList();
});

// ── Rider dashboard stats: orders count, rating, earnings ───────────────────────

class _RiderStats {
  final int orders;
  final double rating;
  const _RiderStats(
      {required this.orders, required this.rating});
}

final riderStatsProvider = FutureProvider<_RiderStats>((ref) async {
  ref.watch(authProvider); // Invalidate on auth change
  final riderService = ref.read(riderServiceProvider);
  
  int orders = 0;
  double rating = 0.0;

  try {
    final history = await riderService.getDeliveryHistory();
    // Ensure only delivered/completed orders are counted
    orders = history.where((o) {
      final s = (o['status']?.toString() ?? '').toLowerCase();
      return s == 'delivered' || s == 'completed';
    }).length;
  } catch (e) {
    debugPrint('Error calculating orders from history: $e');
  }

  rating = 4.5; // Default rating as API is removed

  return _RiderStats(
    orders: orders,
    rating: rating,
  );
});


class RiderHomePage extends ConsumerStatefulWidget {
  const RiderHomePage({super.key});

  @override
  ConsumerState<RiderHomePage> createState() => _RiderHomePageState();
}

class RiderStatusNotifier extends Notifier<bool> {
  static const _key = 'rider_online_status';

  @override
  bool build() {
    // Start with false, then load from storage
    _loadFromStorage();
    return false;
  }

  Future<void> _loadFromStorage() async {
    try {
      final storage = ref.read(storageServiceProvider);
      final saved = await storage.getBool(_key);
      if (saved != null && saved != state) {
        state = saved;
        
        // If we restored an "online" state, ensure we join the socket rooms
        if (saved) {
          final authState = ref.read(authProvider);
          if (authState is AuthAuthenticated) {
            final socket = ref.read(socketServiceProvider);
            socket.joinRiderRoom(authState.user.id);
            socket.joinUserRoom(authState.user.id);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading rider status: $e');
    }
  }

  Future<void> toggle(bool value) async {
    if (state == value) return;
    state = value;
    try {
      final storage = ref.read(storageServiceProvider);
      await storage.setBool(_key, value);
    } catch (e) {
      debugPrint('Error saving rider status: $e');
    }
  }
}

final riderStatusProvider =
    NotifierProvider<RiderStatusNotifier, bool>(RiderStatusNotifier.new);

class _RiderHomePageState extends ConsumerState<RiderHomePage> {
  bool _isTogglingStatus = false;
  final Set<String> _processingIds = {};
  String? _selectedCustomerPhone;
  String? _selectedAddress;

  // Cancel flow: orderId → time when cancel-initiate was called
  final Map<String, DateTime> _cancelInitiatedAt = {};
  Timer? _countdownTicker;

  bool get _isOnline => ref.watch(riderStatusProvider);
  set _isOnline(bool value) =>
      ref.read(riderStatusProvider.notifier).toggle(value);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSocket());
  }

  void _initSocket() {
    final authState = ref.read(authProvider);
    if (authState is! AuthAuthenticated) return;

    final socket = ref.read(socketServiceProvider);
    final userId = authState.user.id;
    final riderId = userId; // rider ID == user ID for riders

    // Join the rider's personal room to receive new order assignments
    socket.joinRiderRoom(riderId);
    // Also join user room for generic order updates
    socket.joinUserRoom(userId);

    // 🔔 New order dispatched to this rider
    socket.onNewOrderAssigned((data) {
      if (!mounted) return;
      ref.invalidate(riderOrdersProvider);
      _showNewOrderBanner(data);
    });

    // 🔄 Any order status changed (accept/pickup/deliver)
    socket.onOrderUpdate((data) {
      if (!mounted) return;

      // Handle "Rider Assigned" specifically as a new task alert
      if (data is Map &&
          (data['status'] == 'Rider Assigned' ||
              data['status'] == 'Rider_Assigned')) {
        _showNewOrderBanner(data['data'] ?? data);
      }

      ref.invalidate(riderOrdersProvider);
      ref.invalidate(riderStatsProvider);
    });
  }

  void _showNewOrderBanner(dynamic data) {
    if (data == null) return;

    // Support flat payload or nested { order: {...} }
    final order = (data is Map && data['order'] is Map) ? data['order'] : data;

    final orderId = order?['orderId']?.toString() ??
        order?['id']?.toString() ??
        order?['_id']?.toString() ??
        '';
    final shortId = orderId.length >= 6
        ? orderId.substring(orderId.length - 6).toUpperCase()
        : orderId.toUpperCase();

    final customer = order?['customerName']?.toString() ??
        order?['customer']?['fullName']?.toString() ??
        order?['user']?['fullName']?.toString() ??
        'New Customer';

    final addressRaw = order?['deliveryAddress'] ?? order?['address'];
    final address = (addressRaw is Map)
        ? addressRaw['address']?.toString() ?? ''
        : addressRaw?.toString() ?? '';

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: Colors.transparent,
        elevation: 0,
        content: _NewOrderBanner(
          shortId: shortId,
          customer: customer,
          address: address,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    final socket = ref.read(socketServiceProvider);
    final authState = ref.read(authProvider);
    if (authState is AuthAuthenticated) {
      socket.leaveRiderRoom(authState.user.id);
      socket.leaveUserRoom(authState.user.id);
    }
    socket.offNewOrderAssigned();
    socket.offOrderUpdate();
    super.dispose();
  }

  /*  ── Location helpers (re-enable for production) ──────────────────────────
  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) { ... }
    ...
    return true;
  }
  bool _hasActiveDelivery(List<dynamic> orders) {
    return orders.any((o) {
      final status = (o['status']?.toString() ?? '').toLowerCase();
      return _activeStatuses.contains(status);
    });
  }
  */

  Future<void> _toggleOnline(bool value) async {
    if (_isTogglingStatus) return;
    setState(() => _isTogglingStatus = true);

    try {
      // ── Going ONLINE ────────────────────────────────────────────────────
      if (value) {
        // NOTE: Location check disabled for testing — re-enable in production
        // final hasPermission = await _ensureLocationPermission();
        // if (!hasPermission) { setState(() => _isTogglingStatus = false); return; }

        // Call backend PATCH /rider/status { status: 'online' }
        final riderService = ref.read(riderServiceProvider);
        final result = await riderService.updateStatus('online');

        if (result['success'] == false) {
          if (mounted) {
            _showSnack(result['message'] ?? 'Failed to go online',
                isError: true);
          }
          setState(() => _isTogglingStatus = false);
          return;
        }

        // NOTE: LocationTracking disabled for testing — re-enable in production
        // await LocationTrackingService.start();
        if (mounted) {
          setState(() => _isOnline = true);
          _showSnack('You are now ONLINE ✅');

          // Explicitly join rooms again on manual toggle to be safe
          final authState = ref.read(authProvider);
          if (authState is AuthAuthenticated) {
            final socket = ref.read(socketServiceProvider);
            socket.joinRiderRoom(authState.user.id);
            socket.joinUserRoom(authState.user.id);
          }

          ref.invalidate(riderOrdersProvider);
          ref.invalidate(riderStatsProvider);
        }

        // ── Going OFFLINE ───────────────────────────────────────────────────
      } else {
        // NOTE: Active delivery block disabled for testing — re-enable in production
        // final ordersAsyncValue = ref.read(riderOrdersProvider);
        // final orders = ordersAsyncValue.value ?? [];
        // if (_hasActiveDelivery(orders)) { ... return; }

        // Call backend PATCH /rider/status { status: 'offline' }
        final riderService = ref.read(riderServiceProvider);
        final result = await riderService.updateStatus('offline');

        if (result['success'] == false) {
          if (mounted) {
            _showSnack(result['message'] ?? 'Failed to go offline',
                isError: true);
          }
          setState(() => _isTogglingStatus = false);
          return;
        }

        // NOTE: LocationTracking disabled for testing — re-enable in production
        // await LocationTrackingService.stop();
        if (mounted) {
          setState(() => _isOnline = false);
          _showSnack('You are now OFFLINE');
          ref.invalidate(riderOrdersProvider);
          ref.invalidate(riderStatsProvider);
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('404')
            ? 'Backend error: Status endpoint not found (404)'
            : 'Error: ${e.toString()}';
        _showSnack(msg, isError: true);
      }
    } finally {
      if (mounted) setState(() => _isTogglingStatus = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
      backgroundColor: isError ? Colors.redAccent : AppColors.accentGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  /* _showAlert — re-enable with location helpers in production
  void _showAlert({
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Color(0xFFFFF0E0),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.orange, size: 32),
        ),
        title: Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              onAction();
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
  */

  Future<void> _handleResponse(String orderId, String response) async {
    if (_processingIds.contains(orderId)) return;
    setState(() => _processingIds.add(orderId));

    try {
      final messenger = ScaffoldMessenger.of(context);
      final riderService = ref.read(riderServiceProvider);
      final result = await riderService.respondToOrder(
          orderId: orderId, response: response);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Action successful'),
            backgroundColor:
                result['success'] ? AppColors.accentGreen : Colors.red,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        if (result['success']) {
          ref.invalidate(riderOrdersProvider);
          try {
            await ref.read(riderOrdersProvider.future);
          } catch (_) {}
        }
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(orderId));
    }
  }

  Future<void> _markOutForDelivery(String orderId) async {
    if (_processingIds.contains(orderId)) return;
    setState(() => _processingIds.add(orderId));

    try {
      final messenger = ScaffoldMessenger.of(context);
      final result = await ref.read(riderServiceProvider).updateDeliveryStatus(
            orderId: orderId,
            status: 'Out for Delivery',
          );
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(result['message'] ?? '🚚 Out for Delivery!'),
          backgroundColor: AppColors.accentGreen,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        ref.invalidate(riderOrdersProvider);
        try {
          await ref.read(riderOrdersProvider.future);
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _processingIds.remove(orderId));
    }
  }

  Future<void> _startDeliveryOtp(String orderId) async {
    if (_processingIds.contains(orderId)) return;
    setState(() => _processingIds.add(orderId));

    try {
      final result =
          await ref.read(riderServiceProvider).requestOtp(orderId: orderId);
      if (!mounted) return;

      if (result['success'] == false) {
        _showSnack(result['message'] ?? 'Failed to send OTP', isError: true);
        return;
      }

      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _OtpEntrySheet(
          orderId: orderId,
          onSuccess: () {
            ref.invalidate(riderOrdersProvider);
            ref.invalidate(deliveryHistoryProvider);
            ref.invalidate(riderStatsProvider);
          },
        ),
      );
    } finally {
      if (mounted) setState(() => _processingIds.remove(orderId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;
    final ordersAsync = ref.watch(riderOrdersProvider);
    final statsAsync = ref.watch(riderStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Rider Dashboard',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1A1A1A)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () {
              AuthHelper.confirmSignOut(
                context: context,
                onConfirm: () async {
                  await ref.read(authProvider.notifier).logout();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      AppRoutes.login,
                      (route) => false,
                    );
                  }
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accentGreen,
        onRefresh: () async => ref.invalidate(riderOrdersProvider),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Rider Profile Card ──────────────────────────────────────────
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00ACC1).withValues(alpha: 0.2),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: const BoxDecoration(
                              color: Color(0xFFCFFAFE),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              size: 32,
                              color: Color(0xFF06B6D4),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.fullName ?? 'Rider Name',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1B2D1F),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user?.phoneNumber ?? '9876543211',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              if (_isTogglingStatus)
                                const SizedBox(
                                  width: 40,
                                  height: 28,
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: AppColors.accentGreen,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Switch.adaptive(
                                  value: _isOnline,
                                  activeTrackColor: AppColors.accentGreen
                                      .withValues(alpha: 0.5),
                                  activeThumbColor: AppColors.accentGreen,
                                  onChanged:
                                      _isTogglingStatus ? null : _toggleOnline,
                                ),
                              Text(
                                _isTogglingStatus
                                    ? 'LOADING'
                                    : _isOnline
                                        ? 'ONLINE'
                                        : 'OFFLINE',
                                style: TextStyle(
                                  color: _isTogglingStatus
                                      ? Colors.orange
                                      : _isOnline
                                          ? AppColors.accentGreen
                                          : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // Stats always visible (not gated behind online status)
                      ...[
                        const Divider(height: 32),
                        statsAsync.when(
                          loading: () => const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppColors.accentGreen),
                              ),
                            ),
                          ),
                          error: (_, __) => Center(
                            child: _buildStat(
                                'Total Delivered', '—', Icons.delivery_dining),
                          ),
                          data: (stats) => Center(
                            child: _buildStat('Total Delivered', '${stats.orders}',
                                Icons.delivery_dining),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (!_isOnline)
                _buildOfflineState()
              else ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Assigned Tasks',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1B2D1F)),
                      ),
                      Text(
                        'Live Tracking Active',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accentGreen),
                      )
                          .animate(onPlay: (controller) => controller.repeat())
                          .shimmer(
                              duration: 2.seconds,
                              color: Colors.white.withValues(alpha: 0.5))
                          .scale(
                              begin: const Offset(1, 1),
                              end: const Offset(1.05, 1.05),
                              duration: 1.seconds,
                              curve: Curves.easeInOut)
                          .then()
                          .scale(
                              begin: const Offset(1.05, 1.05),
                              end: const Offset(1, 1),
                              duration: 1.seconds,
                              curve: Curves.easeInOut),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ordersAsync.when(
                  data: (orders) {
                    final uniqueCustomers = <String, String>{};
                    final uniqueAddresses = <String>{};

                    for (final order in orders) {
                      final phone = order['user']?['phoneNumber']?.toString() ?? 
                                    order['customerPhone']?.toString() ?? 
                                    order['customer']?['phoneNumber']?.toString() ?? '';
                      final name = order['user']?['fullName']?.toString() ?? 
                                   order['customerName']?.toString() ?? 
                                   order['customer']?['fullName']?.toString() ?? 'Unknown Customer';
                      if (phone.isNotEmpty) uniqueCustomers[phone] = name;

                      final addrMap = order['deliveryAddress'] ?? order['address'];
                      String address = '';
                      if (addrMap is Map) {
                        final street = addrMap['fullAddress'] ?? addrMap['address'] ?? addrMap['street'] ?? '';
                        final city = addrMap['city'] ?? '';
                        address = '$street $city'.trim();
                      } else {
                        address = addrMap?.toString() ?? '';
                      }
                      if (address.isNotEmpty) uniqueAddresses.add(address);
                    }

                    // Reset selected filters if they no longer exist in current orders
                    if (_selectedCustomerPhone != null && !uniqueCustomers.containsKey(_selectedCustomerPhone)) {
                      _selectedCustomerPhone = null;
                    }
                    if (_selectedAddress != null && !uniqueAddresses.contains(_selectedAddress)) {
                      _selectedAddress = null;
                    }

                    final filteredOrders = orders.where((order) {
                      bool matchCustomer = true;
                      bool matchAddress = true;

                      if (_selectedCustomerPhone != null) {
                        final phone = order['user']?['phoneNumber']?.toString() ?? 
                                      order['customerPhone']?.toString() ?? 
                                      order['customer']?['phoneNumber']?.toString() ?? '';
                        matchCustomer = phone == _selectedCustomerPhone;
                      }

                      if (_selectedAddress != null) {
                        final addrMap = order['deliveryAddress'] ?? order['address'];
                        String address = '';
                        if (addrMap is Map) {
                          final street = addrMap['fullAddress'] ?? addrMap['address'] ?? addrMap['street'] ?? '';
                          final city = addrMap['city'] ?? '';
                          address = '$street $city'.trim();
                        } else {
                          address = addrMap?.toString() ?? '';
                        }
                        matchAddress = address == _selectedAddress;
                      }

                      return matchCustomer && matchAddress;
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (orders.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        hint: const Text('All Customers', style: TextStyle(fontSize: 13)),
                                        value: _selectedCustomerPhone,
                                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                                        items: [
                                          const DropdownMenuItem<String>(
                                            value: null,
                                            child: Text('All Customers', style: TextStyle(fontSize: 13)),
                                          ),
                                          ...uniqueCustomers.entries.map((e) {
                                            return DropdownMenuItem<String>(
                                              value: e.key,
                                              child: Text('${e.value} (${e.key})', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                                            );
                                          }),
                                        ],
                                        onChanged: (val) => setState(() => _selectedCustomerPhone = val),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        hint: const Text('All Addresses', style: TextStyle(fontSize: 13)),
                                        value: _selectedAddress,
                                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
                                        items: [
                                          const DropdownMenuItem<String>(
                                            value: null,
                                            child: Text('All Addresses', style: TextStyle(fontSize: 13)),
                                          ),
                                          ...uniqueAddresses.map((addr) {
                                            return DropdownMenuItem<String>(
                                              value: addr,
                                              child: Text(addr, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                                            );
                                          }),
                                        ],
                                        onChanged: (val) => setState(() => _selectedAddress = val),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (filteredOrders.isEmpty)
                          _buildEmptyState()
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filteredOrders.length,
                            itemBuilder: (context, index) {
                              final order = filteredOrders[index];
                              return _buildOrderCard(order);
                            },
                          ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(50),
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accentGreen)),
                  ),
                  error: (err, stack) => Center(child: Text('Error: $err')),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 60),
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.power_settings_new_rounded,
                size: 80, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 24),
          const Text(
            'You are currently Offline',
            style: TextStyle(
                color: Color(0xFF1B2D1F),
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Go online to see your assigned tasks',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildStat(String label, String value, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF00ACC1).withValues(alpha: 0.2),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F8EB),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.accentGreen, size: 22),
          ),
          const SizedBox(width: 16),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1B2D1F),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _showCancelDialog(String orderId) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Order',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please provide a reason for cancellation.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter reason...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Back', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Initiate Cancel'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _initiateCancellation(orderId, reasonController.text.trim());
    }
    reasonController.dispose();
  }

  Future<void> _initiateCancellation(String orderId, String reason) async {
    final riderService = ref.read(riderServiceProvider);
    final result = await riderService.initiateCancellation(
      orderId: orderId,
      reason: reason,
    );
    if (!mounted) return;
    if (result['success'] == false) {
      _showSnack(result['message'] ?? 'Failed to initiate cancellation',
          isError: true);
      return;
    }
    DateTime initiatedAt = DateTime.now();
    try {
      final ts = result['data']?['cancelInitiatedAt'] ?? result['cancelInitiatedAt'];
      if (ts != null) initiatedAt = DateTime.parse(ts.toString()).toLocal();
    } catch (_) {}
    setState(() => _cancelInitiatedAt[orderId] = initiatedAt);
    _showSnack('Cancellation initiated — wait 5 minutes to confirm.');
  }

  Future<void> _confirmCancellation(String orderId) async {
    final riderService = ref.read(riderServiceProvider);
    final result = await riderService.confirmCancellation(orderId: orderId);
    if (!mounted) return;
    if (result['success'] == false) {
      _showSnack(result['message'] ?? 'Failed to confirm cancellation',
          isError: true);
      return;
    }
    setState(() => _cancelInitiatedAt.remove(orderId));
    ref.invalidate(riderOrdersProvider);
    _showSnack('Order cancelled successfully.');
  }

  Widget _buildCancelSection(String orderId) {
    final initiatedAt = _cancelInitiatedAt[orderId];
    if (initiatedAt == null) {
      return OutlinedButton.icon(
        onPressed: () => _showCancelDialog(orderId),
        icon: const Icon(Icons.cancel_outlined, size: 16),
        label: const Text('Cancel Order',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red.shade600,
          side: BorderSide(color: Colors.red.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
      );
    }
    // Countdown and confirm button live in their own widget so only it rebuilds
    // every second — not the entire dashboard page.
    return _CancelCountdownWidget(
      initiatedAt: initiatedAt,
      onConfirm: () => _confirmCancellation(orderId),
    );
  }

  Widget _buildOrderCard(dynamic order) {
    final rawAssignmentStatus = (order['riderAssignmentStatus'] ?? '').toString().toLowerCase();
    final orderStatus = (order['status']?.toString() ?? 'Pending').toLowerCase();

    // Support both specific assignment field and main order status
    final isPending = rawAssignmentStatus == 'pending' || 
                      orderStatus == 'rider assigned' || 
                      orderStatus == 'rider_assigned';
                      
    final isAccepted = rawAssignmentStatus == 'accepted' ||
                       orderStatus == 'rider accepted' ||
                       orderStatus == 'rider_accepted' ||
                       ['out for delivery', 'out_for_delivery', 'pickedup', 'picked_up', 'arrived'].contains(orderStatus);

    final isDelivered = orderStatus == 'delivered' || orderStatus == 'completed';
    final bool isProcessing = _processingIds.contains(order['orderId']);

    final items = (order['items'] as List<dynamic>?) ?? [];

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RiderOrderDetailsPage(order: order),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: const Color(0xFF00ACC1).withValues(alpha: 0.15),
            width: 1.0,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFCFFAFE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#${(order['orderId']?.toString() ?? '').length >= 6 ? order['orderId'].toString().substring(order['orderId'].toString().length - 6).toUpperCase() : (order['orderId']?.toString() ?? '').toUpperCase()}',
                              style: const TextStyle(
                                color: Color(0xFF06B6D4),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          if (order['orderType'] == 'Subscription') ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.purple.shade100),
                              ),
                              child: Text(
                                'SUB',
                                style: TextStyle(
                                  color: Colors.purple.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                          if (order['hasExtras'] == true) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blue.shade100),
                              ),
                              child: Text(
                                '+ EXTRAS',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7E6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          (order['status']?.toString() ?? 'UNKNOWN').toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFFFFA000),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  
                  _buildOrderInfoRow(
                    Icons.location_on_rounded,
                    'Delivery Address',
                    (() {
                      final addrMap = order['deliveryAddress'];
                      if (addrMap is Map) {
                        final name = addrMap['fullName'] ?? addrMap['name'] ?? '';
                        final street = addrMap['fullAddress'] ?? addrMap['address'] ?? addrMap['street'] ?? '';
                        final city = addrMap['city'] ?? '';
                        List<String> parts = [];
                        if (street.toString().isNotEmpty) parts.add(street.toString());
                        if (city.toString().isNotEmpty) parts.add(city.toString());
                        String addr = parts.isNotEmpty ? parts.join(', ') : 'No address provided';
                        return name.toString().isNotEmpty ? '$name\n$addr' : addr;
                      }
                      return addrMap?.toString() ?? 'No address provided';
                    })(),
                  ),
                  const SizedBox(height: 10),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildOrderInfoRow(
                          Icons.person_rounded,
                          'Customer',
                          (order['user'] is Map)
                              ? (order['user']['fullName'] ?? order['user']['name'] ?? 'Customer').toString().toUpperCase()
                              : (order['customerName'] ?? 'CUSTOMER').toString().toUpperCase(),
                        ),
                      ),
                      Expanded(
                        child: _buildOrderInfoRow(
                          Icons.directions_run_rounded,
                          'Plant / Vendor',
                          (() {
                            final retailer = order['retailer'] ?? (items.isNotEmpty ? items.first['retailer'] : null);
                            if (retailer is Map) {
                              return (retailer['businessDetails']?['storeDisplayName'] ?? retailer['fullName'] ?? retailer['name'] ?? 'RETAILER').toString().toUpperCase();
                            }
                            return 'RETAILER';
                          })(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildOrderInfoRow(
                          Icons.currency_rupee_rounded,
                          'Total Money',
                          '₹${(order['totalAmount'] ?? order['total'] ?? 0).toString()}',
                        ),
                      ),
                      Expanded(
                        child: _buildOrderInfoRow(
                          Icons.format_list_numbered_rounded,
                          'Total Qty',
                          '${items.fold(0, (sum, i) => sum + (int.tryParse(i['quantity']?.toString() ?? '1') ?? 1))} Units',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  
                  // Product Details
                  const Text('Products', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  if (items.isEmpty)
                    const Text('No items', style: TextStyle(fontSize: 12, color: Colors.grey))
                  else
                    ...items.map((i) {
                      final p = i['product'];
                      final name = (p is Map) ? (p['name'] ?? i['name'] ?? 'Item') : (i['name'] ?? 'Item');
                      final price = (p is Map) ? (p['price'] ?? i['price'] ?? 0) : (i['price'] ?? 0);
                      final qty = i['quantity'] ?? 1;
                      final image = (p is Map) ? (p['image'] ?? i['image']) : i['image'];
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: (image != null && image.toString().startsWith('http'))
                                    ? Image.network(
                                        image.toString(), 
                                        fit: BoxFit.cover, 
                                        errorBuilder: (_,__,___) => const Icon(Icons.inventory_2_rounded, size: 20, color: Colors.grey)
                                      )
                                    : const Icon(Icons.inventory_2_rounded, size: 20, color: Colors.grey),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name.toString(), 
                                    maxLines: 1, 
                                    overflow: TextOverflow.ellipsis, 
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1B2D1F))
                                  ),
                                  Text(
                                    '₹$price  x  $qty', 
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '₹${(double.tryParse(price.toString()) ?? 0) * (int.tryParse(qty.toString()) ?? 1)}', 
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1B2D1F))
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
            // Single Action Button Workflow
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  (() {
                    if (isPending) {
                      // STEP 1: ACCEPT or REJECT ORDER
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton.icon(
                            onPressed: isProcessing
                                ? null
                                : () => _handleResponse(order['orderId'], 'Accepted'),
                            icon: isProcessing
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white70,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline_rounded, size: 18),
                            label: Text(
                                isProcessing ? 'Processing...' : 'Accept Order',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isProcessing
                                  ? Colors.grey
                                  : const Color(0xFF06B6D4),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: isProcessing
                                ? null
                                : () => _handleResponse(order['orderId'], 'Rejected'),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Reject Order',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade600,
                              side: BorderSide(color: Colors.red.shade300),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ],
                      );
                    } else if (isAccepted && !isDelivered) {
                      final s = orderStatus.toLowerCase();
                      if (['out for delivery', 'out_for_delivery', 'arrived']
                          .contains(s)) {
                        // STEP 3: COMPLETE ORDER via OTP
                        return ElevatedButton.icon(
                          onPressed: isProcessing
                              ? null
                              : () => _startDeliveryOtp(order['orderId']),
                          icon: isProcessing
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
                                  ),
                                )
                              : const Icon(Icons.lock_open_rounded, size: 18),
                          label: Text(
                              isProcessing ? 'Sending OTP...' : 'Complete Order',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isProcessing
                                ? Colors.grey
                                : AppColors.accentGreen,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        );
                      } else {
                        // STEP 2: OUT FOR DELIVERY
                        return ElevatedButton.icon(
                          onPressed: isProcessing
                              ? null
                              : () => _markOutForDelivery(order['orderId']),
                          icon: isProcessing
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
                                  ),
                                )
                              : const Icon(Icons.delivery_dining_rounded, size: 18),
                          label: Text(
                              isProcessing
                                  ? 'Processing...'
                                  : 'Mark Out for Delivery',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isProcessing
                                ? Colors.grey
                                : Colors.orange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        );
                      }
                    }
                    return const SizedBox.shrink();
                  })(),
                  if (isAccepted && !isDelivered) ...[
                    const SizedBox(height: 8),
                    _buildCancelSection(order['orderId'].toString()),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildOrderInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: Color(0xFFF1F4F8),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF1B2D1F),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 60),
          Container(
            padding: const EdgeInsets.all(30),
            decoration: const BoxDecoration(
              color: Color(0xFFF1F8EB),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.delivery_dining_rounded,
                size: 80,
                color: const Color(0xFF06B6D4).withValues(alpha: 0.2)),
          ),
          const SizedBox(height: 24),
          const Text(
            'All clear! No pending tasks.',
            style: TextStyle(
                color: Color(0xFF1B2D1F),
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Go online to receive new orders',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    ).animate().fadeIn();
  }
}

// ── Cancel countdown widget ──────────────────────────────────────────────────
//
// Owns its own 1-second Timer so only this tiny widget rebuilds each tick —
// the entire RiderHomePage (order list, images, stats) is never re-rendered
// just to update the countdown display. This eliminates the BLASTBufferQueue
// pressure caused by the previous global setState() ticker.

class _CancelCountdownWidget extends StatefulWidget {
  final DateTime initiatedAt;
  final VoidCallback onConfirm;

  const _CancelCountdownWidget({
    required this.initiatedAt,
    required this.onConfirm,
  });

  @override
  State<_CancelCountdownWidget> createState() => _CancelCountdownWidgetState();
}

class _CancelCountdownWidgetState extends State<_CancelCountdownWidget> {
  Timer? _timer;

  Duration get _remaining {
    final elapsed = DateTime.now().difference(widget.initiatedAt);
    final r = const Duration(minutes: 5) - elapsed;
    return r.isNegative ? Duration.zero : r;
  }

  @override
  void initState() {
    super.initState();
    if (_remaining > Duration.zero) _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining <= Duration.zero) {
        _timer?.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;

    if (remaining > Duration.zero) {
      final mins = remaining.inMinutes.toString().padLeft(2, '0');
      final secs = (remaining.inSeconds % 60).toString().padLeft(2, '0');
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 16, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Text(
              'Confirm available in $mins:$secs',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade800),
            ),
          ],
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: widget.onConfirm,
      icon: const Icon(Icons.cancel_rounded, size: 18),
      label: const Text('Confirm Cancellation',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

// ── OTP Entry Bottom Sheet ────────────────────────────────────────────────────

class _OtpEntrySheet extends ConsumerStatefulWidget {
  final String orderId;
  final VoidCallback onSuccess;

  const _OtpEntrySheet({required this.orderId, required this.onSuccess});

  @override
  ConsumerState<_OtpEntrySheet> createState() => _OtpEntrySheetState();
}

class _OtpEntrySheetState extends ConsumerState<_OtpEntrySheet>
    with SingleTickerProviderStateMixin {
  final _otpController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() {
    _otpController.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final otp = _otpController.text.trim();
    if (otp.length < 4) {
      setState(() => _errorMessage = 'Enter the 4-digit OTP');
      _shakeCtrl.forward(from: 0);
      return;
    }
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });
    final result = await ref
        .read(riderServiceProvider)
        .verifyOtp(orderId: widget.orderId, otp: otp);
    if (!mounted) return;
    if (result['success'] != false) {
      widget.onSuccess();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(children: [
          Icon(Icons.check_circle_rounded, color: Colors.white),
          SizedBox(width: 10),
          Text('Order completed successfully!',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
        backgroundColor: AppColors.accentGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ));
    } else {
      final msg = result['message']?.toString() ?? 'Verification failed';
      setState(() {
        _isVerifying = false;
        _errorMessage = msg;
      });
      _shakeCtrl.forward(from: 0);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _errorMessage = null;
    });
    final result = await ref
        .read(riderServiceProvider)
        .requestOtp(orderId: widget.orderId);
    if (!mounted) return;
    setState(() => _isResending = false);
    final msg = result['success'] != false
        ? 'OTP resent to customer'
        : (result['message'] ?? 'Failed to resend OTP');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor:
          result['success'] != false ? AppColors.accentGreen : Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Icon(Icons.lock_rounded, size: 40, color: Color(0xFF0891B2)),
          const SizedBox(height: 12),
          const Text(
            'Enter OTP from customer',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Ask the customer for the 4-digit code sent to their app',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 28),
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (_, child) =>
                Transform.translate(offset: Offset(_shakeAnim.value, 0), child: child),
            child: TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 16),
              decoration: InputDecoration(
                counterText: '',
                hintText: '• • • •',
                hintStyle: TextStyle(
                    color: Colors.grey.shade300,
                    fontSize: 28,
                    letterSpacing: 12),
                filled: true,
                fillColor: const Color(0xFFF7F8FA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                      color: Color(0xFF0891B2), width: 2),
                ),
                errorText: _errorMessage,
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isVerifying ? null : _verify,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Verify & Complete Order',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _isResending ? null : _resend,
            icon: _isResending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Resend OTP to customer'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0891B2),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── New Order Banner ──────────────────────────────────────────────────────────

/// Shown inside a SnackBar when `newOrderAssigned` arrives via Socket.IO.
class _NewOrderBanner extends StatelessWidget {
  final String shortId;
  final String customer;
  final String address;

  const _NewOrderBanner({
    required this.shortId,
    required this.customer,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF06B6D4), Color(0xFF06B6D4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF00ACC1).withOpacity(0.1),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulsing bell icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_active_rounded,
                color: Colors.white, size: 26),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(begin: 1.0, end: 1.15, duration: 700.ms),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      '🛵  New Order!',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '#$shortId',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                if (customer.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      customer,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if (address.isNotEmpty)
                  Text(
                    address,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate()
        .slideY(begin: -0.5, end: 0, duration: 400.ms, curve: Curves.easeOut)
        .fadeIn(duration: 300.ms);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/food_models.dart';
import '../../../data/services/order_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_images.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/state/auth_store.dart';
import '../../../data/services/socket_service.dart';
import '../../../data/services/db_service.dart';
import 'track_order_page.dart';

class ActiveOrdersPage extends ConsumerStatefulWidget {
  const ActiveOrdersPage({super.key});

  @override
  ConsumerState<ActiveOrdersPage> createState() => _ActiveOrdersPageState();
}

class _ActiveOrdersPageState extends ConsumerState<ActiveOrdersPage> {
  late void Function(dynamic) _onOrderUpdate;
  late void Function(dynamic) _onDeliveryOtp;

  // Keyed by orderId — holds OTP payloads received via socket
  final Map<String, Map<String, dynamic>> _socketOtps = {};

  @override
  void initState() {
    super.initState();
    _onOrderUpdate = (data) {
      if (!mounted) return;
      debugPrint('📦 Order status updated via socket: $data');
      // Reactively handled by ActiveOrdersNotifier
    };

    _onDeliveryOtp = (data) {
      if (!mounted) return;
      debugPrint('🔐 DELIVERY_OTP received: $data');
      if (data is Map) {
        final orderId = data['orderId']?.toString() ?? '';
        if (orderId.isNotEmpty) {
          setState(() {
            _socketOtps[orderId] = Map<String, dynamic>.from(data);
          });
        }
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(currentUserProvider);
      if (user != null) {
        final socket = ref.read(socketServiceProvider);
        socket.joinUserRoom(user.id);
        socket.onOrderUpdate(_onOrderUpdate);
        socket.onDeliveryOtp(_onDeliveryOtp);
      }
    });
  }

  @override
  void dispose() {
    final socket = ref.read(socketServiceProvider);
    socket.offOrderUpdate(_onOrderUpdate);
    socket.offDeliveryOtp(_onDeliveryOtp);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeOrdersAsync = ref.watch(activeOrdersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          'Active Orders',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: Color(0xFF1E293B),
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 20, color: Color(0xFF1E293B)),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: const Color(0xFF00ACC1).withValues(alpha: 0.1),
            height: 1,
          ),
        ),
      ),
      body: SafeArea(
        child: activeOrdersAsync.when(
          data: (orders) {
            final pendingCancelledOrders = orders
                .where((o) => o.status.toLowerCase() != 'delivered')
                .toList();

            if (pendingCancelledOrders.isEmpty) {
              return _buildEmptyState(context);
            }
            final sortedOrders = List<UserOrder>.from(pendingCancelledOrders)
              ..sort((a, b) => b.date.compareTo(a.date));
            return RefreshIndicator(
              color: const Color(0xFF0891B2),
              onRefresh: () async =>
                  ref.read(activeOrdersProvider.notifier).refresh(),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                itemCount: sortedOrders.length,
                itemBuilder: (context, index) {
                  final order = sortedOrders[index];
                  final socketOtp = _socketOtps[order.id];
                  return _ActiveOrderCard(order: order, socketOtpData: socketOtp);
                },
              ),
            );
          },
          loading: () => _buildLoading(),
          error: (err, _) => _buildError(err),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: 3,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 20),
        height: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const _ShimmerBox(),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(
                color: Color(0xFFCFFAFE),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  size: 56, color: Color(0xFF06B6D4)),
            ),
            const SizedBox(height: 24),
            const Text('No Active Orders',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: Color(0xFF1E293B))),
            const SizedBox(height: 8),
            Text('Place an order and track it live here!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Order Something',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0891B2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(Object err) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          const Text('Could not load orders',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Text(err.toString(),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => ref.invalidate(activeOrdersProvider),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0891B2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Order Card ─────────────────────────────────────────────────────────────────

class _ActiveOrderCard extends ConsumerWidget {
  final UserOrder order;
  final Map<String, dynamic>? socketOtpData;
  const _ActiveOrderCard({required this.order, this.socketOtpData});

  String? _resolvedOtp() {
    final now = DateTime.now();
    // Prefer socket data (most recent), fall back to API-persisted OTP
    if (socketOtpData != null) {
      final otp = socketOtpData!['otp']?.toString();
      final expiresAtStr = socketOtpData!['expiresAt']?.toString();
      final expiresAt = expiresAtStr != null ? DateTime.tryParse(expiresAtStr)?.toLocal() : null;
      if (otp != null && otp.isNotEmpty && (expiresAt == null || expiresAt.isAfter(now))) {
        return otp;
      }
    }
    if (order.deliveryOtp != null && order.deliveryOtp!.isNotEmpty) {
      final expiresAt = order.deliveryOtpExpiresAt;
      if (expiresAt == null || expiresAt.isAfter(now)) {
        return order.deliveryOtp;
      }
    }
    return null;
  }

  String _otpExpiryLabel() {
    DateTime? expiresAt;
    if (socketOtpData != null) {
      final str = socketOtpData!['expiresAt']?.toString();
      expiresAt = str != null ? DateTime.tryParse(str)?.toLocal() : null;
    }
    expiresAt ??= order.deliveryOtpExpiresAt;
    if (expiresAt == null) return '';
    final h = expiresAt.hour.toString().padLeft(2, '0');
    final m = expiresAt.minute.toString().padLeft(2, '0');
    return 'Valid until $h:$m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String rawId = order.id;
    final String orderId = rawId.length > 8
        ? rawId.substring(rawId.length - 8).toUpperCase()
        : rawId.toUpperCase();
    final String status = order.status;
    final double total = order.total;

    // Items
    final String itemsSummary = order.items.isNotEmpty
        ? order.items.map((i) => i.name).join(', ')
        : 'See details';

    // Delivery address
    final String deliveryAddress = order.deliveryAddress;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
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
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TrackOrderPage(
                orderId: order.id,
                status: status,
                deliveryAddress: order.deliveryAddressMap,
                deliveryAddressStr: order.deliveryAddressStr,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header (Matching Screenshot) ─────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Order #$orderId',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.black87)),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Order Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: order.isSubscription
                              ? AppColors.primaryDark.withValues(alpha: 0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: order.isSubscription
                                  ? AppColors.primaryDark.withValues(alpha: 0.3)
                                  : Colors.grey.shade300),
                        ),
                        child: Text(
                          (order.orderType ?? 'One-time').toUpperCase(),
                          style: TextStyle(
                              color: order.isSubscription
                                  ? AppColors.primaryDark
                                  : Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                              fontSize: 9),
                        ),
                      ),
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFE2F5E9), // Light green for status
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _formatStatus(status),
                          style: const TextStyle(
                              color: Color(0xFF2E7D32), // Dark green text
                              fontWeight: FontWeight.bold,
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const Divider(height: 32, thickness: 1, color: Color(0xFFF3F4F6)),

              // ── Item Row ────────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product image with fallback
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                      child: _buildItemImage(order),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(itemsSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF1E293B))),
                        const SizedBox(height: 4),
                        Text(
                          'Total Quantity: ${order.items.fold(0, (sum, i) => sum + i.quantity)}',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13),
                        ),
                        if (order.deliverySlot != null &&
                            order.deliverySlot!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Slot: ${order.deliverySlot}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Text(
                'Placed: ${order.date.toLocal().toString().substring(0, 16).replaceAll('T', ', ')}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),

              const SizedBox(height: 16),

              // ── Plant Section (Added) ──────────────────────────────────
              if (order.plantName.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4), // Very light green
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF00ACC1).withValues(alpha: 0.2),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.factory_outlined,
                          color: Color(0xFF16A34A), size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Plant / Retailer',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF16A34A),
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(order.plantName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black87)),
                          ],
                        ),
                      ),
                      if (order.plantPhone.isNotEmpty)
                        IconButton(
                          icon:
                              const Icon(Icons.call, color: Color(0xFF16A34A)),
                          onPressed: () async {
                            final Uri uri =
                                Uri.parse('tel:${order.plantPhone}');
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            }
                          },
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          tooltip: 'Call Plant',
                        ),
                    ],
                  ),
                ),
              ],

              // ── Location Section (Matching Screenshot) ──────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF00ACC1).withValues(alpha: 0.2),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: Colors.grey, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Delivery Address',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Builder(
                            builder: (context) {
                              final addr = order.deliveryAddressMap;
                              final displayStr = order.deliveryAddressStr;
                              if (addr == null) {
                                String street = displayStr ?? '';
                                String city = '';
                                String state = '';
                                String pincode = '';
                                String label = '';
                                String fullName = '';
                                String phone = '';

                                if (street.isNotEmpty) {
                                  try {
                                    final cartProvider =
                                        CartProviderScope.of(context);
                                    final matched =
                                        cartProvider.addresses.firstWhere(
                                      (a) =>
                                          a.street.toLowerCase().trim() ==
                                              street.toLowerCase().trim() ||
                                          street.toLowerCase().contains(
                                              a.street.toLowerCase().trim()),
                                      orElse: () => UserAddress(
                                          id: '',
                                          title: '',
                                          street: '',
                                          details: ''),
                                    );
                                    if (matched.id.isNotEmpty) {
                                      street = matched.street;
                                      label = matched.title;
                                      fullName = matched.fullName;
                                      final parts = matched.details.split(',');
                                      if (parts.isNotEmpty) {
                                        city = parts[0].trim();
                                      }
                                      if (parts.length > 1) {
                                        final stateParts =
                                            parts[1].trim().split(' ');
                                        if (stateParts.length > 1) {
                                          pincode = stateParts.last;
                                          state = stateParts
                                              .sublist(0, stateParts.length - 1)
                                              .join(' ');
                                        } else {
                                          state = parts[1].trim();
                                        }
                                      }
                                    }
                                  } catch (_) {}
                                }

                                if (city.isNotEmpty ||
                                    state.isNotEmpty ||
                                    pincode.isNotEmpty) {
                                  final user = ref.read(currentUserProvider);
                                  if (fullName.isEmpty && user != null) {
                                    fullName = user.fullName;
                                  }
                                  if (fullName.isEmpty) {
                                    fullName = 'Unknown Recipient';
                                  }
                                  if (phone.isEmpty && user != null) {
                                    phone = user.phoneNumber;
                                  }

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (label.isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFCFFAFE),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            label.toUpperCase(),
                                            style: const TextStyle(
                                              color: Color(0xFF06B6D4),
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                      ],
                                      if (fullName.isNotEmpty) ...[
                                        Text(
                                          fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFF4B5563),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                      ],
                                      if (street.isNotEmpty) ...[
                                        Text(
                                          street,
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                            height: 1.3,
                                          ),
                                        ),
                                      ],
                                      if (city.isNotEmpty ||
                                          state.isNotEmpty ||
                                          pincode.isNotEmpty)
                                        Text(
                                          '$city${city.isNotEmpty ? ", " : ""}$state $pincode',
                                          style: const TextStyle(
                                            color: Color(0xFF9CA3AF),
                                            fontSize: 11,
                                            height: 1.2,
                                          ),
                                        ),
                                      if (phone.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          phone,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                            color: Color(0xFF1A1A1A),
                                          ),
                                        ),
                                      ],
                                    ],
                                  );
                                }

                                return Text(
                                  displayStr ?? 'Your delivery address',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                      color: Colors.black87),
                                );
                              }

                              final user = ref.read(currentUserProvider);
                              String label =
                                  addr['label'] ?? addr['title'] ?? '';

                              String fullName =
                                  addr['fullName'] ?? addr['name'] ?? '';
                              if (fullName.toString().trim().isEmpty &&
                                  user != null) {
                                fullName = user.fullName;
                              }
                              if (fullName.isEmpty) {
                                fullName = 'Unknown Recipient';
                              }

                              String street = addr['fullAddress'] ??
                                  addr['address'] ??
                                  addr['street'] ??
                                  addr['flat'] ??
                                  addr['houseNo'] ??
                                  '';
                              String city = addr['city'] ?? '';
                              String state = addr['state'] ?? '';
                              String pincode = addr['pincode'] ?? '';

                              // Robust dynamic matcher to recover missing fields from user's saved addresses
                              if (street.isEmpty ||
                                  city.isEmpty ||
                                  state.isEmpty ||
                                  pincode.isEmpty ||
                                  label.isEmpty) {
                                try {
                                  final cartProvider =
                                      CartProviderScope.of(context);
                                  // 1. Try matching by exact street name
                                  var matched =
                                      cartProvider.addresses.firstWhere(
                                    (a) =>
                                        street.isNotEmpty &&
                                        a.street.toLowerCase().trim() ==
                                            street.toLowerCase().trim(),
                                    orElse: () => UserAddress(
                                        id: '',
                                        title: '',
                                        street: '',
                                        details: ''),
                                  );

                                  // 2. Try matching by label
                                  if (matched.id.isEmpty && label.isNotEmpty) {
                                    matched = cartProvider.addresses.firstWhere(
                                      (a) =>
                                          a.title.toLowerCase().trim() ==
                                          label.toLowerCase().trim(),
                                      orElse: () => UserAddress(
                                          id: '',
                                          title: '',
                                          street: '',
                                          details: ''),
                                    );
                                  }

                                  // 3. Try matching by pincode/city
                                  if (matched.id.isEmpty &&
                                      pincode.isNotEmpty) {
                                    matched = cartProvider.addresses.firstWhere(
                                      (a) => a.details.toLowerCase().contains(
                                          pincode.toLowerCase().trim()),
                                      orElse: () => UserAddress(
                                          id: '',
                                          title: '',
                                          street: '',
                                          details: ''),
                                    );
                                  }

                                  // If matched address found, dynamically recover missing fields
                                  if (matched.id.isNotEmpty) {
                                    if (label.isEmpty) label = matched.title;
                                    if (street.isEmpty) street = matched.street;
                                    if (fullName.isEmpty ||
                                        fullName == 'Unknown Recipient') {
                                      fullName = matched.fullName.isNotEmpty
                                          ? matched.fullName
                                          : fullName;
                                    }

                                    final parts = matched.details.split(',');
                                    if (city.isEmpty && parts.isNotEmpty) {
                                      city = parts[0].trim();
                                    }
                                    if (state.isEmpty || pincode.isEmpty) {
                                      if (parts.length > 1) {
                                        final stateParts =
                                            parts[1].trim().split(' ');
                                        if (stateParts.length > 1) {
                                          if (pincode.isEmpty) {
                                            pincode = stateParts.last;
                                          }
                                          if (state.isEmpty) {
                                            state = stateParts
                                                .sublist(
                                                    0, stateParts.length - 1)
                                                .join(' ');
                                          }
                                        } else {
                                          if (state.isEmpty) {
                                            state = parts[1].trim();
                                          }
                                        }
                                      }
                                    }
                                  }
                                } catch (_) {}
                              }

                              String phone =
                                  addr['phone'] ?? addr['phoneNumber'] ?? '';
                              if (phone.toString().trim().isEmpty &&
                                  user != null) {
                                phone = user.phoneNumber;
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (label.toString().isNotEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFCFFAFE),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        label.toString().toUpperCase(),
                                        style: const TextStyle(
                                          color: Color(0xFF06B6D4),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                  ],
                                  if (fullName.toString().isNotEmpty) ...[
                                    Text(
                                      fullName.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFF4B5563),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                  ],
                                  if (street.toString().isNotEmpty) ...[
                                    Text(
                                      street.toString(),
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                  if (city.toString().isNotEmpty ||
                                      state.toString().isNotEmpty ||
                                      pincode.toString().isNotEmpty)
                                    Text(
                                      '${city.toString()}${city.toString().isNotEmpty ? ", " : ""}${state.toString()} ${pincode.toString()}',
                                      style: const TextStyle(
                                        color: Color(0xFF9CA3AF),
                                        fontSize: 11,
                                        height: 1.2,
                                      ),
                                    ),
                                  if (phone.toString().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      phone.toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF1A1A1A),
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Delivery OTP Banner ───────────────────────────────────────────
              Builder(builder: (context) {
                final otp = _resolvedOtp();
                if (otp == null) return const SizedBox.shrink();
                final expiryLabel = _otpExpiryLabel();
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0891B2), Color(0xFF06B6D4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lock_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Share this OTP with the rider',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: otp.split('').map((digit) => Container(
                          width: 48,
                          height: 54,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            digit,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0891B2),
                            ),
                          ),
                        )).toList(),
                      ),
                      if (expiryLabel.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          expiryLabel,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),

              // ── Price & View Details ───────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${total.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 22,
                            color: Colors.black)),
                    const SizedBox(height: 4),
                    Text('View Details',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                            decoration: TextDecoration.underline)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'PENDING';
      case 'accepted':
      case 'working':
        return 'ACCEPTED';
      case 'rider assigned':
      case 'rider_assigned':
        return 'RIDER ASSIGNED';
      case 'rider accepted':
      case 'rider_accepted':
        return 'RIDER ACCEPTED';
      case 'pickedup':
      case 'picked_up':
        return 'PICKED UP';
      case 'ontheway':
      case 'out_for_delivery':
      case 'out for delivery':
        return 'OUT FOR DELIVERY';
      case 'delivered':
        return 'DELIVERED';
      default:
        return status.toUpperCase();
    }
  }

  Widget _buildItemImage(UserOrder order) {
    final String imageUrl =
        order.items.isNotEmpty ? order.items.first.image : '';

    if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fallbackImage(),
      );
    }

    return _fallbackImage();
  }

  Widget _fallbackImage() {
    return Image.asset(
      AppImages.waterBottle,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.water_drop, color: Color(0xFF0891B2), size: 32),
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  const _ShimmerBox();

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

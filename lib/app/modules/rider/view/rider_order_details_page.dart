import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/rider_service.dart';
import '../../../data/services/socket_service.dart';
import 'rider_home_page.dart';

final orderDetailsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, orderId) async {
  final result = await ref.read(riderServiceProvider).getOrderDetails(orderId);
  return result;
});

class RiderOrderDetailsPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;
  final String? orderId;

  const RiderOrderDetailsPage({
    super.key,
    this.order = const {},
    this.orderId,
  });

  @override
  ConsumerState<RiderOrderDetailsPage> createState() =>
      _RiderOrderDetailsPageState();
}

class _RiderOrderDetailsPageState extends ConsumerState<RiderOrderDetailsPage> {
  /// Live-updated status from Socket.IO (falls back to the initial order status)
  late String _liveStatus;
  Map<String, dynamic>? _fetchedOrder;
  SocketService? _socket;

  // ── Cancellation flow state ───────────────────────────────────────────────
  bool _cancelInitiated = false;
  int _countdownSeconds = 300; // 5 minutes
  Timer? _countdownTimer;
  bool _isCancelLoading = false;

  @override
  void initState() {
    super.initState();
    _liveStatus = widget.order['status']?.toString() ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSocket());
  }

  void _initSocket() {
    final orderId = widget.order['orderId']?.toString() ?? '';
    if (orderId.isEmpty) return;

    // Save reference so dispose() can use it without touching ref
    _socket = ref.read(socketServiceProvider);
    // Join the order-specific room for real-time updates
    _socket!.joinOrderRoom(orderId);

    // Listen for status changes emitted by the server
    _socket!.onOrderUpdate((data) {
      if (!mounted) return;
      final incomingId = data?['orderId']?.toString() ?? '';
      if (incomingId != orderId && incomingId.isNotEmpty) {
        return; // not our order
      }

      final newStatus = data?['status']?.toString() ?? '';
      if (newStatus.isNotEmpty && newStatus != _liveStatus) {
        setState(() => _liveStatus = newStatus);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('📍 Status updated: $newStatus'),
          backgroundColor: AppColors.accentGreen,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ));
      }

      // Also refresh the home list so it stays in sync
      ref.invalidate(riderOrdersProvider);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    final orderId = widget.order['orderId']?.toString() ?? '';
    if (orderId.isNotEmpty) {
      _socket?.leaveOrderRoom(orderId);
      _socket?.offOrderUpdate();
    }
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_countdownSeconds > 0) {
          _countdownSeconds--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _showCancelDialog(String cancelOrderId) async {
    final reasons = [
      'Customer not home',
      'Refused delivery',
      'Wrong address',
      'Customer unreachable',
      'Other',
    ];
    String selectedReason = reasons.first;
    final TextEditingController otherController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Cancel Order',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select a reason:',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 10),
              ...reasons.map((r) => GestureDetector(
                    onTap: () => setDialogState(() => selectedReason = r),
                    child: Row(
                      children: [
                        Radio<String>(
                          value: r,
                          groupValue: selectedReason,
                          activeColor: AppColors.accentGreen,
                          onChanged: (v) =>
                              setDialogState(() => selectedReason = v ?? r),
                        ),
                        Text(r, style: const TextStyle(fontSize: 14)),
                      ],
                    ),
                  )),
              if (selectedReason == 'Other') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: otherController,
                  decoration: const InputDecoration(
                    hintText: 'Describe the reason...',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  maxLines: 2,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Initiate Cancel',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final reason = selectedReason == 'Other'
        ? otherController.text.trim().isNotEmpty
            ? otherController.text.trim()
            : 'Other'
        : selectedReason;

    setState(() => _isCancelLoading = true);
    final res = await ref
        .read(riderServiceProvider)
        .initiateCancellation(orderId: cancelOrderId, reason: reason);
    if (!mounted) return;
    setState(() => _isCancelLoading = false);

    if (res['success'] == true) {
      setState(() {
        _cancelInitiated = true;
        _countdownSeconds = 300;
      });
      _startCountdown();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Cancellation timer started. Wait 5 minutes.'),
        backgroundColor: Colors.orange.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } else {
      final msg = res['message']?.toString() ?? 'Failed to initiate cancellation.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _confirmCancellation(String cancelOrderId) async {
    setState(() => _isCancelLoading = true);
    final res = await ref
        .read(riderServiceProvider)
        .confirmCancellation(orderId: cancelOrderId);
    if (!mounted) return;
    setState(() => _isCancelLoading = false);

    if (res['success'] == true) {
      ref.invalidate(riderOrdersProvider);
      Navigator.of(context).pop();
    } else {
      final msg = res['message']?.toString() ?? 'Could not confirm cancellation.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _callCustomer(String phone) async {
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No phone number available')));
      return;
    }
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open dialer for $phone')));
    }
  }

  Future<void> _openMaps(String address) async {
    if (address.isEmpty || address == 'N/A') {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No address available')));
      return;
    }
    // Using 'dir' action with destination automatically sets the rider's current location as the source
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open Maps')));
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> order = widget.order;

    if (order.isEmpty && widget.orderId != null) {
      final orderAsync = ref.watch(orderDetailsProvider(widget.orderId!));
      return orderAsync.when(
        data: (fetchedMap) {
          order = fetchedMap;
          if (order.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: const Text('Order Error')),
              body: const Center(child: Text('Order not found')),
            );
          }
          return _buildOrderDetails(context, order);
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator(color: AppColors.accentGreen)),
        ),
        error: (err, stack) => Scaffold(
          body: Center(child: Text('Error: $err')),
        ),
      );
    }

    return _buildOrderDetails(context, order);
  }

  Widget _buildOrderDetails(BuildContext context, Map<String, dynamic> order) {
    final items = (order['items'] as List<dynamic>?) ?? [];
    final user = order['user'];
    final customerName = (user is Map)
        ? (user['fullName']?.toString() ??
            user['name']?.toString() ??
            'Customer')
        : 'Customer';
    final customerPhone = (user is Map)
        ? (user['phoneNumber']?.toString() ?? user['phone']?.toString() ?? '')
        : '';
    final deliveryAddressMap = order['deliveryAddress'];
    String deliveryAddress = 'N/A';
    if (deliveryAddressMap is Map) {
      final name = deliveryAddressMap['fullName'] ?? deliveryAddressMap['name'] ?? '';
      final street = deliveryAddressMap['fullAddress'] ?? deliveryAddressMap['address'] ?? deliveryAddressMap['street'] ?? '';
      final city = deliveryAddressMap['city'] ?? '';
      final state = deliveryAddressMap['state'] ?? '';
      final pincode = deliveryAddressMap['pincode'] ?? '';
      
      List<String> parts = [];
      if (street.toString().isNotEmpty) parts.add(street.toString());
      if (city.toString().isNotEmpty) parts.add(city.toString());
      if (state.toString().isNotEmpty) parts.add(state.toString());
      if (pincode.toString().isNotEmpty) parts.add(pincode.toString());
      
      deliveryAddress = parts.isNotEmpty ? parts.join(', ') : 'N/A';
      if (name.toString().isNotEmpty) {
        deliveryAddress = '$name\n$deliveryAddress';
      }
    } else if (deliveryAddressMap != null) {
      deliveryAddress = deliveryAddressMap.toString();
    }

    // Use live status from socket, falls back to initial order status
    final status = _liveStatus.isNotEmpty
        ? _liveStatus
        : (order['status']?.toString() ?? '');
    final orderId = order['orderId']?.toString() ?? '';
    final shortId = orderId.length >= 6
        ? orderId.substring(orderId.length - 6).toUpperCase()
        : orderId.toUpperCase();
    final paymentType = (order['paymentMethod'] ??
            order['paymentType'] ??
            order['payment_method'] ??
            'N/A')
        .toString();
    final instructions = order['deliveryInstructions']?.toString() ??
        order['instructions']?.toString() ??
        'None';

    final retailer = order['retailer'] ?? (items.isNotEmpty ? items.first['retailer'] : null);
    String plantName = '';
    String plantPhone = '';
    if (retailer is Map) {
      plantName = retailer['businessDetails']?['storeDisplayName'] ?? 
                  retailer['fullName'] ?? 
                  retailer['name'] ?? 
                  '';
      plantPhone = retailer['phoneNumber'] ?? retailer['phone'] ?? '';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text('#$shortId',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Quick Actions ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.phone_rounded,
                    label: 'Call Customer',
                    color: Colors.blue,
                    onTap: () => _callCustomer(customerPhone),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.map_rounded,
                    label: 'Open Maps',
                    color: Colors.orange,
                    onTap: () => _openMaps(deliveryAddress),
                  ),
                ),
              ],
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0),

            const SizedBox(height: 20),

            // ── Customer Info ─────────────────────────────────────────────
            _SectionCard(
              title: 'Customer',
              child: Column(
                children: [
                  _InfoRow(
                      icon: Icons.person_rounded,
                      label: 'Name',
                      value: customerName),
                  if (customerPhone.isNotEmpty)
                    _InfoRow(
                        icon: Icons.phone_rounded,
                        label: 'Phone',
                        value: customerPhone),
                  _InfoRow(
                    icon: Icons.location_on_rounded,
                    label: 'Address',
                    value: deliveryAddress,
                    iconColor: Colors.red,
                  ),
                  if (instructions != 'None')
                    _InfoRow(
                        icon: Icons.notes_rounded,
                        label: 'Instructions',
                        value: instructions),
                ],
              ),
            ).animate(delay: 80.ms).fadeIn().slideY(begin: 0.1, end: 0),

            const SizedBox(height: 16),

            // ── Plant Info ─────────────────────────────────────────────
            if (plantName.isNotEmpty)
              _SectionCard(
                title: 'Plant / Retailer',
                child: Column(
                  children: [
                    _InfoRow(
                        icon: Icons.factory_outlined,
                        label: 'Name',
                        value: plantName),
                    if (plantPhone.isNotEmpty)
                      _InfoRow(
                          icon: Icons.phone_android_rounded,
                          label: 'Phone',
                          value: plantPhone),
                  ],
                ),
              ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.1, end: 0),

            const SizedBox(height: 16),

            // ── Order Info ────────────────────────────────────────────────
            _SectionCard(
              title: 'Order Info',
              child: Column(
                children: [
                  _InfoRow(
                      icon: Icons.tag_rounded,
                      label: 'Order ID',
                      value: '#$shortId'),
                  _InfoRow(
                      icon: Icons.payment_rounded,
                      label: 'Payment',
                      value: paymentType),
                  _InfoRow(
                      icon: Icons.info_outline_rounded,
                      label: 'Status',
                      value: status.toUpperCase()),
                  const Divider(height: 24),
                  _InfoRow(
                    icon: Icons.currency_rupee_rounded,
                    label: 'Order Total Money',
                    value: '₹${(order['totalAmount'] ?? order['total'] ?? 0).toString()}',
                    valueColor: AppColors.accentGreen,
                    isBold: true,
                  ),
                ],
              ),
            ).animate(delay: 120.ms).fadeIn().slideY(begin: 0.1, end: 0),

            const SizedBox(height: 16),

            // ── Items ─────────────────────────────────────────────────────
            if (items.isNotEmpty)
              _SectionCard(
                title: 'Items (${items.length} Type • Total ${items.fold(0, (sum, i) => sum + (int.tryParse(i['quantity']?.toString() ?? '1') ?? 1))} qty)',
                child: Column(
                  children: items.map((item) {
                    final product = item['product'];
                    final name = (product is Map)
                        ? (product['name']?.toString() ?? 'Item')
                        : (item['name']?.toString() ?? 'Item');
                    final qty = item['quantity']?.toString() ?? '1';
                    final price = item['price']?.toString() ?? '';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                                color: const Color(0xFFF1F4F8),
                                borderRadius: BorderRadius.circular(8)),
                            child: Center(
                                child: Text(qty,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500))),
                          if (price.isNotEmpty)
                            Text('₹$price',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.accentGreen)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ).animate(delay: 160.ms).fadeIn().slideY(begin: 0.1, end: 0),

            const SizedBox(height: 24),

            // ── Cancellation Flow ──────────────────────────────────────────
            if (!['delivered', 'cancelled', 'rejected', 'completed']
                .contains(status.toLowerCase())) ...[
              const SizedBox(height: 8),
              _buildCancelSection(order),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Cancel section ──────────────────────────────────────────────────────────

  Widget _buildCancelSection(Map<String, dynamic> order) {
    final cancelOrderId = order['_id']?.toString() ??
        order['id']?.toString() ??
        widget.orderId ??
        order['orderId']?.toString() ??
        '';

    if (cancelOrderId.isEmpty) return const SizedBox.shrink();

    final mins = (_countdownSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_countdownSeconds % 60).toString().padLeft(2, '0');
    final timerDone = _countdownSeconds == 0;

    return _SectionCard(
      title: 'Cancel Order',
      child: _isCancelLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(color: Colors.red),
              ),
            )
          : !_cancelInitiated
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Cancelling requires a 5-minute wait to prevent accidental cancellations.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _showCancelDialog(cancelOrderId),
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                      label: const Text('Cancel Order',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer_outlined,
                            color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          timerDone
                              ? 'Timer complete — you can confirm now.'
                              : 'Wait $mins:$secs before confirming.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: timerDone
                                ? AppColors.accentGreen
                                : Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: timerDone
                          ? () => _confirmCancellation(cancelOrderId)
                          : null,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Confirm Cancellation',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ── Helpers ────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey,
                  letterSpacing: 0.5)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color? valueColor;
  final bool isBold;
  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.iconColor = Colors.grey,
      this.valueColor,
      this.isBold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold)),
                Text(value,
                    style: TextStyle(
                        fontSize: isBold ? 15 : 13,
                        color: valueColor ?? const Color(0xFF1A1A1A),
                        fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickActionButton(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

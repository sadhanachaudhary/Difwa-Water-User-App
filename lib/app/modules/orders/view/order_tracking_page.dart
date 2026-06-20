import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../data/services/order_service.dart';
import '../../../data/services/socket_service.dart';
import '../../../data/services/db_service.dart';
import '../../../data/models/food_models.dart';
import '../../auth/provider/auth_provider.dart';

class OrderTrackingPage extends ConsumerStatefulWidget {
  final Map<String, dynamic> order;

  const OrderTrackingPage({super.key, required this.order});

  @override
  ConsumerState<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends ConsumerState<OrderTrackingPage> {
  late Map<String, dynamic> _order;
  List<dynamic> _statusHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _order = Map<String, dynamic>.from(widget.order);
    _statusHistory = List<dynamic>.from(_order['statusHistory'] ?? []);

    _loadOrderDetails();
    _setupSocket();
  }

  Future<void> _loadOrderDetails() async {
    final mongoId = _order['_id']?.toString() ?? '';
    if (mongoId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final service = ref.read(orderServiceProvider);
      Map<String, dynamic> freshData = await service.trackOrder(mongoId);

      // Fallback: some order types (e.g. subscription) may not be on /track
      if (freshData.isEmpty) {
        freshData = await service.getOrderById(mongoId);
      }

      if (freshData.isNotEmpty && mounted) {
        setState(() {
          _order = freshData;
          _statusHistory = List<dynamic>.from(_order['statusHistory'] ?? []);
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupSocket() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final orderId = _order['orderId']?.toString() ?? '';
      if (orderId.isNotEmpty) {
        final socket = ref.read(socketServiceProvider);
        socket.joinOrderRoom(orderId);
        socket.onOrderUpdate((data) {
          if (!mounted) return;
          setState(() {
            _order['status'] = data['status'] ?? _order['status'];
            if (data['statusHistory'] != null) {
              _statusHistory = List<dynamic>.from(data['statusHistory']);
            } else {
              // Append the new status entry locally
              _statusHistory.add({
                'status': data['status'],
                'role': 'system',
                'timestamp': DateTime.now().toIso8601String(),
              });
            }
          });
        });
      }
    });
  }

  @override
  void dispose() {
    final orderId = _order['orderId']?.toString() ?? '';
    if (orderId.isNotEmpty) {
      ref.read(socketServiceProvider).leaveOrderRoom(orderId);
      ref.read(socketServiceProvider).offEvent('orderUpdate');
    }
    super.dispose();
  }

  // All possible statuses in order
  static const _allStatuses = [
    'Pending',
    'Accepted',
    'Rider Assigned',
    'Rider Accepted',
    'Out for Delivery',
    'Delivered',
  ];

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'retailer':
        return const Color(0xFF06B6D4);
      case 'rider':
        return const Color(0xFFE67E22);
      case 'user':
        return const Color(0xFF3498DB);
      case 'system':
        return const Color(0xFF95A5A6);
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    final s = status.toLowerCase();
    if (s.contains('pending') || s.contains('placed')) {
      return Icons.receipt_long_rounded;
    }
    if (s.contains('accepted') && s.contains('rider')) {
      return Icons.delivery_dining_rounded;
    }
    if (s.contains('accepted')) return Icons.check_circle_rounded;
    if (s.contains('processing') || s.contains('preparing')) {
      return Icons.restaurant_rounded;
    }
    if (s.contains('shipped') || s.contains('out for delivery')) {
      return Icons.moped_rounded;
    }
    if (s.contains('delivered')) return Icons.home_rounded;
    return Icons.radio_button_checked_rounded;
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts.toString()).toLocal();
      return DateFormat('dd MMM, hh:mm a').format(dt);
    } catch (_) {
      return ts.toString();
    }
  }

  Widget _buildRoleBadge(String role) {
    if (role == 'system') return const SizedBox();
    final color = _roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'delivered':
        color = const Color(0xFF06B6D4);
        break;
      case 'cancelled':
        color = Colors.red;
        break;
      case 'out for delivery':
      case 'rider accepted':
        color = const Color(0xFFE67E22);
        break;
      default:
        color = const Color(0xFF0891B2); // Dark green or grey
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  bool get _canCancel {
    final status = (_order['status']?.toString() ?? 'Pending').toLowerCase().trim();
    return status != 'delivered' &&
           status != 'completed' &&
           status != 'cancelled' &&
           status != 'canceled';
  }

  bool get _isCancelled {
    final status = (_order['status']?.toString() ?? 'Pending').toLowerCase().trim();
    return status == 'cancelled' || status == 'canceled';
  }

  void _showCancelDialog() {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final textController = TextEditingController();
    bool isSubmitting = false;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'Cancel Order',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Are you sure you want to cancel this order? Please tell us why:',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: textController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Enter reason (e.g., I changed my mind)',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF0891B2), width: 1.5),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please provide a reason';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Go Back', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (formKey.currentState?.validate() ?? false) {
                            setStateDialog(() {
                              isSubmitting = true;
                            });

                            final reason = textController.text.trim();
                            final mongoId = _order['_id']?.toString() ?? '';
                            final result = await ref
                                .read(orderServiceProvider)
                                .cancelOrder(orderId: mongoId, reason: reason);

                            if (!mounted) return;

                            if (result['success'] == true) {
                              Navigator.pop(dialogContext); // close dialog

                              // Show appropriate snackbar based on scenario
                              final scenario = result['scenario']?.toString();
                              final message = result['message']?.toString() ?? 'Order cancelled successfully';

                              if (scenario == 'instant_refund') {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: const Text('Order cancelled. Refund added to wallet!'),
                                    backgroundColor: Colors.green.shade600,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else if (scenario == 'pending_approval') {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: const Text('Order cancelled. Refund is under admin review.'),
                                    backgroundColor: Colors.orange.shade800,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: Text(message),
                                    backgroundColor: Colors.cyan.shade800,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }

                              // Refresh active order list provider
                              try {
                                ref.read(activeOrdersProvider.notifier).refresh();
                              } catch (e) {
                                debugPrint('Error refreshing active orders provider: $e');
                              }

                              // Update local state to trigger UI update
                              setState(() {
                                _order['status'] = 'Cancelled';
                                _statusHistory.add({
                                  'status': 'Cancelled',
                                  'role': 'user',
                                  'timestamp': DateTime.now().toIso8601String(),
                                });
                              });
                            } else {
                              setStateDialog(() {
                                isSubmitting = false;
                              });
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(result['message'] ?? 'Failed to cancel order'),
                                  backgroundColor: Colors.red.shade600,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Cancel Order', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0891B2)),
        ),
      );
    }

    final status = _order['status'] ?? 'Pending';
    final items = _order['items'] as List<dynamic>? ?? [];

    String subtitle = '';
    if (items.isNotEmpty) {
      if (items.length == 1) {
        final item = items.first;
        final product = item['product'];
        final name = (product is Map && product['name'] != null)
            ? product['name'].toString()
            : 'Item';
        final q = item['quantity']?.toString() ?? '1';
        subtitle = '${q}x $name';
      } else {
        subtitle = '${items.length} items in this order';
      }
    }

    // Get retailer name if possible
    String shopName = '';
    if (items.isNotEmpty) {
      final item = items.first;
      final retailer = item['retailer'];
      if (retailer is Map) {
        final bizDetails = retailer['businessDetails'];
        if (bizDetails is Map) {
          shopName = bizDetails['storeDisplayName']?.toString() ??
              bizDetails['businessName']?.toString() ??
              '';
        }
      }
    }

    final isSub =
        _order['orderType'] == 'Subscription' || _order['frequency'] != null;
    final frequency = _order['frequency']?.toString() ?? 'Daily';
    final customDaysList = _order['customDays'] as List<dynamic>? ?? [];
    final customDaysStr = customDaysList.join(', ');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Order Details', 
          style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOrderDetails,
          color: const Color(0xFF0891B2),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Information ─────────────────────────────────────────
              const SizedBox(height: 4),
              Text('#${_order['orderId'] ?? _order['_id'] ?? ''}',
                  style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                'Refresh to check the latest update on your order.',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle,
                    style:
                        TextStyle(color: Colors.grey.shade500, fontSize: 16)),
              ],

              if (shopName.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF00ACC1).withValues(alpha: 0.2),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFF06B6D4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.storefront,
                            color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SOLD BY',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              shopName,
                              style: const TextStyle(
                                color: Color(0xFF0891B2),
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(color: Color(0xFFEEEEEE), thickness: 1.5),
              ),

              // ── Current Status ─────────────────────────────────────────────
              const Text('CURRENT STATUS',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 10),
              _buildStatusBadge(status),

              // ── Subscription Schedule ──────────────────────────────────────
              if (isSub) ...[
                const SizedBox(height: 20),
                const Text('SUBSCRIPTION SCHEDULE',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                const SizedBox(height: 8),
                Text(frequency,
                    style: const TextStyle(
                        color: Color(0xFF06B6D4),
                        fontSize: 16,
                        fontWeight: FontWeight.w900)),
                if (customDaysStr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Days: $customDaysStr',
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                ],
              ],

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(color: Color(0xFFEEEEEE), thickness: 1.5),
              ),

              // ── Status History ─────────────────────────────────────────────
              const Text('STATUS HISTORY',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 20),
              _buildTimeline(status),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(color: Color(0xFFEEEEEE), thickness: 1.5),
              ),

              // ── Delivery Address ───────────────────────────────────────────
              const Text('DELIVERY ADDRESS',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 12),
              _buildAddressSection(),

              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Divider(color: Color(0xFFEEEEEE), thickness: 1.5),
              ),

              // ── Items List ────────────────────────────────────────────────
              if (items.isNotEmpty) ...[
                const Text('ITEMS',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey)),
                const SizedBox(height: 12),
                _buildOrderItemsList(items),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: Color(0xFFEEEEEE), thickness: 1.5),
                ),
              ],

              // ── Order Summary (Payment) ─────────────────────────────────────
              _buildOrderSummary(),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    ),
      bottomNavigationBar: _canCancel
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _showCancelDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade600,
                      side: BorderSide(color: Colors.red.shade200, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Cancel Order',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : _isCancelled
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade400,
                          side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Order Cancelled',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : null,
    );
}

  Widget _buildOrderSummary() {
    final totalAmount = _order['totalAmount'];
    final deliveryFee = _order['deliveryFee'];
    final distance = _order['distance'];
    final paymentMethod = _order['paymentMethod']?.toString() ?? '';
    final paymentStatus = _order['paymentStatus']?.toString() ?? '';
    final orderType = _order['orderType']?.toString() ?? '';

    if (totalAmount == null && paymentMethod.isEmpty) return const SizedBox();

    Color payStatusColor;
    switch (paymentStatus.toLowerCase()) {
      case 'paid':
        payStatusColor = const Color(0xFF06B6D4);
        break;
      case 'pending':
        payStatusColor = Colors.orange;
        break;
      case 'failed':
        payStatusColor = Colors.red;
        break;
      default:
        payStatusColor = Colors.grey;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ORDER SUMMARY',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF00ACC1).withValues(alpha: 0.2),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              if (distance != null && (distance as num) > 0) ...[
                _summaryRow(
                  'Distance',
                  '${distance.toString()} km',
                  icon: Icons.motorcycle,
                ),
                const Divider(height: 20, color: Color(0xFFEEEEEE)),
              ],
              if (deliveryFee != null && (deliveryFee as num) > 0) ...[
                _summaryRow(
                  'Delivery Fee',
                  '₹${deliveryFee.toString()}',
                  icon: Icons.local_shipping,
                ),
                const Divider(height: 20, color: Color(0xFFEEEEEE)),
              ],
              if (_order['bottleDepositFee'] != null && (_order['bottleDepositFee'] as num) > 0) ...[
                _summaryRow(
                  'Bottle Deposit Fee',
                  '₹${_order['bottleDepositFee'].toString()}',
                  icon: Icons.cached_rounded,
                ),
                const Divider(height: 20, color: Color(0xFFEEEEEE)),
              ],
              if (_order['hasEmptyBottles'] == true || _order['hasEmptyBottles'] == 'true') ...[
                _summaryRow(
                  'Returned Bottles',
                  '${_order['returnedBottlesCount']?.toString() ?? "0"} Units',
                  icon: Icons.assignment_return_outlined,
                ),
                const Divider(height: 20, color: Color(0xFFEEEEEE)),
              ],
              if (totalAmount != null)
                _summaryRow(
                  'Total Amount',
                  '₹${totalAmount.toString()}',
                  icon: Icons.receipt_long_outlined,
                  valueStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Color(0xFF0891B2)),
                ),
              if (paymentMethod.isNotEmpty) ...[
                const Divider(height: 20, color: Color(0xFFEEEEEE)),
                _summaryRow(
                  'Payment Method',
                  paymentMethod,
                  icon: Icons.account_balance_wallet_outlined,
                ),
              ],
              if (paymentStatus.isNotEmpty) ...[
                const Divider(height: 20, color: Color(0xFFEEEEEE)),
                _summaryRow(
                  'Payment Status',
                  paymentStatus,
                  icon: Icons.verified_outlined,
                  valueStyle: TextStyle(
                      fontWeight: FontWeight.bold, color: payStatusColor),
                ),
              ],
              if (orderType.isNotEmpty) ...[
                const Divider(height: 20, color: Color(0xFFEEEEEE)),
                _summaryRow(
                  'Order Type',
                  orderType,
                  icon: Icons.category_outlined,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value,
      {IconData? icon, TextStyle? valueStyle}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ),
        Text(value,
            style: valueStyle ??
                const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87)),
      ],
    );
  }

  Widget _buildOrderItemsList(List<dynamic> items) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00ACC1).withValues(alpha: 0.2),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: items.map((item) {
          final product = item['product'];
          final name = (product is Map)
              ? (product['name']?.toString() ?? 'Item')
              : (item['name']?.toString() ?? 'Item');
          final qty = item['quantity']?.toString() ?? '1';
          final price = item['price']?.toString() ?? '';
          final isLast = items.indexOf(item) == items.length - 1;

          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      qty,
                      style: const TextStyle(
                        color: Color(0xFF0891B2),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (price.isNotEmpty)
                  Text(
                    '₹$price',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: Color(0xFF0891B2),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAddressSection() {
    final addr = _order['deliveryAddress'];
    if (addr == null || (addr is Map && addr.isEmpty)) {
      return const Padding(
        padding: EdgeInsets.only(left: 36),
        child: Text('No delivery address specified.',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }

    if (addr is String) {
      String street = addr;
      String city = '';
      String state = '';
      String pincode = '';
      String label = '';
      String fullName = '';
      String phone = '';

      if (street.isNotEmpty) {
        try {
          final cartProvider = CartProviderScope.of(context);
          final matched = cartProvider.addresses.firstWhere(
            (a) => a.street.toLowerCase().trim() == street.toLowerCase().trim() ||
                   street.toLowerCase().contains(a.street.toLowerCase().trim()),
            orElse: () => UserAddress(id: '', title: '', street: '', details: ''),
          );
          if (matched.id.isNotEmpty) {
            street = matched.street;
            label = matched.title;
            fullName = matched.fullName;
            final parts = matched.details.split(',');
            if (parts.isNotEmpty) city = parts[0].trim();
            if (parts.length > 1) {
              final stateParts = parts[1].trim().split(' ');
              if (stateParts.length > 1) {
                pincode = stateParts.last;
                state = stateParts.sublist(0, stateParts.length - 1).join(' ');
              } else {
                state = parts[1].trim();
              }
            }
          }
        } catch (_) {}
      }

      if (city.isNotEmpty || state.isNotEmpty || pincode.isNotEmpty) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFCFFAFE),
                  borderRadius: BorderRadius.circular(4),
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
            if (city.isNotEmpty || state.isNotEmpty || pincode.isNotEmpty)
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

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0891B2).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.location_on, color: Color(0xFF0891B2), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              addr,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      );
    }

    final user = ref.read(currentUserProvider);
    String label = addr['label'] ?? addr['title'] ?? '';
    
    String fullName = addr['fullName'] ?? addr['name'] ?? '';
    if (fullName.toString().trim().isEmpty && user != null) {
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
    final landmark = addr['landmark'] ?? '';

    // Robust dynamic matcher to recover missing fields from user's saved addresses
    if (street.isEmpty || city.isEmpty || state.isEmpty || pincode.isEmpty || label.isEmpty) {
      try {
        final cartProvider = CartProviderScope.of(context);
        // 1. Try matching by exact street name
        var matched = cartProvider.addresses.firstWhere(
          (a) => street.isNotEmpty && a.street.toLowerCase().trim() == street.toLowerCase().trim(),
          orElse: () => UserAddress(id: '', title: '', street: '', details: ''),
        );
        
        // 2. Try matching by label
        if (matched.id.isEmpty && label.isNotEmpty) {
          matched = cartProvider.addresses.firstWhere(
            (a) => a.title.toLowerCase().trim() == label.toLowerCase().trim(),
            orElse: () => UserAddress(id: '', title: '', street: '', details: ''),
          );
        }
        
        // 3. Try matching by pincode/city
        if (matched.id.isEmpty && pincode.isNotEmpty) {
          matched = cartProvider.addresses.firstWhere(
            (a) => a.details.toLowerCase().contains(pincode.toLowerCase().trim()),
            orElse: () => UserAddress(id: '', title: '', street: '', details: ''),
          );
        }

        // If matched address found, dynamically recover missing fields
        if (matched.id.isNotEmpty) {
          if (label.isEmpty) label = matched.title;
          if (street.isEmpty) street = matched.street;
          if (fullName.isEmpty || fullName == 'Unknown Recipient') {
            fullName = matched.fullName.isNotEmpty ? matched.fullName : fullName;
          }
          
          final parts = matched.details.split(',');
          if (city.isEmpty && parts.isNotEmpty) city = parts[0].trim();
          if (state.isEmpty || pincode.isEmpty) {
            if (parts.length > 1) {
              final stateParts = parts[1].trim().split(' ');
              if (stateParts.length > 1) {
                if (pincode.isEmpty) pincode = stateParts.last;
                if (state.isEmpty) state = stateParts.sublist(0, stateParts.length - 1).join(' ');
              } else {
                if (state.isEmpty) state = parts[1].trim();
              }
            }
          }
        }
      } catch (_) {}
    }
    
    String phone = addr['phone'] ?? addr['phoneNumber'] ?? '';
    if (phone.toString().trim().isEmpty && user != null) {
      phone = user.phoneNumber;
    }

    if (street.toString().isEmpty && city.toString().isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(left: 36),
        child: Text('Address details not available.',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0891B2).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child:
              const Icon(Icons.location_on, color: Color(0xFF0891B2), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.toString().isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCFFAFE),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label.toString().toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFF06B6D4),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              if (fullName.toString().isNotEmpty) ...[
                Text(
                  fullName.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(height: 4),
              ],
              if (street.toString().isNotEmpty) ...[
                Text(
                  street.toString(),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
              if (city.toString().isNotEmpty || state.toString().isNotEmpty || pincode.toString().isNotEmpty)
                Text(
                  '${city.toString()}${city.toString().isNotEmpty ? ", " : ""}${state.toString()} ${pincode.toString()}',
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              if (landmark.toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Landmark: ${landmark.toString()}',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (phone.toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  phone.toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline(String currentStatus) {
    if (_statusHistory.isNotEmpty) {
      return _buildHistoryTimeline();
    }
    return _buildInferredTimeline(currentStatus);
  }

  Widget _buildHistoryTimeline() {
    // Filter duplicates and sequential identical statuses
    final filteredHistory = <dynamic>[];
    String lastStatus = '';

    for (var item in _statusHistory) {
      final currentStatus = item['status']?.toString() ?? '';
      if (currentStatus != lastStatus) {
        filteredHistory.add(item);
        lastStatus = currentStatus;
      }
    }

    return Column(
      children: filteredHistory.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        final isLast = i == filteredHistory.length - 1;
        final role = item['role']?.toString() ?? 'system';
        final statusText = item['status']?.toString() ?? '';
        final ts = _formatTimestamp(item['timestamp']);
        final color = isLast ? const Color(0xFF06B6D4) : Colors.grey.shade400;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _statusIcon(statusText),
                      size: 16,
                      color: color,
                    ),
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 45,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          color.withValues(alpha: 0.2),
                          Colors.grey.shade100,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(statusText,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: isLast
                                ? const Color(0xFF0891B2)
                                : const Color(0xFF2C3E50))),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (role != 'system') ...[
                          _buildRoleBadge(role),
                          const SizedBox(width: 8),
                        ],
                        Text(ts,
                            style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildInferredTimeline(String currentStatus) {
    final currentIdx = _allStatuses.indexOf(currentStatus);
    return Column(
      children: _allStatuses.asMap().entries.map((entry) {
        final idx = entry.key;
        final s = entry.value;
        if (idx > currentIdx && currentIdx != -1) return const SizedBox();

        final isDone = idx <= currentIdx;
        if (!isDone) return const SizedBox();

        final isLast = idx == currentIdx;

        String role = 'system';
        if (s == 'Accepted' || s == 'Rider Assigned') role = 'retailer';
        if (s == 'Rider Accepted' || s == 'Out for Delivery' || s == 'Delivered') {
          role = 'rider';
        }

        final color = isLast ? const Color(0xFF06B6D4) : Colors.grey.shade400;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _statusIcon(s),
                      size: 16,
                      color: color,
                    ),
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 45,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          color.withValues(alpha: 0.2),
                          Colors.grey.shade100,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s,
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: isLast
                                ? const Color(0xFF0891B2)
                                : const Color(0xFF2C3E50))),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (role != 'system') ...[
                          _buildRoleBadge(role),
                          const SizedBox(width: 8),
                        ],
                        const Text('Done',
                            style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

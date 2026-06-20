import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../data/models/food_models.dart';
import '../../../data/services/order_service.dart';
import '../../../data/services/socket_service.dart';
import '../../auth/provider/auth_provider.dart';
import '../../../data/models/product_model.dart';
import '../../../data/services/db_service.dart';
import '../../../widgets/bounce_widget.dart';
import '../../../core/constants/app_colors.dart';

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupSocket());
  }

  void _setupSocket() {
    final user = ref.read(currentUserProvider);
    if (user == null) return;
    try {
      final socket = ref.read(socketServiceProvider);
      socket.joinUserRoom(user.id);
      socket.onOrderUpdate((data) {
        if (!mounted) return;
        ref.invalidate(myOrdersProvider);
      });
      socket.onRiderAssigned((data) {
        if (!mounted) return;
        HapticFeedback.heavyImpact();
        _showRiderAssignedPopup(data);
      });
    } catch (e) {
      debugPrint('OrdersPage: Socket setup error: $e');
    }
  }

  void _showRiderAssignedPopup(dynamic data) {
    final riderName = data?['rider']?['name'] ?? 'Your Rider';
    final riderPhone = data?['rider']?['phone'] ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF0891B2).withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delivery_dining, size: 48, color: Color(0xFF0891B2)),
              ),
              const SizedBox(height: 20),
              const Text('🎉 Rider Assigned!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              const SizedBox(height: 8),
              Text('$riderName is on the way to pick up your order.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 14)),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF0891B2)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('OK', style: TextStyle(color: Color(0xFF0891B2))))),
            ],
          ),
        ),
      ),
    );
    ref.invalidate(myOrdersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(myOrdersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF0891B2), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Orders', style: TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF0891B2)),
            onPressed: () => ref.invalidate(myOrdersProvider),
          ),
        ],
      ),
      body: ordersAsync.when(
        data: (orders) {
          final filteredOrders = List.of(orders)
            ..sort((a, b) => b.date.compareTo(a.date));
          
          if (filteredOrders.isEmpty) return const Center(child: Text('No orders yet', style: TextStyle(color: Colors.grey)));

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: filteredOrders.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) => _LiveOrderCard(order: filteredOrders[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFF0891B2))),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }
}

class _LiveOrderCard extends StatefulWidget {
  final UserOrder order;
  const _LiveOrderCard({required this.order});
  @override
  State<_LiveOrderCard> createState() => _LiveOrderCardState();
}

class _LiveOrderCardState extends State<_LiveOrderCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _showOrderDetails(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, useSafeArea: true, builder: (context) => _OrderDetailsSheet(order: widget.order));
  }

  void _reorder(BuildContext context) {
    HapticFeedback.mediumImpact();
    final cartProv = CartProviderScope.of(context);
    for (var item in widget.order.items) { cartProv.addToCart(CartItem(id: item.id.isNotEmpty ? item.id : 'reorder_${item.name}', title: item.name, unitPrice: item.price, subtitle: 'Reorder', image: item.image, category: 'Reorder', quantity: item.quantity)); }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to cart for reorder!'), backgroundColor: Color(0xFF06B6D4), behavior: SnackBarBehavior.floating));
    _controller.forward().then((_) => _controller.reverse());
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final String imageUrl = widget.order.items.isNotEmpty ? widget.order.items.first.image : '';
    final bool isDelivered = widget.order.status.toLowerCase() == 'delivered';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showOrderDetails(context),
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(scale: _scaleAnimation.value, child: child),
        child: Container(
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
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(widget.order.items.isNotEmpty ? widget.order.items.first.name : 'Order', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B)))), _buildStatusBadge(widget.order.status)]),
                const Divider(height: 32, thickness: 1, color: Color(0xFFF3F4F6)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 70, height: 70, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(12)), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: imageUrl.isNotEmpty ? Image.network(imageUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => _placeholder()) : _placeholder())),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.order.items.map((i) => '${i.quantity}x ${i.name}').join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B))), const SizedBox(height: 4), _summaryText('Placed: ${dateFormat.format(widget.order.date)}'), if (isDelivered) _summaryText('Delivered: ${dateFormat.format(widget.order.date.add(const Duration(hours: 1)))}'), if (widget.order.riderName.isNotEmpty) _summaryText('Rider: ${widget.order.riderName}')])),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total Bill', style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)), const SizedBox(height: 2), Text('₹${widget.order.total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black))]),
                    BounceWidget(
                      onTap: () => _reorder(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFD4A017), width: 1.5),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: const Text('Reorder', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryText(String t) => Text(t, style: TextStyle(color: Colors.grey.shade600, fontSize: 13));

  Widget _buildStatusBadge(String status) {
    final s = status.toLowerCase();
    Color color;
    Color bg;
    if (s == 'delivered' || s == 'completed') {
      color = const Color(0xFF2E7D32); bg = const Color(0xFFE2F5E9);
    } else if (s == 'cancelled') {
      color = const Color(0xFFB91C1C); bg = const Color(0xFFFEE2E2);
    } else {
      color = const Color(0xFFB45309); bg = const Color(0xFFFEF3C7);
    }
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)));
  }

  Widget _placeholder() => const Center(child: Icon(Icons.water_drop, color: Color(0xFF0891B2), size: 32));
}

class _OrderDetailsSheet extends StatelessWidget {
  final UserOrder order;
  const _OrderDetailsSheet({required this.order});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 100),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 24),
          const Text('Order Details', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          Text('ID: #${order.id.length > 8 ? order.id.substring(order.id.length - 8).toUpperCase() : order.id.toUpperCase()}', style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w600)),
          if (order.plantName.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.factory_outlined,
                    size: 16, color: Color(0xFF0891B2)),
                const SizedBox(width: 8),
                Text(
                  order.plantName,
                  style: const TextStyle(
                      color: Color(0xFF0891B2),
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
          if (order.status.toLowerCase() == 'cancelled') ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.cancel_rounded, size: 16, color: Color(0xFFB91C1C)),
                    const SizedBox(width: 8),
                    Text(
                      order.cancelledBy != null
                          ? 'Cancelled by ${order.cancelledBy![0].toUpperCase()}${order.cancelledBy!.substring(1)}'
                          : 'Order Cancelled',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFB91C1C)),
                    ),
                  ]),
                  if (order.cancelReason != null && order.cancelReason!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Reason: ${order.cancelReason}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF7F1D1D))),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text('ITEMS ORDERED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 12),
          ...order.items.map((item) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)), child: Text('${item.quantity}x', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))), const SizedBox(width: 12), Expanded(child: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1E293B)))), Text('₹${(item.price * item.quantity).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))]))),
          const Divider(height: 40),
          const Text('BILL DETAILS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
          _row('Item Total', order.total - order.deliveryFee - order.bottleDepositFee),
          if (order.bottleDepositFee > 0)
            _row('Bottle Deposit Fee', order.bottleDepositFee),
          if (order.hasEmptyBottles)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Returned Bottles', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  Text('${order.returnedBottlesCount} Units', style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          _row('Delivery Fee', order.deliveryFee),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Grand Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Text('₹${order.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A1A1A)))]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: const Text('GOT IT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
  Widget _row(String l, double v) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(l, style: const TextStyle(color: Colors.grey, fontSize: 14)), Text('₹${v.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600))]));
}

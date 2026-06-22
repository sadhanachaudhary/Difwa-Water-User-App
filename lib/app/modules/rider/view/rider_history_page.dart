import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/rider_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

final deliveryHistoryProvider =
    FutureProvider<List<dynamic>>((ref) async {
  final all = await ref.read(riderServiceProvider).getDeliveryHistory();
  return all.where((o) {
    final s = (o['status']?.toString() ?? '').toLowerCase();
    return s == 'delivered' || s == 'completed' || s == 'cancelled';
  }).toList();
});

class RiderHistoryPage extends ConsumerWidget {
  const RiderHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(deliveryHistoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4EC),
      appBar: AppBar(
        title: const Text('Delivery History',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF0891B2))),
        backgroundColor: const Color(0xFFF0F4EC),
        foregroundColor: const Color(0xFF0891B2),
        elevation: 0,
        centerTitle: true,
        actions: const [],

      ),
      body: historyAsync.when(
        data: (deliveries) {
          if (deliveries.isEmpty) {
            return _buildEmptyState();
          }
          return RefreshIndicator(
            color: AppColors.accentGreen,
            onRefresh: () async => ref.invalidate(deliveryHistoryProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              itemCount: deliveries.length,
              itemBuilder: (context, index) =>
                  _DeliveryHistoryCard(item: deliveries[index]),
            ),
          );
        },
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.accentGreen)),
        error: (err, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('Could not load history',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(deliveryHistoryProvider),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: const BoxDecoration(
              color: Color(0xFFCFFAFE),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history_rounded,
                size: 52, color: AppColors.accentGreen),
          ),
          const SizedBox(height: 20),
          const Text('No Deliveries Yet',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: Color(0xFF0891B2))),
          const SizedBox(height: 8),
          Text('Completed deliveries will appear here',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
        ],
      ),
    );
  }
}

// ── History Card ────────────────────────────────────────────────────────────

class _DeliveryHistoryCard extends StatelessWidget {
  final dynamic item;
  const _DeliveryHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    // ── Order ID ─────────────────────────────────────────────────────────────
    final String rawId =
        (item['orderId'] ?? item['_id'] ?? item['id'] ?? '').toString();
    final String shortId = rawId.length > 8
        ? rawId.substring(rawId.length - 8).toUpperCase()
        : rawId.toUpperCase();

    // ── Date ────────────────────────────────────────────────────────────────
    String displayDate = '';
    final ds = item['deliveredAt']?.toString() ??
        item['updatedAt']?.toString() ??
        item['createdAt']?.toString() ??
        '';
    if (ds.isNotEmpty) {
      try {
        displayDate = DateFormat('MMM dd, yyyy  •  hh:mm a')
            .format(DateTime.parse(ds).toLocal());
      } catch (_) {
        displayDate = ds;
      }
    }

    // ── Customer ─────────────────────────────────────────────────────────────
    final userData = item['user'] ?? item['customer'];
    final String customerName = userData is Map
        ? (userData['fullName'] ?? userData['name'] ?? 'Customer')
        : (item['customerName']?.toString() ?? 'Customer');
    final String customerPhone = userData is Map
        ? (userData['phoneNumber'] ?? userData['phone'] ?? '')
        : (item['phoneNumber']?.toString() ?? '');

    // ── Address ──────────────────────────────────────────────────────────────
    String addressStr = 'Address not available';
    final addrRaw = item['deliveryAddress'] ?? item['address'];
    if (addrRaw is Map) {
      final name = addrRaw['fullName'] ?? addrRaw['name'] ?? '';
      final street = addrRaw['fullAddress'] ?? addrRaw['address'] ?? addrRaw['street'] ?? '';
      final city = addrRaw['city'] ?? '';
      final state = addrRaw['state'] ?? '';
      final pincode = addrRaw['pincode'] ?? '';
      List<String> parts = [];
      if (street.toString().isNotEmpty) parts.add(street.toString());
      if (city.toString().isNotEmpty) parts.add(city.toString());
      if (state.toString().isNotEmpty) parts.add(state.toString());
      if (pincode.toString().isNotEmpty) parts.add(pincode.toString());
      addressStr = parts.isNotEmpty ? parts.join(', ') : 'Address details unavailable';
      if (name.toString().isNotEmpty) {
        addressStr = '$name\n$addressStr';
      }
    } else if (addrRaw is String && addrRaw.isNotEmpty) {
      addressStr = addrRaw;
    }

    // ── Items ────────────────────────────────────────────────────────────────
    final itemsList = item['items'] as List<dynamic>? ?? [];
    final String itemsSummary = itemsList.isNotEmpty
        ? itemsList.map((i) {
            final n = i['name']?.toString() ??
                (i['product'] is Map
                    ? i['product']['name']?.toString()
                    : null) ??
                'Item';
            final q = i['quantity'] ?? i['qty'] ?? 1;
            return '${q}x $n';
          }).join(', ')
        : 'No items info';

    Future<void> launchCall(String phone) async {
      if (phone.isEmpty) return;
      final uri = Uri.parse('tel:$phone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header (ID + Status) ─────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '#$shortId',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Color(0xFF1B2D1F)),
                ),
                _StatusBadge(status: item['status']?.toString() ?? ''),
              ],
            ),
            const SizedBox(height: 12),
            // ── Date Row ─────────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  displayDate,
                  style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.grey.shade100, thickness: 1.5),
            const SizedBox(height: 16),

            // ── Details ──
            Row(
              children: [
                Expanded(
                  child: _Row(
                    icon: Icons.person_outline_rounded,
                    label: 'Customer',
                    value: customerName,
                  ),
                ),
                if (customerPhone.isNotEmpty)
                  IconButton(
                    onPressed: () => launchCall(customerPhone),
                    icon: const Icon(Icons.phone_in_talk_rounded,
                        size: 20, color: AppColors.accentGreen),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFCFFAFE),
                      padding: const EdgeInsets.all(8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (customerPhone.isNotEmpty) ...[
              _Row(
                icon: Icons.phone_android_rounded,
                label: 'Phone Number',
                value: customerPhone,
              ),
              const SizedBox(height: 12),
            ],
            _Row(
              icon: Icons.location_on_outlined,
              label: 'Delivered to',
              value: addressStr,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            _Row(
              icon: Icons.factory_outlined,
              label: 'Plant / Vendor',
              value: (() {
                final items = (item['items'] as List?) ?? [];
                final retailer = item['retailer'] ?? (items.isNotEmpty ? items.first['retailer'] : null);
                if (retailer is Map) {
                  return (retailer['businessDetails']?['storeDisplayName'] ?? 
                          retailer['fullName'] ?? 
                          retailer['name'] ?? 
                          'RETAILER').toString().toUpperCase();
                }
                return 'RETAILER';
              })(),
            ),
            const SizedBox(height: 12),
            _Row(
              icon: Icons.set_meal_outlined,
              label: 'Items',
              value: itemsSummary,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _Row(
              icon: Icons.currency_rupee_rounded,
              label: 'Bill Amount',
              value: '₹${(item['totalAmount'] ?? item['total'] ?? 0).toString()}',
              isBoldValue: true,
            ),

            // ── Cancellation reason (rider-cancelled orders) ─────────────────
            if ((item['status']?.toString().toLowerCase() ?? '') == 'cancelled') ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.cancel_rounded, size: 14, color: Color(0xFFB91C1C)),
                      SizedBox(width: 6),
                      Text('Order Cancelled',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFB91C1C))),
                    ]),
                    if ((item['cancelReason'] ?? item['cancellationReason'] ?? item['reason'])
                            ?.toString()
                            .isNotEmpty ==
                        true) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Reason: ${(item['cancelReason'] ?? item['cancellationReason'] ?? item['reason']).toString()}',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF7F1D1D)),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color color;
    Color bg;
    if (s == 'delivered' || s == 'completed') {
      color = AppColors.accentGreen;
      bg = const Color(0xFFCFFAFE);
    } else if (s == 'cancelled') {
      color = const Color(0xFFB91C1C);
      bg = const Color(0xFFFEE2E2);
    } else {
      color = Colors.orange;
      bg = Colors.orange.withValues(alpha: 0.1);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1.0),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final int maxLines;
  final bool isBoldValue;

  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.maxLines = 1,
    this.isBoldValue = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4EC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF0891B2)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontWeight: isBoldValue ? FontWeight.bold : FontWeight.w600,
                  fontSize: 13,
                  color: isBoldValue ? AppColors.accentGreen : null,
                ),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/state/auth_store.dart';
import '../../../data/services/socket_service.dart';
import '../../../data/services/order_service.dart';
import '../../../data/services/db_service.dart';
import '../../../data/models/food_models.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'order_chat_page.dart';

/// Maps every backend status string → a 0-based step index (0 = just placed).
int _statusToStep(String status) {
  switch (status.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ')) {
    case 'pending':
      return 0;
    case 'accepted':
    case 'working':
    case 'rider assigned':
    case 'riderassigned':
    case 'rider accepted':
      return 1;
    case 'pickedup':
    case 'picked up':
    case 'out for delivery':
    case 'out_for_delivery':
    case 'ontheway':
    case 'on the way':
      return 2;
    case 'delivered':
      return 3;
    default:
      return 0;
  }
}

String _stepLabel(String status) {
  switch (status.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ')) {
    case 'pending':
      return 'Order Placed';
    case 'accepted':
    case 'working':
      return 'Order Accepted';
    case 'rider assigned':
    case 'riderassigned':
      return 'Rider Assigned';
    case 'rider accepted':
      return 'Rider Accepted';
    case 'pickedup':
    case 'picked up':
    case 'out for delivery':
    case 'out_for_delivery':
    case 'ontheway':
    case 'on the way':
      return 'Out for Delivery';
    case 'delivered':
      return 'Delivered!';
    default:
      return status;
  }
}

class TrackOrderPage extends ConsumerStatefulWidget {
  final String orderId;
  final Map<String, dynamic>? deliveryAddress;
  final String? deliveryAddressStr;
  final String? status; // initial status passed from card

  const TrackOrderPage({
    super.key,
    required this.orderId,
    this.deliveryAddress,
    this.deliveryAddressStr,
    this.status,
  });

  @override
  ConsumerState<TrackOrderPage> createState() => _TrackOrderPageState();
}

class _TrackOrderPageState extends ConsumerState<TrackOrderPage>
    with TickerProviderStateMixin {
  // Live order state
  late String _currentStatus;
  String _riderName = '';
  String _riderPhone = '';
  String _plantName = '';
  String _plantPhone = '';
  bool _isLoading = true;
  String _lastRiderUpdate = '';
  late void Function(dynamic) _onRiderLocation;

  // Delivery Address State
  Map<String, dynamic>? _deliveryAddressMap;
  String? _deliveryAddressStr;

  // Socket callbacks
  late void Function(dynamic) _onOrderUpdate;
  late void Function(dynamic) _onRiderAssigned;

  // Pulse animation for the live dot
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status ?? 'Pending';
    _deliveryAddressMap = widget.deliveryAddress;
    _deliveryAddressStr = widget.deliveryAddressStr;
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _fetchOrderDetails();
    _connectSocket();
  }

  Future<void> _fetchOrderDetails() async {
    try {
      final orderData =
          await ref.read(orderServiceProvider).getOrderById(widget.orderId);
      if (!mounted) return;
      if (orderData.isNotEmpty) {
        setState(() {
          _currentStatus = orderData['status']?.toString() ?? _currentStatus;
          final rider = orderData['rider'] ?? orderData['riderId'];
          if (rider is Map) {
            _riderName = rider['fullName'] ?? rider['name'] ?? _riderName;
            _riderPhone = rider['phoneNumber'] ?? rider['phone'] ?? _riderPhone;
          }
          
          final items = orderData['items'] as List?;
          final retailer = orderData['retailer'] ?? (items != null && items.isNotEmpty ? items.first['retailer'] : null);
          if (retailer is Map) {
            _plantName = retailer['businessDetails']?['storeDisplayName'] ?? 
                         retailer['fullName'] ?? 
                         retailer['name'] ?? 
                         _plantName;
            _plantPhone = retailer['phoneNumber'] ?? retailer['phone'] ?? _plantPhone;
          }

          final fetchedAddr = orderData['deliveryAddress'] ?? orderData['address'];
          if (fetchedAddr is Map) {
            _deliveryAddressMap = Map<String, dynamic>.from(fetchedAddr);
          } else if (fetchedAddr is String) {
            _deliveryAddressStr = fetchedAddr;
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching order details: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _connectSocket() {
    final socketService = ref.read(socketServiceProvider);
    socketService.joinOrderRoom(widget.orderId);

    final user = ref.read(currentUserProvider);
    if (user != null) {
      socketService.joinUserRoom(user.id);
    }

    _onOrderUpdate = (data) {
      if (!mounted) return;
      final String statusStr = (data['status'] ?? '').toString();
      final payload = data['data'];

      // Handle Rider Location Change specifically (no-op since map is removed)
      if (statusStr == 'RIDER_LOCATION_UPDATE') {
        return;
      }

      // Handle Status Change
      setState(() {
        if (statusStr.isNotEmpty && statusStr != 'RIDER_LOCATION_UPDATE') {
          _currentStatus = statusStr;
        }

        if (payload is Map) {
          // If the payload has the full order object, extract rider and retailer
          final rider = payload['rider'] ?? payload['riderId'];
          if (rider is Map) {
            _riderName = rider['fullName'] ?? rider['name'] ?? _riderName;
            _riderPhone = rider['phoneNumber'] ?? rider['phone'] ?? _riderPhone;
          }
          
          final items = payload['items'] as List?;
          final retailer = payload['retailer'] ?? (items != null && items.isNotEmpty ? items.first['retailer'] : null);
          if (retailer is Map) {
            _plantName = retailer['businessDetails']?['storeDisplayName'] ?? 
                         retailer['fullName'] ?? 
                         retailer['name'] ?? 
                         _plantName;
            _plantPhone = retailer['phoneNumber'] ?? retailer['phone'] ?? _plantPhone;
          }

          final fetchedAddr = payload['deliveryAddress'] ?? payload['address'];
          if (fetchedAddr is Map) {
            _deliveryAddressMap = Map<String, dynamic>.from(fetchedAddr);
          } else if (fetchedAddr is String) {
            _deliveryAddressStr = fetchedAddr;
          }
        }
      });

      if (statusStr.toLowerCase() == 'delivered') {
        Future.delayed(const Duration(milliseconds: 500), _showDeliverySuccess);
      }
    };

    _onRiderAssigned = (data) {
      if (!mounted) return;
      debugPrint('🛵 Rider assigned/working: ${data['riderName']}');
      setState(() {
        _riderName = data['riderName']?.toString() ?? _riderName;
        _riderPhone = data['riderPhone']?.toString() ?? _riderPhone;
        if (_currentStatus.toLowerCase() == 'pending') {
          _currentStatus = 'Working';
        }
      });
    };

    _onRiderLocation = (data) {
      if (!mounted) return;
      debugPrint('📍 Rider location updated: $data');
      setState(() {
        _lastRiderUpdate = 'Last updated: ${DateFormat('hh:mm a').format(DateTime.now())}';
      });
    };

    socketService.onOrderUpdate(_onOrderUpdate);
    socketService.onRiderAssigned(_onRiderAssigned);
    socketService.onRiderLocation(_onRiderLocation);
  }

  void _showDeliverySuccess() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF06B6D4), size: 72),
            const SizedBox(height: 16),
            const Text('Order Delivered!',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
            const SizedBox(height: 8),
            const Text('Enjoy your fresh water! 💧',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // close dialog
                  Navigator.pop(context); // back to active orders
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0891B2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Back to Home',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    final socketService = ref.read(socketServiceProvider);
    socketService.leaveOrderRoom(widget.orderId);
    socketService.offOrderUpdate(_onOrderUpdate);
    socketService.offRiderAssigned(_onRiderAssigned);
    socketService.offRiderLocation(_onRiderLocation);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _statusToStep(_currentStatus);
    final shortId = widget.orderId.length > 8
        ? '#${widget.orderId.substring(widget.orderId.length - 8).toUpperCase()}'
        : '#${widget.orderId.toUpperCase()}';

    final bool canCancel = _canCancel;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: CircleAvatar(
            backgroundColor: const Color(0xFFF0F4EC),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: const Text('Track Order',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      bottomNavigationBar: canCancel
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
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
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
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
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0891B2)),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
              children: [
                // ── Live Status Header ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
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
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Live pulse dot
                                AnimatedBuilder(
                                  animation: _pulseAnim,
                                  builder: (_, __) => Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Colors.green
                                          .withValues(alpha: _pulseAnim.value),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text('LIVE',
                                    style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _stepLabel(_currentStatus),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22,
                                  letterSpacing: -0.5),
                            ),
                            Text(
                              _getStatusSubtitle(_currentStatus),
                              style: TextStyle(
                                  color: Colors.grey.shade500, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF0F4EC),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.timer_outlined,
                                color: Color(0xFF0891B2), size: 20),
                          ),
                          const SizedBox(height: 4),
                          Text(shortId,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.grey.shade400)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Delivery Address ───────────────────────────────────
                _buildAddressCard(),

                const SizedBox(height: 24),

                // ── Stepper ────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(24),
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
                  child: _buildStepper(step),
                ),

                const SizedBox(height: 24),

                // ── Plant Info ─────────────────────────────────────────
                if (_plantName.isNotEmpty) ...[
                  _buildPlantCard(),
                  const SizedBox(height: 24),
                ],

                // ── Rider Info ─────────────────────────────────────────
                if (step >= 1) ...[
                  _buildRiderCard(),
                  const SizedBox(height: 24),
                ],

                const SizedBox(height: 40),
              ],
            ),
      ),
    );
  }

  Widget _buildStepper(int currentStep) {
    final steps = [
      {'label': 'Order Placed', 'icon': Icons.check_circle_outline},
      {'label': 'Accepted by Rider', 'icon': Icons.delivery_dining},
      {'label': 'Out for Delivery', 'icon': Icons.electric_bolt},
      {'label': 'Delivered', 'icon': Icons.home_rounded},
    ];

    return Column(
      children: List.generate(steps.length, (i) {
        final isDone = i <= currentStep;
        final isCurrent = i == currentStep;
        final isLast = i == steps.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Circle + line
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isDone
                          ? const Color(0xFF0891B2)
                          : Colors.grey.shade200,
                      shape: BoxShape.circle,
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                  color: const Color(0xFF0891B2)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 8)
                            ]
                          : [],
                    ),
                    child: Icon(
                      isDone ? Icons.check : (steps[i]['icon'] as IconData),
                      size: 12,
                      color: isDone ? Colors.white : Colors.grey,
                    ),
                  ),
                  if (!isLast)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 2,
                      height: 40,
                      color: isDone
                          ? const Color(0xFF0891B2)
                          : Colors.grey.shade200,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Label
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 28),
                child: Text(
                  steps[i]['label'] as String,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w400,
                    color: isDone ? Colors.black : Colors.grey,
                    fontSize: isCurrent ? 15 : 13,
                  ),
                ),
              ),
            ),
            // Timestamp placeholder
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                isDone ? _getTimeForStep(i) : '—',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ),
          ],
        );
      }),
    );
  }

  String _getTimeForStep(int step) {
    // We use relative time hints since we don't have per-step timestamps
    if (step == 0) return 'Done';
    if (step == 1) return 'Done';
    return 'Done';
  }

  Widget _buildAddressCard() {
    final addr = _deliveryAddressMap;
    final displayStr = _deliveryAddressStr;

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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFFCFFAFE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_on,
                    color: Color(0xFF0891B2), size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Delivery Address',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 8),
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
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    if (fullName.isNotEmpty) ...[
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF4B5563),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (street.isNotEmpty) ...[
                      Text(
                        street,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (city.isNotEmpty || state.isNotEmpty || pincode.isNotEmpty)
                      Text(
                        '$city${city.isNotEmpty ? ", " : ""}$state $pincode',
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        phone,
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
          ),
        );
      }

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFCFFAFE),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_on,
                  color: Color(0xFF0891B2), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Delivery Address',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(displayStr ?? 'Your delivery address',
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 13, height: 1.4),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFCFFAFE),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on,
                color: Color(0xFF0891B2), size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Delivery Address',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
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
      ),
    );
  }

  Widget _buildPlantCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4), // Very light green
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
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.factory_outlined,
                color: Color(0xFF16A34A), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Plant / Retailer',
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF16A34A),
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  _plantName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (_plantPhone.isNotEmpty)
                  Text(
                    _plantPhone,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (_plantPhone.isNotEmpty)
            _IconBtn(
              icon: Icons.call,
              isPrimary: true,
              onPressed: () async {
                final Uri uri = Uri.parse('tel:$_plantPhone');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRiderCard() {
    final hasRider = _riderName.isNotEmpty;
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
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF0891B2),
            child: (hasRider && _riderName.trim().isNotEmpty)
                ? Text(
                    _riderName.trim()[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                  )
                : const Icon(Icons.delivery_dining,
                    color: Colors.white, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasRider ? _riderName : 'Assigning Rider...',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.orange, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      hasRider ? 'Your Delivery Partner' : 'Please wait',
                      style:
                          TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
                if (_lastRiderUpdate.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.green, size: 12),
                        const SizedBox(width: 4),
                        Text(
                          _lastRiderUpdate,
                          style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_riderPhone.isNotEmpty)
            _IconBtn(
              icon: Icons.call,
              isPrimary: true,
              onPressed: () async {
                final Uri uri = Uri.parse('tel:$_riderPhone');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
          const SizedBox(width: 10),
          _IconBtn(
            icon: Icons.chat_bubble_outline,
            isPrimary: false,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => OrderChatPage(
                    riderName: _riderName.isNotEmpty ? _riderName : 'Delivery Partner',
                    riderPhone: _riderPhone,
                    orderId: widget.orderId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _getStatusSubtitle(String status) {
    switch (status.toLowerCase().replaceAll('_', ' ').replaceAll('-', ' ')) {
      case 'pending':
        return 'Your order has been received';
      case 'accepted':
        return 'Your order has been accepted by the vendor';
      case 'rider assigned':
      case 'riderassigned':
        return 'A rider has been assigned to your order';
      case 'rider accepted':
        return 'Rider is heading to pick up your order';
      case 'pickedup':
      case 'picked up':
      case 'out for delivery':
      case 'out_for_delivery':
      case 'ontheway':
      case 'on the way':
        return 'Your order is on the way! 🛵';
      case 'delivered':
        return 'Enjoy your fresh water! 💧';
      case 'cancelled':
      case 'canceled':
        return 'This order has been cancelled';
      default:
        return 'Tracking your order...';
    }
  }

  bool get _canCancel {
    final status = _currentStatus.toLowerCase().trim();
    return status != 'delivered' &&
           status != 'completed' &&
           status != 'cancelled' &&
           status != 'canceled';
  }

  bool get _isCancelled {
    final status = _currentStatus.toLowerCase().trim();
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
                            final result = await ref
                                .read(orderServiceProvider)
                                .cancelOrder(orderId: widget.orderId, reason: reason);

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
                                _currentStatus = 'Cancelled';
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
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _IconBtn(
      {required this.icon, required this.isPrimary, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF0891B2) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isPrimary ? Colors.transparent : Colors.grey.shade200),
        ),
        child: Icon(icon,
            color: isPrimary ? Colors.white : Colors.black87, size: 18),
      ),
    );
  }
}

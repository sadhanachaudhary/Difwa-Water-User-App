import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:difwawaterapp/app/data/services/db_service.dart';
import '../../../data/services/order_service.dart';
import '../../../data/services/subscription_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/services/wallet_service.dart';
import 'order_success_page.dart';

import '../../../data/services/shop_service.dart';
import '../../../data/models/shop_product_model.dart';
import '../../../data/models/food_models.dart';

class PaymentMethodPage extends ConsumerStatefulWidget {
  const PaymentMethodPage({super.key});

  @override
  ConsumerState<PaymentMethodPage> createState() => _PaymentMethodPageState();
}

class _PaymentMethodPageState extends ConsumerState<PaymentMethodPage> {
  bool _isLoading = false;
  int _orderType = 0; // 0: One-time, 1: Scheduled
  String _paymentMethod = 'Wallet'; // 'Wallet' or 'Cash' (one-time orders)
  String _subscriptionPaymentType = 'Wallet'; // 'Wallet' (upfront) or 'PayLater' (subscription orders)
  String _frequency = 'Daily';
  List<String> _selectedDays = [];
  String? _selectedSlot;
  List<DeliverySlotAvailability>? _slotsAvailability;
  bool _isLoadingSlots = false;

  /// Show a clean, user-friendly snackbar — no 'Exception:' prefix ever shown.
  void _showError(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 14))),
          ],
        ),
        backgroundColor: const Color(0xFF0891B2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _refreshAfterPurchase(WidgetRef ref, CartProvider cartProvider) async {
    // 1. Sync the CartProvider's internal wallet and orders state
    await cartProvider.syncWallet();
    await cartProvider.syncOrders();
    
    // 2. Invalidate Riverpod providers to force global UI updates
    ref.invalidate(walletBalanceProvider);
    ref.invalidate(walletHistoryProvider);
    ref.invalidate(walletTransactionsProvider);
    ref.invalidate(activeOrdersProvider);
    ref.invalidate(myOrdersProvider);
    
    // 3. Refresh subscriptions list notifier
    if (mounted) {
      ref.invalidate(mySubscriptionsProvider);
    }
    
    // 4. Clear the cart
    cartProvider.clearCart();
  }

  late DateTime _startDate;
  final List<String> _frequencies = [
    'Daily',
    'Alternate Days',
    'Weekly',
  ];
  final List<String> _weekDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now().add(const Duration(days: 1));
    _loadCheckoutDraft();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final cart = CartProviderScope.of(context);
        cart.syncWallet();
        cart.updateDeliveryCharge();
        _fetchSlotsAvailability();
      }
    });
  }

  Future<void> _fetchSlotsAvailability() async {
    final cartProvider = CartProviderScope.of(context);
    final shopId = cartProvider.cartShopId;
    if (shopId == null || shopId.isEmpty) return;

    if (mounted) setState(() => _isLoadingSlots = true);
    try {
      String? dateParam;
      if (_orderType == 1) {
        dateParam = "${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}";
      }
      var slots = await ref.read(shopServiceProvider).getShopSlots(shopId, date: dateParam);
      if (slots.isEmpty) {
        final shopVal = ref.read(shopDetailsProvider(shopId)).value;
        if (shopVal != null && shopVal.deliverySlots.isNotEmpty) {
          slots = shopVal.deliverySlots
              .map((s) => DeliverySlotAvailability(slot: s, available: true))
              .toList();
        }
      }
      if (mounted) {
        setState(() {
          _slotsAvailability = slots;
          
          // Verify current slot is still valid and available
          if (_selectedSlot != null) {
            final slotExistsAndAvailable = slots.any((s) => s.slot == _selectedSlot && s.available);
            if (!slotExistsAndAvailable) {
              _selectedSlot = null; // Reset selection if no longer available
              _saveCheckoutDraft();
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching slots availability: $e');
    } finally {
      if (mounted) setState(() => _isLoadingSlots = false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadCheckoutDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final orderType = prefs.getInt('checkout_draft_order_type');
      final frequency = prefs.getString('checkout_draft_frequency');
      final selectedDays = prefs.getStringList('checkout_draft_selected_days');
      final startDateStr = prefs.getString('checkout_draft_start_date');
      final selectedSlot = prefs.getString('checkout_draft_selected_slot');

      final subPaymentType = prefs.getString('checkout_draft_sub_payment_type');

      if (mounted) {
        setState(() {
          if (orderType != null) _orderType = orderType;
          if (frequency != null) _frequency = frequency;
          if (selectedDays != null) _selectedDays = selectedDays;
          if (startDateStr != null) {
            _startDate = DateTime.tryParse(startDateStr) ?? DateTime.now().add(const Duration(days: 1));
          }
          if (selectedSlot != null) _selectedSlot = selectedSlot;
          if (subPaymentType != null) _subscriptionPaymentType = subPaymentType;
        });
      }
    } catch (e) {
      debugPrint('Error loading checkout draft: $e');
    }
  }

  Future<void> _saveCheckoutDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('checkout_draft_order_type', _orderType);
      await prefs.setString('checkout_draft_frequency', _frequency);
      await prefs.setStringList('checkout_draft_selected_days', _selectedDays);
      await prefs.setString('checkout_draft_start_date', _startDate.toIso8601String());
      if (_selectedSlot != null) {
        await prefs.setString('checkout_draft_selected_slot', _selectedSlot!);
      } else {
        await prefs.remove('checkout_draft_selected_slot');
      }
      await prefs.setString('checkout_draft_sub_payment_type', _subscriptionPaymentType);
    } catch (e) {
      debugPrint('Error saving checkout draft: $e');
    }
  }

  Future<void> _clearCheckoutDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('checkout_draft_order_type');
      await prefs.remove('checkout_draft_frequency');
      await prefs.remove('checkout_draft_selected_days');
      await prefs.remove('checkout_draft_start_date');
      await prefs.remove('checkout_draft_selected_slot');
      await prefs.remove('checkout_draft_sub_payment_type');
    } catch (e) {
      debugPrint('Error clearing checkout draft: $e');
    }
  }

  Future<void> _pickDate() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: tomorrow,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _saveCheckoutDraft();
      });
      _fetchSlotsAvailability();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartProvider = CartProviderScope.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Payment Method',
          style: TextStyle(
              color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          const _CheckoutStepper(currentStep: 2),
          const SizedBox(height: 20),
          if (!cartProvider.isDeliverable)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cartProvider.deliveryMessage,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cartProvider.selectedAddress != null) ...[
                    _buildAddressCard(context, cartProvider),
                    const SizedBox(height: 20),
                  ],

                  GestureDetector(
                    onTap: () async {
                      await Navigator.pushNamed(context, '/wallet');
                      if (mounted) {
                        CartProviderScope.of(context).syncWallet();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF00ACC1).withOpacity(0.2),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_rounded,
                              color: AppColors.primary, size: 32),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Wallet Balance',
                                  style: TextStyle(
                                      fontSize: 13, color: Colors.grey)),
                              Text(
                                '₹${cartProvider.walletBalance.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary),
                              ),
                            ],
                          ),
                          const Spacer(),
                          if (cartProvider.walletBalance < cartProvider.total)
                            const Text('Insufficient',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12)),
                          const Icon(Icons.arrow_forward_ios,
                              size: 16, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Empty Bottle Exchange',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937))),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00ACC1).withOpacity(0.2),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cached_rounded, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Do you have empty bottles to return?',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Color(0xFF1F2937)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Waive deposit charge by exchanging empty bottles.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  cartProvider.setHasEmptyBottles(false);
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: !cartProvider.hasEmptyBottles
                                      ? AppColors.primary
                                      : Colors.white,
                                  side: BorderSide(
                                    color: !cartProvider.hasEmptyBottles
                                        ? AppColors.primary
                                        : const Color(0xFF00ACC1).withOpacity(0.2),
                                  ),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: Text(
                                  'No, pay deposit',
                                  style: TextStyle(
                                    color: !cartProvider.hasEmptyBottles
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  cartProvider.setHasEmptyBottles(true);
                                },
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: cartProvider.hasEmptyBottles
                                      ? AppColors.primary
                                      : Colors.white,
                                  side: BorderSide(
                                    color: cartProvider.hasEmptyBottles
                                        ? AppColors.primary
                                        : const Color(0xFF00ACC1).withOpacity(0.2),
                                  ),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: Text(
                                  'Yes, exchange',
                                  style: TextStyle(
                                    color: cartProvider.hasEmptyBottles
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (cartProvider.hasEmptyBottles) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Returned Bottles Count:',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade800),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: cartProvider.returnedBottlesCount > 0
                                        ? () {
                                            cartProvider.setReturnedBottlesCount(
                                                cartProvider.returnedBottlesCount - 1);
                                          }
                                        : null,
                                    icon: const Icon(Icons.remove_circle_outline),
                                    color: AppColors.primary,
                                    disabledColor: Colors.grey.shade300,
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    constraints: const BoxConstraints(minWidth: 40),
                                    child: Text(
                                      '${cartProvider.returnedBottlesCount}',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      cartProvider.setReturnedBottlesCount(
                                          cartProvider.returnedBottlesCount + 1);
                                    },
                                    icon: const Icon(Icons.add_circle_outline),
                                    color: AppColors.primary,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Order Summary',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937))),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF00ACC1).withOpacity(0.2),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        ...cartProvider.items.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${item.title} x ${item.quantity}',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  Text(
                                    '₹${(item.totalPrice).toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            )),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Delivery Charges',
                                style: TextStyle(color: Colors.grey)),
                            if (cartProvider.isCalculatingDelivery)
                              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))
                            else
                              Text(
                                '₹${cartProvider.deliveryFee.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: cartProvider.deliveryFee > 0 ? Colors.black : Colors.green,
                                  fontWeight: cartProvider.deliveryFee > 0 ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                        if (cartProvider.bottleDepositFee > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Bottle Deposit Charge',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                '₹${cartProvider.bottleDepositFee.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (cartProvider.weatherSurgeFee > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Weather Surge Fee 🌦️',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                '₹${cartProvider.weatherSurgeFee.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (cartProvider.nightSurgeFee > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Night Delivery Surge 🌙',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                '₹${cartProvider.nightSurgeFee.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (cartProvider.floorChargeFee > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Building Floor Charge 🏢',
                                  style: TextStyle(color: Colors.grey)),
                              Text(
                                '₹${cartProvider.floorChargeFee.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Amount',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(
                              '₹${cartProvider.total.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: AppColors.primary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Payment Method',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937))),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _paymentMethod = 'Wallet'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 12),
                            decoration: BoxDecoration(
                              color: _paymentMethod == 'Wallet'
                                  ? AppColors.primary
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _paymentMethod == 'Wallet'
                                    ? AppColors.primary
                                    : const Color(0xFF00ACC1).withOpacity(0.2),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.account_balance_wallet_rounded,
                                  color: _paymentMethod == 'Wallet'
                                      ? Colors.white
                                      : AppColors.primary,
                                  size: 26,
                                ),
                                const SizedBox(height: 8),
                                Text('Wallet',
                                    style: TextStyle(
                                        color: _paymentMethod == 'Wallet'
                                            ? Colors.white
                                            : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _orderType == 1
                              ? null
                              : () => setState(() => _paymentMethod = 'Cash'),
                          child: Opacity(
                            opacity: _orderType == 1 ? 0.45 : 1.0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 16, horizontal: 12),
                              decoration: BoxDecoration(
                                color: _paymentMethod == 'Cash'
                                    ? AppColors.primary
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _paymentMethod == 'Cash'
                                      ? AppColors.primary
                                      : const Color(0xFF00ACC1).withOpacity(0.2),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.payments_rounded,
                                    color: _paymentMethod == 'Cash'
                                        ? Colors.white
                                        : Colors.green.shade700,
                                    size: 26,
                                  ),
                                  const SizedBox(height: 8),
                                  Text('Cash on Delivery',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: _paymentMethod == 'Cash'
                                              ? Colors.white
                                              : Colors.black87,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_orderType == 1 && _paymentMethod == 'Cash')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Cash on Delivery is not available for scheduled orders.',
                        style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const Text('Order Type',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937))),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _TypeButton(
                        label: 'One-time Order',
                        selected: _orderType == 0,
                        onTap: () {
                          setState(() {
                            _orderType = 0;
                            _saveCheckoutDraft();
                          });
                          _fetchSlotsAvailability();
                        },
                        icon: Icons.shopping_bag_outlined,
                      ),
                      const SizedBox(width: 12),
                      _TypeButton(
                        label: 'Daily Deliveries',
                        selected: _orderType == 1,
                        onTap: () {
                          setState(() {
                            _orderType = 1;
                            // COD not supported for scheduled orders
                            if (_paymentMethod == 'Cash') _paymentMethod = 'Wallet';
                            _saveCheckoutDraft();
                          });
                          _fetchSlotsAvailability();
                        },
                        icon: Icons.calendar_today_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_orderType == 1) ...[
                    const Text('Delivery Frequency',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937))),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _frequencies.map((f) {
                        bool isSel = _frequency == f;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _frequency = f;
                            if (f != 'Weekly') _selectedDays = [];
                            _saveCheckoutDraft();
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSel
                                    ? AppColors.primary
                                    : const Color(0xFF00ACC1).withOpacity(0.2),
                                width: 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              f,
                              style: TextStyle(
                                color: isSel ? Colors.white : Colors.black,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_frequency == 'Weekly') ...[
                      const SizedBox(height: 16),
                      const Text('Select Delivery Days',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937))),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _weekDays.map((day) {
                          final short = day.substring(0, 3);
                          final selected = _selectedDays.contains(day);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (selected) {
                                _selectedDays.remove(day);
                              } else {
                                _selectedDays.add(day);
                              }
                              _saveCheckoutDraft();
                            }),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.primary
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.primary
                                      : const Color(0xFF00ACC1).withOpacity(0.2),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: Text(short,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: selected
                                          ? Colors.white
                                          : Colors.black87)),
                            ),
                          );
                        }).toList(),
                      ),
                      if (_selectedDays.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Please select at least one day',
                              style:
                                  TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                    ],
                    const SizedBox(height: 16),
                    // Start Date Picker
                    const Text('Start Date',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937))),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF00ACC1).withOpacity(0.2),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                color: AppColors.primary, size: 20),
                            const SizedBox(width: 12),
                            Text(
                              '${_startDate.day.toString().padLeft(2, '0')} / ${_startDate.month.toString().padLeft(2, '0')} / ${_startDate.year}',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary),
                            ),
                            const Spacer(),
                            const Text('Tap to change',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Payment Type',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937))),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _TypeButton(
                          label: 'Pay Upfront',
                          selected: _subscriptionPaymentType == 'Wallet',
                          onTap: () => setState(() {
                            _subscriptionPaymentType = 'Wallet';
                            _saveCheckoutDraft();
                          }),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        const SizedBox(width: 12),
                        _TypeButton(
                          label: 'Pay Later',
                          selected: _subscriptionPaymentType == 'PayLater',
                          onTap: () => setState(() {
                            _subscriptionPaymentType = 'PayLater';
                            _saveCheckoutDraft();
                          }),
                          icon: Icons.schedule_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subscriptionPaymentType == 'Wallet'
                          ? 'Load your wallet once — daily cost is auto-deducted each morning.'
                          : 'Deliveries start immediately; wallet balance may go negative.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                  ],
                  const Text('Delivery Slot',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937))),
                  const SizedBox(height: 12),
                  if (_isLoadingSlots)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    ref.watch(shopDetailsProvider(cartProvider.cartShopId ?? '')).when(
                          data: (shop) {
                            final List<DeliverySlotAvailability> displaySlots;
                            if (_slotsAvailability != null && _slotsAvailability!.isNotEmpty) {
                              displaySlots = _slotsAvailability!;
                            } else {
                              displaySlots = (shop?.deliverySlots ?? [])
                                  .map((s) => DeliverySlotAvailability(slot: s, available: true))
                                  .toList();
                            }

                            if (displaySlots.isEmpty) {
                              return Text('No slots available',
                                  style: TextStyle(color: Colors.grey.shade500));
                            }

                            // Verify selected slot is still valid and available
                            if (_selectedSlot != null) {
                              final slotExistsAndAvailable = displaySlots.any((s) => s.slot == _selectedSlot && s.available);
                              if (!slotExistsAndAvailable) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  setState(() {
                                    _selectedSlot = null;
                                    _saveCheckoutDraft();
                                  });
                                });
                              }
                            }

                            return SizedBox(
                              height: 50,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: displaySlots.length,
                                itemBuilder: (context, index) {
                                  final slotData = displaySlots[index];
                                  final slot = slotData.slot;
                                  final isAvailable = slotData.available;
                                  final isSelected = _selectedSlot == slot;
                                  
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8, bottom: 8),
                                    child: GestureDetector(
                                      onTap: !isAvailable
                                          ? () => _showError('This slot is currently full/unavailable.')
                                          : () => setState(() {
                                                _selectedSlot = slot;
                                                _saveCheckoutDraft();
                                              }),
                                      child: Opacity(
                                        opacity: isAvailable ? 1.0 : 0.45,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: isSelected 
                                                ? AppColors.primary 
                                                : isAvailable 
                                                    ? Colors.white 
                                                    : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isSelected
                                                  ? AppColors.primary
                                                  : isAvailable
                                                      ? const Color(0xFF00ACC1).withOpacity(0.2)
                                                      : Colors.grey.shade300,
                                              width: 1.0,
                                            ),
                                            boxShadow: [
                                              if (isAvailable)
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.05),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4),
                                                ),
                                            ],
                                          ),
                                          child: Center(
                                            child: Text(
                                              slot,
                                              style: TextStyle(
                                                color: isSelected 
                                                    ? Colors.white 
                                                    : isAvailable 
                                                        ? Colors.black 
                                                        : Colors.grey.shade500,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                fontSize: 13,
                                                decoration: isAvailable ? null : TextDecoration.lineThrough,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          loading: () => const Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator())),
                          error: (_, __) => Text(
                            'Could not load delivery slots. Pull to refresh.',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                          ),
                        ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_isLoading || !cartProvider.isDeliverable || cartProvider.isCalculatingDelivery)
                    ? null
                    : () async {
                        HapticFeedback.mediumImpact();
                        // ── Validate user inputs BEFORE setting loading ────────
                        final selectedAddr = cartProvider.selectedAddress;
                        if (selectedAddr == null) {
                          _showError('Please select a delivery address to continue.');
                          return;
                        }
                        if (_orderType == 0 &&
                            _paymentMethod == 'Wallet' &&
                            cartProvider.walletBalance < cartProvider.total) {
                          _showError('Your wallet balance is low. Please top up to proceed.');
                          return;
                        }
                        if (_orderType == 1 && _frequency == 'Weekly' && _selectedDays.isEmpty) {
                          _showError('Please choose at least one day for your weekly delivery.');
                          return;
                        }
                        if (_selectedSlot == null) {
                          _showError('Please choose a delivery time slot.');
                          return;
                        }

                        setState(() => _isLoading = true);

                        // ── Fetch latest slots to check availability right before submit ──
                        await _fetchSlotsAvailability();
                        if (_selectedSlot == null) {
                          _showError('The selected delivery slot is no longer available. Please select another slot.');
                          setState(() => _isLoading = false);
                          return;
                        }

                        final navigator = Navigator.of(context);
                        try {
                          String fullName = selectedAddr.fullName;
                          if (fullName.trim().isEmpty) {
                            fullName = cartProvider.userProfile.name;
                          }
                          if (fullName.isEmpty) {
                            fullName = 'Unknown Recipient';
                          }
                          final parts = selectedAddr.details.split(',');
                          final city = parts.isNotEmpty ? parts[0].trim() : '';
                          String state = '';
                          String pincode = '';
                          if (parts.length > 1) {
                            final stateParts = parts[1].trim().split(' ');
                            if (stateParts.length > 1) {
                              pincode = stateParts.last;
                              state = stateParts.sublist(0, stateParts.length - 1).join(' ');
                            } else {
                              state = parts[1].trim();
                            }
                          }

                          final deliveryAddressMap = {
                            'fullName': fullName,
                            'street': selectedAddr.street,
                            'address': selectedAddr.street,
                            'fullAddress': '${selectedAddr.street}, ${selectedAddr.details}',
                            'city': city,
                            'state': state,
                            'pincode': pincode,
                            'phone': cartProvider.userProfile.phone,
                            'phoneNumber': cartProvider.userProfile.phone,
                            'label': selectedAddr.title,
                            'latitude': selectedAddr.latitude,
                            'longitude': selectedAddr.longitude,
                            // Priority fix: added lat/lng for backend compatibility
                            'lat': selectedAddr.latitude,
                            'lng': selectedAddr.longitude,
                            // Floor / Lift — always include so backend calculates correctly
                            'floorNumber': selectedAddr.floorNumber ?? 0,
                            'hasLift': selectedAddr.hasLift ?? false,
                            if (selectedAddr.latitude != null &&
                                selectedAddr.longitude != null)
                              'coordinates': {
                                'latitude': selectedAddr.latitude,
                                'longitude': selectedAddr.longitude,
                                'lat': selectedAddr.latitude,
                                'lng': selectedAddr.longitude,
                              },
                          };

                          if (_orderType == 1) {
                            // SCHEDULED ORDER
                            final subService = ref.read(subscriptionServiceProvider);
                            for (final item in cartProvider.items) {
                              final res = await subService.subscribeToProduct(
                                productId: item.id,
                                frequency: _frequency,
                                quantity: item.quantity,
                                deliveryAddress: deliveryAddressMap,
                                customDays: _frequency == 'Weekly' ? _selectedDays : [],
                                startDate: _startDate,
                                deliverySlot: _selectedSlot,
                                paymentMethod: _subscriptionPaymentType,
                                hasEmptyBottles: cartProvider.hasEmptyBottles,
                                returnedBottlesCount: cartProvider.returnedBottlesCount,
                              );
                              if (res['success'] != true) {
                                final String errMsg = res['message'] ?? '';
                                if (errMsg.contains('slot') || errMsg.contains('Slot') || errMsg.contains('no longer available')) {
                                  await _fetchSlotsAvailability();
                                }
                                final cleanMsg = errMsg.replaceAll(RegExp(r'^ApiException(\(\d+\))?:\s*'), '');
                                _showError(cleanMsg.isNotEmpty ? cleanMsg : 'Could not subscribe to ${item.title}. Please try again.');
                                return;
                              }
                            }
                            await _refreshAfterPurchase(ref, cartProvider);
                            await _clearCheckoutDraft();
                            if (!mounted) return;
                            navigator.pushAndRemoveUntil(
                                MaterialPageRoute(builder: (_) => const OrderSuccessPage()),
                                (route) => route.isFirst);
                          } else {
                            // ONE-TIME ORDER
                            final orderService = ref.read(orderServiceProvider);
                            final itemsMap = cartProvider.items.map((item) => {
                                'product': item.id,
                                'retailer': item.shopId,
                                'quantity': item.quantity,
                                'price': item.unitPrice,
                              }).toList();

                            final response = await orderService.placeOrder(
                                items: itemsMap,
                                totalAmount: cartProvider.total,
                                deliveryAddress: deliveryAddressMap,
                                paymentMethod: _paymentMethod,
                                deliverySlot: _selectedSlot,
                                hasEmptyBottles: cartProvider.hasEmptyBottles,
                                returnedBottlesCount: cartProvider.returnedBottlesCount,
                                // Always send floor/lift so the backend records & charges correctly
                                floorNumber: selectedAddr.floorNumber ?? 0,
                                hasLift: selectedAddr.hasLift ?? false,
                                coordinates: (selectedAddr.latitude != null &&
                                        selectedAddr.longitude != null)
                                    ? {
                                        'latitude': selectedAddr.latitude!,
                                        'longitude': selectedAddr.longitude!,
                                        'lat': selectedAddr.latitude!,
                                        'lng': selectedAddr.longitude!,
                                      }
                                    : null);

                            if (response['success'] == true) {
                              await _refreshAfterPurchase(ref, cartProvider);
                              await _clearCheckoutDraft();
                              if (!mounted) return;
                              navigator.pushAndRemoveUntil(
                                  MaterialPageRoute(
                                      builder: (_) => OrderSuccessPage(order: response['order'])),
                                  (route) => route.isFirst);
                            } else {
                              final String errMsg = response['message'] ?? '';
                              if (errMsg.contains('slot') || errMsg.contains('Slot') || errMsg.contains('no longer available')) {
                                await _fetchSlotsAvailability();
                              }
                              final cleanMsg = errMsg.replaceAll(RegExp(r'^ApiException(\(\d+\))?:\s*'), '');
                              _showError(cleanMsg.isNotEmpty ? cleanMsg : 'Order could not be placed. Please try again.');
                            }
                          }
                        } catch (_) {
                          // Unexpected network/server error — never show raw exception to user
                          _showError('Something went wrong. Please check your connection and try again.');
                        } finally {
                          if (mounted) setState(() => _isLoading = false);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        _paymentMethod == 'Cash'
                            ? 'Place Order (Pay on Delivery)'
                            : 'Make a payment',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressCard(BuildContext context, CartProvider cartProvider) {
    final addr = cartProvider.selectedAddress!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF00ACC1).withOpacity(0.2),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                addr.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF1F2937),
                ),
              ),
              if (addr.isDefault) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F4F8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DEFAULT',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.swap_horiz_rounded, size: 16, color: AppColors.primary),
                label: const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            addr.street,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.4),
          ),
          Text(
            addr.details,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Floor: ${addr.floorNumber ?? 0}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Lift: ${addr.hasLift == true ? "Available" : "Not Available"}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              if (cartProvider.floorChargeFee > 0)
                Text(
                  'Floor Charge: ₹${cartProvider.floorChargeFee.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.orange,
                  ),
                )
              else
                const Text(
                  'No Floor Charge',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: Colors.green,
                  ),
                ),
              ElevatedButton.icon(
                onPressed: () => _showEditFloorDialog(context, addr, cartProvider),
                icon: const Icon(Icons.edit_rounded, size: 14),
                label: const Text('Edit Floor', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  foregroundColor: AppColors.primary,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditFloorDialog(BuildContext context, UserAddress addr, CartProvider cartProvider) {
    final floorCtrl = TextEditingController(text: addr.floorNumber?.toString() ?? '0');
    bool hasLiftVal = addr.hasLift ?? false;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Edit Floor Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: floorCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    enabled: !isSaving,
                    onTap: () {
                      if (floorCtrl.text == '0') {
                        floorCtrl.clear();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Floor Number',
                      hintText: 'e.g. 0 for Ground, 1, 2, 3...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Building has lift?',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                      Switch.adaptive(
                        value: hasLiftVal,
                        activeTrackColor: AppColors.primary.withOpacity(0.5),
                        activeThumbColor: AppColors.primary,
                        onChanged: isSaving
                            ? null
                            : (val) {
                                setDialogState(() {
                                  hasLiftVal = val;
                                });
                              },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final int floor = int.tryParse(floorCtrl.text) ?? 0;
                          final updatedAddr = addr.copyWith(
                            floorNumber: floor,
                            hasLift: hasLiftVal,
                          );

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            final res = await cartProvider.updateAddress(updatedAddr);
                            if (context.mounted) {
                              Navigator.pop(dialogContext); // Close dialog
                              if (res['success'] != true) {
                                _showError(res['message'] ?? 'Failed to update address floor details.');
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Floor details updated successfully!'),
                                    backgroundColor: AppColors.primary,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setDialogState(() {
                                isSaving = false;
                              });
                              _showError('Error updating address: $e');
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Save', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _TypeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;

  const _TypeButton(
      {required this.label,
      required this.selected,
      required this.onTap,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : const Color(0xFF00ACC1).withOpacity(0.2),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? Colors.white : Colors.grey, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: selected ? Colors.white : Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



class _CheckoutStepper extends StatelessWidget {
  final int currentStep;
  const _CheckoutStepper({required this.currentStep});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          _StepDot(label: 'DELIVERY', stepIndex: 0, currentStep: currentStep),
          _StepLine(active: currentStep >= 1),
          _StepDot(label: 'ADDRESS', stepIndex: 1, currentStep: currentStep),
          _StepLine(active: currentStep >= 2),
          _StepDot(label: 'PAYMENT', stepIndex: 2, currentStep: currentStep),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final int stepIndex;
  final int currentStep;
  const _StepDot(
      {required this.label,
      required this.stepIndex,
      required this.currentStep});
  @override
  Widget build(BuildContext context) {
    final bool done = currentStep > stepIndex;
    final bool active = currentStep == stepIndex;
    final Color bg = (done || active) ? AppColors.primary : Colors.white;
    final Color border =
        (done || active) ? AppColors.primary : Colors.grey.shade300;
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: Border.all(color: border, width: 2),
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : Text('${stepIndex + 1}',
                  style: TextStyle(
                      color: active ? Colors.white : Colors.grey.shade500,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: (done || active)
                  ? AppColors.primary
                  : Colors.grey.shade400,
              letterSpacing: 0.5),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool active;
  const _StepLine({required this.active});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: 2,
          margin: const EdgeInsets.only(bottom: 20),
          color: active ? AppColors.primary : Colors.grey.shade300,
        ),
      );
}

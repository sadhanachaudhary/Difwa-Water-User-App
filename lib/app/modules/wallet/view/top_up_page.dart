import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../../data/services/payment_service.dart';
import '../../../data/services/wallet_service.dart';
import '../../../data/services/db_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../home/controller/main_controller.dart';

class TopUpPage extends ConsumerStatefulWidget {
  const TopUpPage({super.key});

  @override
  ConsumerState<TopUpPage> createState() => _TopUpPageState();
}

class _TopUpPageState extends ConsumerState<TopUpPage> {
  final TextEditingController _amountController = TextEditingController();
  bool _isLoading = false;
  // Cache service so we can call dispose() without using ref after unmount
  late PaymentService _paymentService;
  // Cache context-dependent refs — Razorpay callbacks fire after CheckoutActivity
  // closes and Flutter's InheritedWidget tree is mid-resume, so .of(context)
  // calls inside callbacks throw "No ancestor found / wrap in X" errors.
  ScaffoldMessengerState? _messenger;
  CartProvider? _cartScope;

  bool _amountInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
    _cartScope = CartProviderScope.of(context);
    if (!_amountInitialized) {
      _amountInitialized = true;
      final args = ModalRoute.of(context)?.settings.arguments
          as Map<String, dynamic>?;
      final amount = args?['amount'];
      if (amount != null) {
        _amountController.text = amount.toString();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _paymentService = ref.read(paymentServiceProvider);
    _paymentService.init(
      onSuccess: _handlePaymentSuccess,
      onFailure: _handlePaymentFailure,
      onExternalWallet: _handleExternalWallet,
    );
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    debugPrint('TopUpPage: Payment SUCCESS: ID=${response.paymentId}, OrderID=${response.orderId}');
    if (!mounted) return;
    setState(() => _isLoading = true);
    final amount = double.tryParse(_amountController.text) ?? 0.0;

    final walletRef = ref.read(walletServiceProvider);

    final result = await walletRef.topUpSuccess(
          amount: amount,
          razorpayOrderId: response.orderId!,
          razorpayPaymentId: response.paymentId!,
          razorpaySignature: response.signature!,
        );

    debugPrint('TopUpPage: Verification result: $result');

    if (mounted) {
      setState(() => _isLoading = false);
      if (result['success'] == true) {
        _cartScope?.syncWallet();
        ref.invalidate(walletBalanceProvider);
        ref.invalidate(walletHistoryProvider);
        
        _messenger?.showSnackBar(
          SnackBar(
            content: const Text('Wallet topped up successfully!'),
            backgroundColor: const Color(0xFF06B6D4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          ),
        );
        
        // Ensure index is set to 3 (Wallet tab on MainPage)
        ref.read(mainIndexProvider.notifier).setIndex(3);
        
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      } else {
        _messenger?.showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Verification failed'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          ),
        );
      }
    }
  }

  void _handlePaymentFailure(PaymentFailureResponse response) {
    debugPrint('TopUpPage: Payment FAILED: Code=${response.code}, Message=${response.message}');
    // Use cached messenger — widget may already be unmounted at this point
    if (!mounted) return;
    _messenger?.showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Expanded(child: Text('Payment was not completed. Please try again.')),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    debugPrint('TopUpPage: External Wallet selected: ${response.walletName}');
    // Use cached messenger — safe after native callback
    if (!mounted) return;
    _messenger?.showSnackBar(
      SnackBar(
        content: Text('External Wallet: ${response.walletName}'),
        backgroundColor: const Color(0xFF06B6D4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _paymentService.dispose(); // use cached ref — safe after unmount
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = CartProviderScope.of(context).userProfile;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          'Top Up Wallet',
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
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: const Color(0xFF00ACC1).withOpacity(0.1),
            height: 1,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter Amount',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                  const Text(
                    '₹',
                    style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E293B)),
                      decoration: const InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(color: Colors.grey),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [500, 1000, 2000, 5000].map((amt) {
                final isSelected = _amountController.text == amt.toString();
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => setState(() => _amountController.text = amt.toString()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF00ACC1)
                                : const Color(0xFF00ACC1).withOpacity(0.1),
                            width: isSelected ? 2.0 : 1.0,
                          ),
                          boxShadow: isSelected ? [
                            BoxShadow(
                              color: const Color(0xFF00ACC1).withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ] : [],
                        ),
                        child: Text(
                          '₹$amt',
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF00ACC1) : const Color(0xFF1E293B),
                            fontWeight: isSelected ? FontWeight.w900 : FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 48),
            _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.accentGreen))
                : ElevatedButton(
                    onPressed: () async {
                      final amount =
                          double.tryParse(_amountController.text) ?? 0.0;
                      if (amount < 100) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Minimum top-up is ₹100')));
                        return;
                      }
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await _paymentService.openCheckout(
                          amount: amount,
                          contact: profile.phone,
                          email: profile.email,
                        );
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(
                          content: const Row(
                            children: [
                              Icon(Icons.error_outline, color: Colors.white, size: 18),
                              SizedBox(width: 10),
                              Expanded(child: Text('Could not open payment. Please try again.')),
                            ],
                          ),
                          backgroundColor: AppColors.error,
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Proceed to Payment',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
          ],
        ),
      ),
    );
  }
}

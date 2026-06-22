import 'package:flutter/material.dart';
import '../../../data/services/db_service.dart';
import '../../cart/view/cart_page.dart';
import '../../../core/constants/app_colors.dart';

class CartSummaryBar extends StatelessWidget {
  final CartProvider cart;
  final VoidCallback? onTap;

  const CartSummaryBar({
    super.key,
    required this.cart,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final count = cart.itemCount;
    if (count == 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: onTap ?? () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const CartPage()),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_basket_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count ITEM${count > 1 ? 'S' : ''}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  '₹${cart.total.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Text(
              'VIEW CART',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

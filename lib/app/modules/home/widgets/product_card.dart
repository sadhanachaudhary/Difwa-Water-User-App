import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../data/models/food_models.dart';
import '../../../data/services/db_service.dart';
import '../../../data/models/product_model.dart';
import '../../../data/services/favorites_service.dart';
import '../view/product_details_page.dart';
import '../widgets/quantity_selector.dart';
import '../../../widgets/bounce_widget.dart';
import '../../../core/constants/app_colors.dart';

class ProductCard extends ConsumerWidget {
  final Product product;
  final VoidCallback? onAdd;

  const ProductCard({
    super.key,
    required this.product,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = CartProviderScope.of(context);

    final cartItem = cart.items.firstWhere(
      (item) =>
          (item.id.isNotEmpty &&
              product.id.isNotEmpty &&
              item.id == product.id) ||
          ((item.id.isEmpty || product.id.isEmpty) &&
              item.title.isNotEmpty &&
              item.title == product.name &&
              item.shopId != null &&
              item.shopId!.isNotEmpty &&
              item.shopId == product.shopId),
      orElse: () => CartItem(
        id: product.id,
        title: product.name,
        unitPrice: product.price,
        subtitle: product.weight,
        image: product.image,
        category: product.category,
        quantity: 0,
      ),
    );
    final isInCart = cartItem.quantity > 0;

    final isOutOfStock = product.stockStatus == 'Out of Stock';
    final isLowStock = product.stockStatus == 'Low Stock';

    return BounceWidget(
      onTap: () {
        if (!product.isShopActive) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This shop is currently closed.'),
              backgroundColor: Colors.black87,
            ),
          );
          return;
        }
        if (isOutOfStock) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This product is currently out of stock.'),
              backgroundColor: Colors.black87,
            ),
          );
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailsPage(product: product),
          ),
        );
      },
      child: Opacity(
        opacity: (product.isShopActive && !isOutOfStock) ? 1.0 : 0.8,
        child: ColorFiltered(
          colorFilter: (product.isShopActive && !isOutOfStock)
              ? const ColorFilter.mode(Colors.transparent, BlendMode.multiply)
              : const ColorFilter.mode(Colors.grey, BlendMode.saturation),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.2),
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
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product Image
                    Hero(
                      tag: 'product_${product.id}',
                      child: Padding(
                        padding:
                            const EdgeInsets.only(top: 8, left: 8, right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height:
                                120, // Increased height slightly for better visibility
                            width: double.infinity,
                            color: const Color(
                                0xFFF1F5F9), // Light grey background
                            padding: const EdgeInsets.all(
                                8), // Keep image away from the borders
                            child: Center(
                              child: Image.network(
                                product.image,
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey.shade200,
                                    child: const Center(
                                      child: Icon(Icons.broken_image,
                                          color: Colors.grey),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Weight or description
                          Text(
                            product.weight,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Price & Add Area
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '₹${product.price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              // Dynamic Cart Controls
                              if (!isInCart)
                                BounceWidget(
                                  onTap: () => _handleAddToCart(context, cart),
                                  scaleFactor: 0.9,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: (product.isShopActive &&
                                              !isOutOfStock)
                                          ? AppColors.primary
                                          : Colors.grey,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                )
                              else
                                QuantitySelector(
                                  quantity: cartItem.quantity,
                                  onIncrement:
                                      (product.isShopActive && !isOutOfStock)
                                          ? () => cart.increment(product.id)
                                          : () {},
                                  onDecrement:
                                      (product.isShopActive && !isOutOfStock)
                                          ? () => cart.decrement(product.id)
                                          : () {},
                                  size: 32, // Compact size for grid card
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Closed Shop Badge
                if (!product.isShopActive)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'CLOSED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Out of Stock Badge
                if (isOutOfStock && product.isShopActive)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'OUT OF STOCK',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Badge (Offer/New/Low Stock)
                if ((product.badgeText.isNotEmpty || isLowStock) &&
                    product.isShopActive &&
                    !isOutOfStock)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isLowStock ? Colors.orange.shade700 : Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isLowStock
                            ? (product.stock > 0
                                ? 'Only ${product.stock} left!'
                                : 'Selling Fast!')
                            : product.badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // Favorite Icon
                Positioned(
                  top: 8,
                  right: 8,
                  child: _ProductHeart(productId: product.id),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(
        begin: 0.05, end: 0, duration: 400.ms, curve: Curves.easeOutQuad);
  }

  void _handleAddToCart(BuildContext context, CartProvider cart) {
    if (onAdd != null) {
      onAdd!();
      return;
    }

    if (!product.isShopActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This shop is currently closed.'),
          backgroundColor: Colors.black87,
        ),
      );
      return;
    }

    final isOutOfStock =
        product.stockStatus == 'Out of Stock' || product.stock <= 0;
    if (isOutOfStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This product is currently out of stock.'),
          backgroundColor: Colors.black87,
        ),
      );
      return;
    }

    if (cart.isSameShop(product.shopId)) {
      HapticFeedback.lightImpact();
      cart.addToCart(CartItem.fromProduct(product));
    } else {
      _showReplaceCartDialog(context, cart);
    }
  }

  void _showReplaceCartDialog(BuildContext context, CartProvider cart) {
    final oldShopName = cart.cartShopName ?? 'another shop';
    final newShopName =
        product.shopName.isNotEmpty ? product.shopName : 'this shop';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Start a new cart?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        content: Text(
          'Your cart has items from $oldShopName. Adding items from $newShopName will replace your current selection. Would you like to proceed?',
          style:
              const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: const Color(0xFFFFF1F0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'No',
                    style: TextStyle(
                        color: Color(0xFFFC5A44), fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    cart.clearCart();
                    cart.addToCart(CartItem.fromProduct(product));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Cart replaced with items from $newShopName'),
                        backgroundColor: AppColors.primaryDark,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: const Color(0xFFFC5A44),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Replace',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductHeart extends ConsumerStatefulWidget {
  final String productId;
  const _ProductHeart({required this.productId});

  @override
  ConsumerState<_ProductHeart> createState() => _ProductHeartState();
}

class _ProductHeartState extends ConsumerState<_ProductHeart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  bool? _localFav;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
    _scale = Tween<double>(begin: 1.0, end: 1.4)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    final notifier = ref.read(favoritesProvider.notifier);

    // Optimistic toggle
    final isFav = _localFav ??
        (ref.read(favoritesProvider).asData?.value.contains(widget.productId) ??
            false);

    setState(() => _localFav = !isFav);

    _controller.forward().then((_) => _controller.reverse());

    try {
      await notifier.toggle(widget.productId);
    } catch (e) {
      if (mounted) setState(() => _localFav = isFav); // Rollback on error
    }
  }

  @override
  Widget build(BuildContext context) {
    final favsValue = ref.watch(favoritesProvider);

    // Sync local state once loaded — assign directly so the current build frame
    // already has the correct value; no setState/addPostFrameCallback needed
    // because ref.watch above already drives the rebuild.
    favsValue.whenData((ids) {
      _localFav ??= ids.contains(widget.productId);
    });

    final bool isFav = _localFav ??
        (favsValue.asData?.value.contains(widget.productId) ?? false);

    return GestureDetector(
      onTap: _onTap,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? Colors.red : Colors.grey.shade400,
            size: 16,
          ),
        ),
      ),
    );
  }
}

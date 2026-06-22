import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../models/shop_product_model.dart';
import '../../../core/state/auth_store.dart';

/// Service for toggling and fetching user favorites from the backend.
class FavoritesService {
  final ApiClient _apiClient;
  FavoritesService(this._apiClient);

  /// POST /api/app/favorites  →  { "message": "...", "isFavorite": true/false }
  Future<bool> toggleFavorite(String productId) async {
    try {
      final response = await _apiClient.post(
        '${ApiClient.baseUrl}/favorites',
        data: {'productId': productId, 'product_id': productId},
        requiresAuth: true,
      );
      debugPrint('[FavoritesService] toggleFavorite response: $response');

      final bool? isFav = response['isFavorite'] as bool?;
      if (isFav != null) return isFav;

      // Fallback: derive from message
      final message = response['message']?.toString().toLowerCase() ?? '';
      return message.contains('added') || message.contains('add');
    } catch (e) {
      debugPrint('[FavoritesService] toggleFavorite error: $e');
      rethrow;
    }
  }

  /// GET /api/app/favorites  →  list of favourite products
  Future<List<ShopProduct>> getFavoriteProducts() async {
    try {
      final response = await _apiClient.get(
        '${ApiClient.baseUrl}/favorites',
        requiresAuth: true,
      );
      debugPrint('[FavoritesService] getFavoriteProducts response type: ${response.runtimeType}');

      List<dynamic> items = [];
      if (response is List) {
        items = response;
      } else if (response is Map) {
        final raw = response['favorites'] ?? response['data'] ?? response['items'];
        if (raw is List) items = raw;
      }

      final products = items.map((item) {
        // Handle both nested { product: {...} } and flat product objects
        final productData = item is Map && item['product'] is Map
            ? item['product'] as Map<String, dynamic>
            : (item is Map ? item as Map<String, dynamic> : <String, dynamic>{});
        return ShopProduct.fromJson(productData);
      }).where((p) => p.id.isNotEmpty).toList();

      debugPrint('[FavoritesService] loaded ${products.length} favorite products');
      return products;
    } catch (e) {
      debugPrint('[FavoritesService] getFavoriteProducts error: $e');
      return [];
    }
  }

  /// Convenience wrapper: return only IDs (for heart-toggle state).
  Future<Set<String>> getFavoriteIds() async {
    final products = await getFavoriteProducts();
    return products.map((p) => p.id).toSet();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final favoritesServiceProvider = Provider<FavoritesService>((ref) {
  return FavoritesService(ref.watch(apiClientProvider));
});

/// Holds the SET of favorited product IDs.
/// Drives the heart-toggle visual on every product card.
/// Updated OPTIMISTICALLY first, then reconciled with the server response.
class FavoritesNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final isAuthenticated = ref.watch(isAuthenticatedProvider);
    if (!isAuthenticated) return {};
    final ids = await ref.read(favoritesServiceProvider).getFavoriteIds();
    debugPrint('[FavoritesNotifier] initial favorite IDs: $ids');
    return ids;
  }

  /// Toggle a product. Optimistic → API → reconcile → refresh product list.
  Future<void> toggle(String productId) async {
    final previous = state;
    final currentSet = Set<String>.from(state.asData?.value ?? {});
    final isCurrentlyFav = currentSet.contains(productId);

    // 1. Optimistic update: flip state IMMEDIATELY so heart turns red/grey NOW
    final updated = Set<String>.from(currentSet);
    if (isCurrentlyFav) {
      updated.remove(productId);
    } else {
      updated.add(productId);
    }
    state = AsyncData(updated);

    try {
      // 2. Call backend
      final isFavNow = await ref.read(favoritesServiceProvider).toggleFavorite(productId);

      // 3. Reconcile with server truth
      final reconciled = Set<String>.from(updated);
      if (isFavNow) {
        reconciled.add(productId);
      } else {
        reconciled.remove(productId);
      }
      state = AsyncData(reconciled);

      // 4. Refresh the full product list so FavoritesPage immediately shows/hides the item
      ref.invalidate(favoriteProductsProvider);

      debugPrint('[FavoritesNotifier] toggled $productId → isFav=$isFavNow, total=${reconciled.length}');
    } catch (e) {
      debugPrint('[FavoritesNotifier] toggle failed, rolling back: $e');
      state = previous;
      rethrow;
    }
  }
}

final favoritesProvider =
    AsyncNotifierProvider<FavoritesNotifier, Set<String>>(() {
  return FavoritesNotifier();
});

/// Full [ShopProduct] list for the current user's favorites.
/// Non-autoDispose → keeps data alive across page navigations.
/// Invalidated explicitly by [FavoritesNotifier.toggle] after every API call.
final favoriteProductsProvider = FutureProvider<List<ShopProduct>>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  if (!isAuthenticated) return [];
  return ref.read(favoritesServiceProvider).getFavoriteProducts();
});

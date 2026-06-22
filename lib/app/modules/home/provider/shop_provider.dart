import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../data/models/shop_product_model.dart';
import '../../../data/services/shop_service.dart';
import '../../../data/services/socket_service.dart';
import '../../../data/services/location_service.dart';
import '../../../core/utils/loader_utils.dart';

final shopsListProvider =
    AsyncNotifierProvider<ShopsNotifier, List<ShopModel>>(ShopsNotifier.new);

class ShopsNotifier extends AsyncNotifier<List<ShopModel>> {
  @override
  Future<List<ShopModel>> build() async {
    final service = ref.watch(shopServiceProvider);
    final shops = await LoaderUtils.wrapWithSkeleton(
      () => service.getShops().timeout(const Duration(seconds: 20)),
    );

    // Listen for real-time shop status updates — deregister first to prevent
    // listener stacking if build() is called more than once.
    final socket = ref.read(socketServiceProvider);
    socket.offShopStatusUpdate();
    socket.onShopStatusUpdate((data) {
      _handleShopStatusUpdate(data);
    });

    ref.onDispose(() {
      socket.offShopStatusUpdate();
    });

    return shops;
  }

  void _handleShopStatusUpdate(dynamic data) {
    if (data is Map<String, dynamic>) {
      final String? shopId = data['shopId']?.toString();
      final bool? isShopActive = data['isShopActive'] as bool?;

      if (shopId != null && isShopActive != null) {
        state.whenData((shops) {
          final updatedShops = shops.map((s) {
            if (s.id == shopId) {
              return s.copyWith(isShopActive: isShopActive);
            }
            return s;
          }).toList();
          state = AsyncData(updatedShops);
        });
      }
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
        () => LoaderUtils.wrapWithSkeleton(
          () => ref.read(shopServiceProvider).getShops().timeout(const Duration(seconds: 20)),
        ));
  }
}

final shopProductsProvider =
    FutureProvider.family<List<ShopProduct>, String>((ref, shopId) async {
  final service = ref.read(shopServiceProvider);
  return LoaderUtils.wrapWithSkeleton(() => service.getShopProducts(shopId));
});

/// Resolves the user's current GPS position once per session.
/// Returns null silently if permission is denied or GPS is off.
final userLocationProvider = FutureProvider<Position?>(
  (ref) async {
    try {
      return await ref.read(locationServiceProvider).getCurrentLocation();
    } catch (_) {
      return null;
    }
  },
);

/// Calculates the straight-line distance between the user and a shop.
/// Returns a human-readable label like "1.2 km" or "800 m", or null if
/// either coordinate is missing.
String? shopDistanceLabel({
  required Position? userPos,
  required double? shopLat,
  required double? shopLng,
}) {
  if (userPos == null || shopLat == null || shopLng == null) return null;
  final meters = Geolocator.distanceBetween(
    userPos.latitude,
    userPos.longitude,
    shopLat,
    shopLng,
  );
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

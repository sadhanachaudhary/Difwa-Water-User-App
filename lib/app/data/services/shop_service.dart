import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/shop_product_model.dart';
import '../models/food_models.dart';
import '../models/banner_model.dart';
import '../network/api_client.dart';
import 'package:flutter/foundation.dart';

/// Provider for ShopService
final shopServiceProvider = Provider<ShopService>((ref) {
  return ShopService(client: ref.watch(apiClientProvider));
});

/// Reactive Provider for a specific shop's details
final shopDetailsProvider = FutureProvider.family<ShopModel?, String>((ref, id) {
  if (id.isEmpty) return Future.value(null);
  return ref.watch(shopServiceProvider).getShopDetails(id);
});

/// Reactive Provider for app banners
final bannersProvider = FutureProvider<List<AppBanner>>((ref) {
  return ref.watch(shopServiceProvider).getBanners();
});

/// Service layer for shops.

class ShopService {
  final ApiClient _client;

  ShopService({required ApiClient client}) : _client = client;

  Future<List<ShopModel>> getShops() async {
    try {
      final json = await _client.get(
        '${ApiClient.baseUrl}/shops',
        requiresAuth: false,
      );

      final raw = json['data'] as List<dynamic>? ?? [];
      
      // Senior Dev: Offload complex shop listing to isolate
      return await compute(_parseShops, raw);
    } catch (e) {
      debugPrint('ShopService: Error fetching shops: $e');
      return [];
    }
  }

  static List<ShopModel> _parseShops(List<dynamic> data) {
    return data
        .map((e) => ShopModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ShopProduct>> getShopProducts(String shopId) async {
    try {
      final json = await _client.get(
        '${ApiClient.baseUrl}/shops/$shopId/products',
        requiresAuth: false,
      );
      final raw = (json['data'] ?? json['products']) as List<dynamic>? ?? [];
      
      // Senior Dev: Background thread for shop product parsing
      return await compute(_parseShopProducts, raw);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
          message:
              'Failed to fetch products for shop $shopId: ${e.toString()}');
    }
  }

  static List<ShopProduct> _parseShopProducts(List<dynamic> data) {
    return data
        .map((e) => ShopProduct.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FoodCategory>> getCategories() async {
    try {
      final json = await _client.get(
        '${ApiClient.baseUrl}/categories',
        requiresAuth: false,
      );
      final raw = json['data'] as List<dynamic>? ?? [];
      
      // Senior Dev: Isolate for category mapping
      return await compute(_parseCategories, raw);
    } catch (e) {
      debugPrint('ShopService: Error fetching categories: $e');
      return [];
    }
  }

  static List<FoodCategory> _parseCategories(List<dynamic> data) {
    return data
        .map((e) => FoodCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ShopModel?> getShopDetails(String shopId) async {
    try {
      final json = await _client.get(
        '${ApiClient.baseUrl}/shops/$shopId',
        requiresAuth: false,
      );
      final data = json['data'] ?? json;
      return ShopModel.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('ShopService: Error fetching shop details for $shopId: $e');
      return null;
    }
  }

  Future<List<DeliverySlotAvailability>> getShopSlots(String shopId, {String? date}) async {
    try {
      final json = await _client.get(
        '${ApiClient.baseUrl}/shops/$shopId/slots',
        queryParameters: date != null ? {'date': date} : null,
        requiresAuth: false,
      );
      final raw = (json['data'] ?? json['deliverySlotsAvailability'] ?? json) as List<dynamic>? ?? [];
      return raw.map((e) => DeliverySlotAvailability.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('ShopService: Error fetching shop slots for $shopId: $e');
      return [];
    }
  }

  Future<List<AppBanner>> getBanners() async {
    try {
      final json = await _client.get(
        '/banners/app',
        requiresAuth: false,
      );
      debugPrint('ShopService: Raw banners response: $json (Type: ${json.runtimeType})');
      
      List<dynamic> raw = [];
      if (json is List) {
        raw = json;
      } else if (json is Map) {
        raw = (json['data'] ?? json['banners'] ?? json['results'] ?? []) as List<dynamic>;
      }
      
      return raw.map((e) => AppBanner.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('ShopService: Error fetching banners: $e');
      return [];
    }
  }

  Future<Product?> getProductDetails(String productId) async {
    try {
      final json = await _client.get(
        '/products/$productId',
        requiresAuth: false,
      );
      final data = json['data'] ?? json;
      return Product.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('ShopService: Error fetching product details for $productId: $e');
      return null;
    }
  }

  Future<AppBanner?> createBanner(Map<String, dynamic> payload) async {
    try {
      final json = await _client.post(
        '/banners/app', // Note: Banners are app-wide, mapped under /banners/app
        data: payload,
        requiresAuth: true,
      );
      final data = json['data'] ?? json;
      return AppBanner.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      debugPrint('ShopService: Error creating banner: $e');
      return null;
    }
  }

  Future<bool> deleteBanner(String id) async {
    try {
      await _client.delete(
        '/banners/$id',
        requiresAuth: true,
      );
      return true;
    } catch (e) {
      debugPrint('ShopService: Error deleting banner: $e');
      return false;
    }
  }
}

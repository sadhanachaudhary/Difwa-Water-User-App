import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product_model.dart';
import '../models/food_models.dart';
import 'cart_service.dart';
import 'wallet_service.dart';
import 'address_service.dart';
import 'shop_service.dart';
import 'order_service.dart';
import 'auth_service.dart';
import '../network/api_client.dart';
import '../../core/constants/app_images.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class CartProvider extends ChangeNotifier {
  final CartService? _service;
  final WalletService? _walletService;
  final AddressService? _addressService;
  final ShopService? _shopService;
  final OrderService? _orderService;
  final AuthService? _authService;
  final List<CartItem> _items = [];

  CartProvider({
    CartService? service,
    WalletService? walletService,
    AddressService? addressService,
    ShopService? shopService,
    OrderService? orderService,
    AuthService? authService,
    UserProfile? user,
  })  : _service = service,
        _walletService = walletService,
        _addressService = addressService,
        _shopService = shopService,
        _orderService = orderService,
        _authService = authService {
    if (user != null) {
      _userProfile = user;
    }
    Future.microtask(() {
      loadCategories();
      loadAddresses();
      syncWallet();
      loadShops();
      _loadCartFromPrefs().then((_) {
        if (isLoggedIn) {
          loadCartFromApi();
        }
      });
    });
  }

  // ── Getters ───────────────────────────────────────────────────────────────
  AddressService? get addressService => _addressService;
  List<CartItem> get items => _items;
  UserProfile get userProfile => _userProfile;
  List<FoodCategory> get foodCategories => _foodCategories;
  List<Restaurant> get restaurants => _restaurants;
  List<UserOrder> get orders => _orders;
  List<UserAddress> get addresses => _addresses;

  List<UserPaymentMethod> get payments => _payments;

  UserProfile _userProfile = const UserProfile(
    name: 'Guest User',
    email: '',
    phone: '',
    profileImage: AppImages.defaultAvatar,
  );

  bool get isLoggedIn =>
      _userProfile.email.isNotEmpty || _userProfile.phone.isNotEmpty;

  List<FoodCategory> _foodCategories = [];
  final List<Restaurant> _restaurants = [];

  List<UserOrder> _orders = [];
  bool _isOrdersLoading = false;

  bool get isOrdersLoading => _isOrdersLoading;

  void setOrders(List<UserOrder> newOrders) {
    _orders = newOrders;
    notifyListeners();
  }

  void setLoadingOrders(bool loading) {
    _isOrdersLoading = loading;
    notifyListeners();
  }

  double _walletBalance = 0.0;
  List<dynamic> _transactions = [];

  double get walletBalance => _walletBalance;
  List<dynamic> get transactions => _transactions;

  bool _hasEmptyBottles = false;
  int _returnedBottlesCount = 0;
  double _bottleDepositFee = 0.0;

  bool get hasEmptyBottles => _hasEmptyBottles;
  int get returnedBottlesCount => _returnedBottlesCount;
  double get bottleDepositFee => _bottleDepositFee;

  void setHasEmptyBottles(bool val) {
    if (_hasEmptyBottles != val) {
      _hasEmptyBottles = val;
      if (!val) {
        _returnedBottlesCount = 0;
      }
      notifyListeners();
      updateDeliveryCharge();
    }
  }

  void setReturnedBottlesCount(int val) {
    if (_returnedBottlesCount != val) {
      _returnedBottlesCount = val;
      notifyListeners();
      updateDeliveryCharge();
    }
  }

  bool _isWalletSyncing = false;
  Future<void> syncWallet() async {
    if (_walletService == null || _isWalletSyncing) return;
    _isWalletSyncing = true;
    try {
      final result = await _walletService!.getBalance();
      if (result['success']) {
        _walletBalance = (result['balance'] as num).toDouble();
      }
      _transactions = await _walletService!.getTransactionHistory();
      notifyListeners();
    } catch (e) {
      debugPrint('CartProvider: Error syncing wallet: $e');
    } finally {
      _isWalletSyncing = false;
    }
  }

  Future<void> syncOrders() async {
    if (_orderService == null) return;
    try {
      final history = await _orderService!.getMyOrders();
      _orders = history;
      notifyListeners();
    } catch (e) {
      debugPrint('CartProvider: Error syncing orders: $e');
    }
  }

  Future<void> syncUserProfile() async {
    if (_authService == null) return;
    try {
      final response = await _authService!.getProfile();
      if (response.success && response.data != null) {
        final u = response.data!;
        _userProfile = UserProfile(
          name: u.fullName,
          email: u.email,
          phone: u.phoneNumber,
          profileImage: AppImages.defaultAvatar,
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint('CartProvider: Error syncing profile: $e');
    }
  }

  List<UserAddress> _addresses = [];
  bool _isAddressesLoading = false;
  int _selectedAddressIndex = 0;

  bool get isAddressesLoading => _isAddressesLoading;
  int get selectedAddressIndex => _selectedAddressIndex;

  void selectAddress(int index) {
    if (_selectedAddressIndex != index) {
      _selectedAddressIndex = index;
      notifyListeners();
      // Important: Update delivery fee whenever a DIFFERENT address is selected
      updateDeliveryCharge();
    }
  }

  UserAddress? get selectedAddress {
    if (_addresses.isEmpty) return null;
    if (_selectedAddressIndex >= 0 &&
        _selectedAddressIndex < _addresses.length) {
      return _addresses[_selectedAddressIndex];
    }
    return _addresses.firstWhere((a) => a.isDefault,
        orElse: () => _addresses.first);
  }

  final List<UserPaymentMethod> _payments = [];
  
  // ── Delivery Charge Logic ──────────────────────────────────────────────
  double _deliveryFee = 0.0;
  double _weatherSurgeFee = 0.0;
  double _nightSurgeFee = 0.0;
  double _floorChargeFee = 0.0;
  bool _isDeliverable = true;
  String _deliveryMessage = '';
  bool _isCalculatingDelivery = false;
  String? _lastCalculatedAddressId;
  String? _lastCalculatedCartHash;

  double get deliveryFee => _deliveryFee;
  double get weatherSurgeFee => _weatherSurgeFee;
  double get nightSurgeFee => _nightSurgeFee;
  double get floorChargeFee => _floorChargeFee;
  bool get isDeliverable => _isDeliverable;
  String get deliveryMessage => _deliveryMessage;
  bool get isCalculatingDelivery => _isCalculatingDelivery;

  Future<void> updateDeliveryCharge() async {
    final addr = selectedAddress;
    final vendorId = cartShopId;

    if (addr == null || vendorId == null) {
      _deliveryFee = 0.0;
      _isDeliverable = true;
      _deliveryMessage = '';
      notifyListeners();
      return;
    }

    // Hash of cart items to detect quantity changes
    final cartHash =
        _items.map((e) => '${e.id}:${e.quantity}').join('|');

    // Include floorNumber and hasLift in address key to detect floor changes on same address
    final addressKey = '${addr.id}:${addr.floorNumber ?? 0}:${addr.hasLift ?? true}';

    if (_lastCalculatedAddressId == addressKey &&
        _lastCalculatedCartHash == cartHash) {
      return; // Already calculated for this state
    }

    if (_isCalculatingDelivery) return;
    _isCalculatingDelivery = true;
    notifyListeners();

    try {
      double userLat = 0.0;
      double userLng = 0.0;
      bool hasCoordinates = false;

      // PRIORITY 1: USE ADDRESS COORDINATES (Senior Dev Best Practice)
      // Use the coordinates explicitly saved with the address (from Map Picker)
      if (addr.latitude != null && addr.longitude != null && addr.latitude != 0 && addr.longitude != 0) {
        userLat = addr.latitude!;
        userLng = addr.longitude!;
        hasCoordinates = true;
      } 
      
      // PRIORITY 2: USE CURRENT GPS (Fallback only)
      if (!hasCoordinates) {
        try {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse) {
            final position = await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high);
            userLat = position.latitude;
            userLng = position.longitude;
            hasCoordinates = true;
          }
        } catch (e) {
          debugPrint('CartProvider: GPS fallback error: $e');
        }
      }

      final itemsMap = _items
          .map((item) => {
                'product': item.id,
                'retailer': item.shopId,
                'quantity': item.quantity,
                'price': item.unitPrice,
              })
          .toList();

      final result = await _orderService!.calculateDeliveryCharge(
        vendorId: vendorId,
        userLat: userLat,
        userLng: userLng,
        items: itemsMap,
        hasEmptyBottles: _hasEmptyBottles,
        returnedBottlesCount: _returnedBottlesCount,
        floorNumber: addr.floorNumber,
        hasLift: addr.hasLift,
      );

      if (result['success']) {
        _deliveryFee = (result['deliveryFee'] as num? ?? 0.0).toDouble();
        _bottleDepositFee = (result['bottleDepositFee'] as num? ?? 0.0).toDouble();
        _weatherSurgeFee = (result['weatherSurgeFee'] as num? ?? 0.0).toDouble();
        _nightSurgeFee = (result['nightSurgeFee'] as num? ?? 0.0).toDouble();
        _floorChargeFee = (result['floorChargeFee'] as num? ?? 0.0).toDouble();
        _isDeliverable = result['deliverable'] ?? true;
        _deliveryMessage = result['message'] ?? '';
        final addressKey = '${addr.id}:${addr.floorNumber ?? 0}:${addr.hasLift ?? true}';
        _lastCalculatedAddressId = addressKey;
        _lastCalculatedCartHash = cartHash;
      }
    } catch (e) {
      debugPrint('CartProvider: Error calculating delivery charge: $e');
    } finally {
      _isCalculatingDelivery = false;
      notifyListeners();
    }
  }

  void updateUserProfile(UserProfile profile) {
    _userProfile = profile;
    notifyListeners();
  }

  void clearSession() {
    _userProfile = const UserProfile(
      name: 'Guest User',
      email: '',
      phone: '',
      profileImage: AppImages.defaultAvatar,
    );
    _items.clear();
    _favoriteIds.clear();
    _addresses.clear();
    _orders.clear();
    _transactions.clear();
    _walletBalance = 0.0;
    _selectedAddressIndex = 0;
    _saveCartToPrefs();
    notifyListeners();
  }

  Future<void> _loadCartFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cartJsonStr = prefs.getString('cached_cart_items');
      if (cartJsonStr != null && cartJsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(cartJsonStr);
        final List<CartItem> cachedItems = decoded
            .map((e) => CartItem.fromJson(Map<String, dynamic>.from(e)))
            .where((item) => item.id.isNotEmpty && item.quantity > 0)
            .toList();
        _items.clear();
        _items.addAll(cachedItems);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('CartProvider: Error loading cart from prefs: $e');
    }
  }

  Future<void> _saveCartToPrefs() async {
    try {
      _items.removeWhere((item) => item.quantity <= 0 || item.id.isEmpty);
      final prefs = await SharedPreferences.getInstance();
      final cartJsonStr = jsonEncode(_items.map((e) => e.toJson()).toList());
      await prefs.setString('cached_cart_items', cartJsonStr);
    } catch (e) {
      debugPrint('CartProvider: Error saving cart to prefs: $e');
    }
  }

  /// Syncs local guest cart items to the server after login.
  Future<void> syncLocalCartToServer() async {
    if (!isLoggedIn || _service == null || _items.isEmpty) return;

    debugPrint('🛒 Syncing ${_items.length} local items to server...');
    for (final item in _items) {
      try {
        await _service!.addToCart(item.id, item.quantity);
      } catch (e) {
        debugPrint('⚠️ Failed to sync item ${item.title} to server: $e');
      }
    }
    // After syncing, reload the full cart from API to ensure everything is in sync
    await loadCartFromApi();
  }

  // ── API Integration ───────────────────────────────────────────────────────
  Future<void> loadCategories() async {
    if (_shopService == null) return;
    try {
      _foodCategories = await _shopService!.getCategories();
      notifyListeners();
    } catch (e) {
      debugPrint('CartProvider: Error loading categories: $e');
    }
  }

  Future<void> loadShops() async {
    if (_shopService == null) return;
    try {
      final shops = await _shopService!.getShops();
      _restaurants.clear();
      // Map ShopModel to Restaurant model used in Home UI
      for (var s in shops) {
        _restaurants.add(Restaurant(
          id: s.id,
          name: s.name,
          image: s.image,
          rating: s.rating,
          deliveryTime: s.deliveryTime,
          discount: 'Free Delivery',
          minOrder: '₹0 min',
        ));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('CartProvider: Error loading shops: $e');
    }
  }

  Future<void> loadCartFromApi() async {
    if (_service == null) return;
    try {
      final remoteItems = await _service!.getCart();
      final validItems = remoteItems
          .where((item) => item.id.isNotEmpty && item.quantity > 0)
          .toList();
      _items.clear();
      _items.addAll(validItems);
      _saveCartToPrefs();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading cart from API: $e');
    }
  }

  final List<String> _favoriteIds = [];

  List<Restaurant> get favRestaurants {
    if (_restaurants.isEmpty) return [];
    return _favoriteIds
        .map((id) => _restaurants.firstWhere((r) => r.id == id,
            orElse: () => _restaurants.first))
        .toList();
  }

  bool isFavorite(String id) => _favoriteIds.contains(id);

  void toggleFavorite(String id) {
    if (_favoriteIds.contains(id)) {
      _favoriteIds.remove(id);
    } else {
      _favoriteIds.add(id);
    }
    notifyListeners();
  }

  void reorderFavorites(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    final String item = _favoriteIds.removeAt(oldIndex);
    _favoriteIds.insert(newIndex, item);
    notifyListeners();
  }

  Future<Map<String, dynamic>> addAddress(UserAddress address) async {
    if (_addressService != null) {
      try {
        // Robust parsing of details string (matches AddressFormPage.initState)
        final detailsStr = address.details;
        final parts = detailsStr.split(',');
        String cityName = 'City';
        String stateName = '';
        String pincodeStr = '';

        if (parts.isNotEmpty) {
          cityName = parts[0].trim();
          if (parts.length > 1) {
            final statePin = parts[1].trim();
            if (statePin.contains(' ')) {
              pincodeStr = statePin.split(' ').last;
              stateName = statePin.substring(0, statePin.lastIndexOf(' ')).trim();
            } else {
              stateName = statePin;
            }
          }
        }

        // Fallback geocoding if coordinates are missing
        double? lat = address.latitude;
        double? lng = address.longitude;
        if (lat == null || lng == null || (lat == 0 && lng == 0)) {
          try {
            final fullAddr = '${address.street}, ${address.details}';
            final locations = await locationFromAddress(fullAddr).timeout(const Duration(seconds: 3));
            if (locations.isNotEmpty) {
              lat = locations.first.latitude;
              lng = locations.first.longitude;
            }
          } catch (e) {
            debugPrint('CartProvider: Geocoding fallback failed for Add: $e');
          }
        }

        final result = await _addressService!.saveAddress(
          fullName: address.fullName,
          email: address.email,
          label: address.title,
          fullAddress: address.street,
          city: cityName,
          state: stateName,
          pincode: pincodeStr,
          isDefault: address.isDefault,
          latitude: lat,
          longitude: lng,
          floorNumber: address.floorNumber,
          hasLift: address.hasLift,
        );
        final bool isSuccess = result['success'] == true || result['data'] != null || result['_id'] != null;
        if (isSuccess) {
          await loadAddresses();
          // Auto-select the newly added address
          if (_addresses.isNotEmpty) {
            String? newId;
            if (result is Map) {
              final rawId = result['_id'] ?? result['id'];
              if (rawId != null) {
                newId = rawId.toString();
              } else if (result['data'] is Map) {
                final dataId = result['data']['_id'] ?? result['data']['id'];
                if (dataId != null) newId = dataId.toString();
              } else if (result['address'] is Map) {
                final addrId = result['address']['_id'] ?? result['address']['id'];
                if (addrId != null) newId = addrId.toString();
              }
            }
            int newIdx = -1;
            if (newId != null && newId.isNotEmpty) {
              newIdx = _addresses.indexWhere((a) => a.id == newId);
            }
            if (newIdx == -1) {
              newIdx = _addresses.indexWhere((a) => a.title == address.title && a.street == address.street);
            }
            if (newIdx != -1) {
              _selectedAddressIndex = newIdx;
              notifyListeners();
            }
          }
        }
        return result;
      } catch (e) {
        debugPrint('CartProvider: Error adding address: $e');
        return {'success': false, 'message': e.toString()};
      }
    } else {
      // Offline fallback
      if (address.isDefault) {
        for (int i = 0; i < _addresses.length; i++) {
          _addresses[i] = _addresses[i].copyWith(isDefault: false);
        }
      }
      _addresses.add(address);
      notifyListeners();
      return {'success': true};
    }
  }

  Future<void> loadAddresses() async {
    if (_addressService == null) return;
    _isAddressesLoading = true;
    notifyListeners();

    try {
      final token = await ApiClient.getToken();
      if (token == null || token.isEmpty) {
        _isAddressesLoading = false;
        notifyListeners();
        return;
      }

      final result = await _addressService!.getAddresses();
      if (result['success']) {
        final List<dynamic> data = result['data'] ?? [];
        // Preserve selection by ID if possible
        final previousId = _addresses.isNotEmpty && _selectedAddressIndex < _addresses.length 
            ? _addresses[_selectedAddressIndex].id 
            : null;

        _addresses = data.map((json) {
          // ... (mapping logic)
          final city = json['city'] ?? '';
          final state = json['state'] ?? '';
          final pincode = json['pincode'] ?? '';

          String detailsStr = '$city, $state';
          if (pincode.isNotEmpty &&
              !state.toString().contains(pincode.toString())) {
            detailsStr += ' $pincode';
          }

          double? lat = (json['latitude'] as num?)?.toDouble();
          double? lng = (json['longitude'] as num?)?.toDouble();

          if (lat == null || lng == null) {
            final coords = json['coordinates'];
            if (coords is Map) {
              lat = _parseNum(coords['latitude'] ?? coords['lat']);
              lng = _parseNum(coords['longitude'] ?? coords['lng']);
            } else if (coords is List && coords.length >= 2) {
              lng = _parseNum(coords[0]);
              lat = _parseNum(coords[1]);
            }
          }

          return UserAddress(
            id: json['_id'] ?? '',
            title: json['label'] ?? 'Address',
            street: json['fullAddress'] ?? '',
            details: detailsStr,
            fullName: json['fullName'] ?? '',
            email: json['email'] ?? '',
            isDefault: json['isDefault'] ?? false,
            latitude: lat,
            longitude: lng,
            floorNumber: json['floorNumber'] != null ? int.tryParse(json['floorNumber'].toString()) : null,
            hasLift: json['hasLift'] == null ? true : (json['hasLift'] == true || json['hasLift'] == 1 || json['hasLift'].toString() == 'true'),
          );
        }).toList();

        if (previousId != null) {
          final newIdx = _addresses.indexWhere((a) => a.id == previousId);
          if (newIdx != -1) {
            _selectedAddressIndex = newIdx;
          } else {
            // Fallback to default if previous selection is gone
            final defaultIdx = _addresses.indexWhere((a) => a.isDefault);
            _selectedAddressIndex = defaultIdx != -1 ? defaultIdx : 0;
          }
        } else {
          // Initial load
          final defaultIdx = _addresses.indexWhere((a) => a.isDefault);
          _selectedAddressIndex = defaultIdx != -1 ? defaultIdx : 0;
        }
      }
    } catch (e) {
      debugPrint('Error loading addresses: $e');
    } finally {
      _isAddressesLoading = false;
      notifyListeners();
      // Calculate delivery fee for the newly loaded/selected address
      updateDeliveryCharge();
    }
  }

  Future<Map<String, dynamic>> updateAddress(UserAddress address) async {
    if (_addressService != null) {
      // Robust parsing of details string (matches AddressFormPage.initState)
      final detailsStr = address.details;
      final parts = detailsStr.split(',');
      String cityName = 'City';
      String stateName = '';
      String pincodeStr = '';

      if (parts.isNotEmpty) {
        cityName = parts[0].trim();
        if (parts.length > 1) {
          final statePin = parts[1].trim();
          if (statePin.contains(' ')) {
            pincodeStr = statePin.split(' ').last;
            stateName = statePin.substring(0, statePin.lastIndexOf(' ')).trim();
          } else {
            stateName = statePin;
          }
        }
      }

      try {
        // Fallback geocoding if coordinates are missing
        double? lat = address.latitude;
        double? lng = address.longitude;
        if (lat == null || lng == null || (lat == 0 && lng == 0)) {
          try {
            final fullAddr = '${address.street}, ${address.details}';
            final locations = await locationFromAddress(fullAddr).timeout(const Duration(seconds: 3));
            if (locations.isNotEmpty) {
              lat = locations.first.latitude;
              lng = locations.first.longitude;
            }
          } catch (e) {
            debugPrint('CartProvider: Geocoding fallback failed for Update: $e');
          }
        }

        final result = await _addressService!.updateAddress(
          id: address.id,
          fullName: address.fullName,
          email: address.email,
          label: address.title,
          fullAddress: address.street,
          city: cityName,
          state: stateName,
          pincode: pincodeStr,
          isDefault: address.isDefault,
          latitude: lat,
          longitude: lng,
          floorNumber: address.floorNumber,
          hasLift: address.hasLift,
        );
        final bool isSuccess = result['success'] == true || result['data'] != null || result['_id'] != null;
        if (isSuccess) {
          await loadAddresses();
        }
        return result;
      } catch (e) {
        debugPrint('CartProvider: Error updating address: $e');
        return {'success': false, 'message': e.toString()};
      }
    } else {
      final index = _addresses.indexWhere((a) => a.id == address.id);
      if (index != -1) {
        if (address.isDefault) {
          for (int i = 0; i < _addresses.length; i++) {
            _addresses[i] = _addresses[i].copyWith(isDefault: false);
          }
        }
        _addresses[index] = address;
        notifyListeners();
      }
      return {'success': true};
    }
  }

  Future<void> removeAddress(String id) async {
    if (_addressService != null) {
      try {
        final result = await _addressService!.deleteAddress(id);
        if (result['success'] ?? true) {
          // Refresh the address list from the server
          await loadAddresses();
        }
      } catch (e) {
        debugPrint('CartProvider: Error deleting address: $e');
      }
    } else {
      _addresses.removeWhere((a) => a.id == id);
      if (_lastCalculatedAddressId == id) {
        _lastCalculatedAddressId = null;
      }
      notifyListeners();
    }
  }

  int get itemCount {
    return _items
        .where((item) => item.id.isNotEmpty && item.quantity > 0)
        .fold(0, (sum, item) => sum + item.quantity);
  }

  double get subtotal {
    return _items
        .where((item) => item.id.isNotEmpty && item.quantity > 0)
        .fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  double get shippingCharges => _deliveryFee;
  double get total => subtotal + shippingCharges + _bottleDepositFee + _weatherSurgeFee + _nightSurgeFee + _floorChargeFee;

  bool isInCart(String title) {
    return _items.any((item) => item.title == title && item.quantity > 0);
  }

  String? get cartShopId => _items.isEmpty ? null : _items.first.shopId;
  String? get cartShopName => _items.isEmpty ? null : _items.first.shopName;

  bool isSameShop(String? shopId) {
    if (_items.isEmpty) return true;
    if (shopId == null) return true;
    // Check if any item in cart belongs to a different shop
    return _items.every((item) => item.shopId == shopId);
  }

  void addToCart(CartItem cartItem) {
    if (cartItem.id.isEmpty || cartItem.quantity <= 0) return;
    final idx = _items.indexWhere((item) =>
        (item.id.isNotEmpty && cartItem.id.isNotEmpty && item.id == cartItem.id) ||
        (item.id.isEmpty && item.title == cartItem.title && item.shopId == cartItem.shopId));
    if (idx >= 0) {
      _items[idx].quantity += cartItem.quantity;
      if (isLoggedIn && _service != null) {
        _service!.updateQuantity(_items[idx].id, _items[idx].quantity);
      }
    } else {
      _items.add(cartItem);
      if (isLoggedIn && _service != null) {
        _service!.addToCart(cartItem.id, cartItem.quantity);
      }
    }
    _saveCartToPrefs();
    notifyListeners();
    updateDeliveryCharge();
  }

  void increment(String id) {
    if (id.isEmpty) return;
    final idx = _items.indexWhere((item) => item.id == id);
    if (idx >= 0) {
      _items[idx].quantity++;
      if (isLoggedIn && _service != null) {
        _service!.updateQuantity(_items[idx].id, _items[idx].quantity);
      }
      _saveCartToPrefs();
      notifyListeners();
      updateDeliveryCharge();
    }
  }

  void decrement(String id) {
    if (id.isEmpty) return;
    final idx = _items.indexWhere((item) => item.id == id);
    if (idx >= 0) {
      final itemId = _items[idx].id;
      if (_items[idx].quantity > 1) {
        _items[idx].quantity--;
        if (isLoggedIn && _service != null) {
          _service!.updateQuantity(itemId, _items[idx].quantity);
        }
      } else {
        _items.removeAt(idx);
        if (isLoggedIn && _service != null) {
          _service!.removeFromCart(itemId);
        }
      }
      _saveCartToPrefs();
      notifyListeners();
      updateDeliveryCharge();
    }
  }

  void removeItem(String id) {
    if (id.isEmpty) return;
    final idx = _items.indexWhere((item) => item.id == id);
    if (idx >= 0) {
      final itemId = _items[idx].id;
      _items.removeAt(idx);
      if (isLoggedIn && _service != null) {
        _service!.removeFromCart(itemId);
      }
      _saveCartToPrefs();
      notifyListeners();
      updateDeliveryCharge();
    }
  }

  void clearCart() {
    _items.clear();
    if (_service != null) {
      _service!.clearCart();
    }
    _saveCartToPrefs();
    notifyListeners();
    updateDeliveryCharge();
  }

  Future<Map<String, dynamic>> checkout({
    String paymentMethod = 'Wallet',
    String? deliverySlot,
  }) async {
    if (_orderService == null) {
      return {'success': false, 'message': 'Order service not available'};
    }
    if (selectedAddress == null) {
      return {'success': false, 'message': 'Please select a delivery address'};
    }

    final addr = selectedAddress!;
    // Parse address details back to parts for the API
    // Robust parsing for checkout
    final detailsStr = addr.details;
    final parts = detailsStr.split(',');
    String cityName = '';
    String stateName = '';
    String pincodeStr = '';

    if (parts.isNotEmpty) {
      cityName = parts[0].trim();
      if (parts.length > 1) {
        final statePin = parts[1].trim();
        if (statePin.contains(' ')) {
          pincodeStr = statePin.split(' ').last;
          stateName = statePin.substring(0, statePin.lastIndexOf(' ')).trim();
        } else {
          stateName = statePin;
        }
      }
    }

    final deliveryAddress = {
      'fullName': addr.fullName.isNotEmpty ? addr.fullName : _userProfile.name,
      'address': addr.street,
      'fullAddress': addr.street,
      'street': addr.street,
      'city': cityName,
      'state': stateName,
      'pincode': pincodeStr,
      'phone': addr.email.isNotEmpty ? addr.email : _userProfile.phone, // fallback or direct if stored
      'phoneNumber': _userProfile.phone,
      'label': addr.title,
    };

    final itemsMap = _items
        .map((item) => {
              'product': item.id,
              'retailer': item.shopId,
              'quantity': item.quantity,
              'price': item.unitPrice,
            })
        .toList();

    final result = await _orderService!.placeOrder(
      items: itemsMap,
      totalAmount: total,
      deliveryAddress: deliveryAddress,
      paymentMethod: paymentMethod,
      deliverySlot: deliverySlot,
      hasEmptyBottles: _hasEmptyBottles,
      returnedBottlesCount: _returnedBottlesCount,
      floorNumber: addr.floorNumber,
      hasLift: addr.hasLift,
    );

    if (result['success']) {
      _items.clear();
      _saveCartToPrefs();
      notifyListeners();
      // Update wallet balance after purchase
      syncWallet();
    }
    return result;
  }

  double? _parseNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}

class CartProviderScope extends InheritedNotifier<CartProvider> {
  const CartProviderScope({
    super.key,
    required CartProvider provider,
    required super.child,
  }) : super(notifier: provider);

  static CartProvider of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CartProviderScope>()!
        .notifier!;
  }
}

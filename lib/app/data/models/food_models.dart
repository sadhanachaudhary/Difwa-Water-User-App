class FoodCategory {
  final String id;
  final String name;
  final String image;
  final int colorValue; // Hex color for the circular background
  final String? iconPath; // Optional path for thematic icons

  const FoodCategory({
    required this.id,
    required this.name,
    required this.image,
    this.colorValue = 0xFFF7F8FA,
    this.iconPath,
  });

  factory FoodCategory.fromJson(Map<String, dynamic> json) {
    return FoodCategory(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      image: json['image']?.toString() ?? '',
      colorValue: json['colorValue'] != null
          ? int.tryParse(json['colorValue'].toString()) ?? 0xFFF7F8FA
          : 0xFFF7F8FA,
      iconPath: json['iconPath']?.toString(),
    );
  }
}

class Restaurant {
  final String id;
  final String name;
  final String image;
  final double rating;
  final String deliveryTime;
  final String discount;
  final String minOrder;
  final List<String> categories;
  final bool isPromoted;

  const Restaurant({
    required this.id,
    required this.name,
    required this.image,
    required this.rating,
    required this.deliveryTime,
    required this.discount,
    required this.minOrder,
    this.categories = const [],
    this.isPromoted = false,
  });
}

class UserOrder {
  final String id;
  final String status;
  final double total;
  final double deliveryFee;
  final double distance;
  final DateTime date;
  final List<UserOrderItem> items;
  final Map<String, dynamic>? rider;
  final Map<String, dynamic>? deliveryAddressMap;
  final String? deliveryAddressStr;
  final bool isReviewed;
  final double bottleDepositFee;
  final bool hasEmptyBottles;
  final int returnedBottlesCount;

  const UserOrder({
    required this.id,
    required this.status,
    required this.total,
    this.deliveryFee = 0.0,
    this.distance = 0.0,
    required this.date,
    required this.items,
    this.rider,
    this.deliveryAddressMap,
    this.deliveryAddressStr,
    this.deliverySlot,
    this.orderType,
    this.retailer,
    this.isReviewed = false,
    this.deliveryOtp,
    this.deliveryOtpExpiresAt,
    this.cancelReason,
    this.cancelledBy,
    this.bottleDepositFee = 0.0,
    this.hasEmptyBottles = false,
    this.returnedBottlesCount = 0,
  });

  UserOrder copyWith({
    String? id,
    String? status,
    double? total,
    double? deliveryFee,
    double? distance,
    DateTime? date,
    List<UserOrderItem>? items,
    Map<String, dynamic>? rider,
    Map<String, dynamic>? deliveryAddressMap,
    String? deliveryAddressStr,
    bool? isReviewed,
    String? deliverySlot,
    String? orderType,
    Map<String, dynamic>? retailer,
    String? deliveryOtp,
    DateTime? deliveryOtpExpiresAt,
    String? cancelReason,
    String? cancelledBy,
    double? bottleDepositFee,
    bool? hasEmptyBottles,
    int? returnedBottlesCount,
  }) {
    return UserOrder(
      id: id ?? this.id,
      status: status ?? this.status,
      total: total ?? this.total,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      distance: distance ?? this.distance,
      date: date ?? this.date,
      items: items ?? this.items,
      rider: rider ?? this.rider,
      deliveryAddressMap: deliveryAddressMap ?? this.deliveryAddressMap,
      deliveryAddressStr: deliveryAddressStr ?? this.deliveryAddressStr,
      isReviewed: isReviewed ?? this.isReviewed,
      deliverySlot: deliverySlot ?? this.deliverySlot,
      orderType: orderType ?? this.orderType,
      retailer: retailer ?? this.retailer,
      deliveryOtp: deliveryOtp ?? this.deliveryOtp,
      deliveryOtpExpiresAt: deliveryOtpExpiresAt ?? this.deliveryOtpExpiresAt,
      cancelReason: cancelReason ?? this.cancelReason,
      cancelledBy: cancelledBy ?? this.cancelledBy,
      bottleDepositFee: bottleDepositFee ?? this.bottleDepositFee,
      hasEmptyBottles: hasEmptyBottles ?? this.hasEmptyBottles,
      returnedBottlesCount: returnedBottlesCount ?? this.returnedBottlesCount,
    );
  }

  final String? deliverySlot;
  final String? orderType;
  final Map<String, dynamic>? retailer;
  final String? deliveryOtp;
  final DateTime? deliveryOtpExpiresAt;
  final String? cancelReason;
  final String? cancelledBy;

  String get riderName => rider?['fullName'] ?? rider?['name'] ?? '';
  String get riderPhone => rider?['phoneNumber'] ?? rider?['phone'] ?? '';
  
  String get plantName => retailer?['businessDetails']?['storeDisplayName'] ?? 
                          retailer?['fullName'] ?? 
                          retailer?['name'] ?? 
                          '';
  String get plantPhone => retailer?['phoneNumber'] ?? retailer?['phone'] ?? '';
  
  bool get isSubscription => orderType?.toLowerCase() == 'subscription';

  String get deliveryAddress {
    if (deliveryAddressMap == null) {
      return deliveryAddressStr ?? 'Your delivery address';
    }
    final name = deliveryAddressMap!['fullName'] ?? deliveryAddressMap!['name'] ?? '';
    final street = deliveryAddressMap!['fullAddress'] ?? deliveryAddressMap!['address'] ?? deliveryAddressMap!['street'] ?? '';
    final city = deliveryAddressMap!['city'] ?? '';
    final state = deliveryAddressMap!['state'] ?? '';
    final pincode = deliveryAddressMap!['pincode'] ?? '';
    final label = deliveryAddressMap!['label'] ?? '';

    List<String> parts = [];
    if (street.toString().isNotEmpty) parts.add(street.toString());
    if (city.toString().isNotEmpty) parts.add(city.toString());
    if (state.toString().isNotEmpty) parts.add(state.toString());
    if (pincode.toString().isNotEmpty) parts.add(pincode.toString());

    String addrStr = parts.isNotEmpty ? parts.join(', ') : '';
    if (addrStr.isEmpty) {
      return deliveryAddressStr ?? 'Your delivery address';
    }
    
    String finalStr = '';
    if (label.toString().isNotEmpty) {
      finalStr += '[${label.toString().toUpperCase()}] ';
    }
    if (name.toString().isNotEmpty) {
      finalStr += '${name.toString()}\n';
    }
    finalStr += addrStr;
    
    return finalStr;
  }

  factory UserOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] ?? json['products']) as List? ?? [];
    final items = rawItems
        .map((i) => UserOrderItem.fromJson(i as Map<String, dynamic>))
        .toList();

    double totalAmt =
        (json['totalAmount'] ?? json['total'] ?? json['bill'] as num?)
                ?.toDouble() ??
            0.0;
    if (totalAmt == 0.0 && items.isNotEmpty) {
      totalAmt = items.fold(0.0, (sum, i) => sum + (i.price * i.quantity));
    }

    return UserOrder(
      id: (json['_id'] ?? json['orderId'] ?? json['id'] ?? '').toString(),
      status: (json['status'] ?? json['paymentStatus'] ?? 'Pending').toString(),
      total: totalAmt,
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0.0,
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.tryParse(json['updatedAt'] ??
                  json['createdAt'] ??
                  json['orderDate'] ??
                  '')
              ?.toLocal() ??
          DateTime.now(),
      items: items,
      rider: json['rider'] is Map ? json['rider'] : null,
      deliveryAddressMap: json['deliveryAddress'] is Map
          ? json['deliveryAddress']
          : (json['address'] is Map ? json['address'] : null),
      deliveryAddressStr: json['deliveryAddress'] is String
          ? json['deliveryAddress'] as String
          : (json['address'] is String ? json['address'] as String : null),
      deliverySlot: json['deliverySlot']?.toString(),
      orderType: json['orderType']?.toString() ?? 'One-time',
      retailer: json['retailer'] is Map
          ? json['retailer'] as Map<String, dynamic>
          : (items.isNotEmpty ? items.first.retailer : null),
      deliveryOtp: json['deliveryOtp']?.toString(),
      deliveryOtpExpiresAt: json['deliveryOtpExpiresAt'] != null
          ? DateTime.tryParse(json['deliveryOtpExpiresAt'].toString())?.toLocal()
          : null,
      cancelReason: (json['cancelReason'] ?? json['cancellationReason'] ?? json['reason'])?.toString(),
      cancelledBy: json['cancelledBy']?.toString(),
      isReviewed: json['isReviewed'] == true ||
          json['reviewed'] == true ||
          json['isReviewed'] == 1 ||
          json['reviewed'] == 1 ||
          json['is_reviewed'] == true ||
          json['is_reviewed'] == 1 ||
          json['isReviewed'].toString().toLowerCase() == 'true' ||
          json['is_reviewed'].toString().toLowerCase() == 'true',
      bottleDepositFee: (json['bottleDepositFee'] as num?)?.toDouble() ?? 0.0,
      hasEmptyBottles: json['hasEmptyBottles'] == true || json['hasEmptyBottles'] == 'true',
      returnedBottlesCount: (json['returnedBottlesCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class UserOrderItem {
  final String id;
  final String name;
  final int quantity;
  final double price;
  final String image;
  final Map<String, dynamic>? retailer;

  const UserOrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
    required this.image,
    this.retailer,
  });

  factory UserOrderItem.fromJson(Map<String, dynamic> json) {
    final p = json['product'] is Map ? json['product'] : json;
    String img = '';
    if (p['image'] != null) {
      img = p['image'].toString();
    } else if (p['images'] is List && (p['images'] as List).isNotEmpty) {
      img = p['images'][0].toString();
    }

    return UserOrderItem(
      id: (p['_id'] ?? p['id'] ?? '').toString(),
      name: (p['name'] ?? p['productName'] ?? 'Item').toString(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      price: (json['price'] as num?)?.toDouble() ??
          (p['price'] as num?)?.toDouble() ??
          0.0,
      image: img,
      retailer: json['retailer'] is Map ? json['retailer'] as Map<String, dynamic> : null,
    );
  }
}

class UserAddress {
  final String id;
  final String title;
  final String street;
  final String details;
  final String fullName;
  final String email;
  final bool isDefault;
  final double? latitude;
  final double? longitude;
  final int? floorNumber;
  final bool? hasLift;

  const UserAddress({
    required this.id,
    required this.title,
    required this.street,
    required this.details,
    this.fullName = '',
    this.email = '',
    this.isDefault = false,
    this.latitude,
    this.longitude,
    this.floorNumber,
    this.hasLift,
  });

  UserAddress copyWith({
    String? id,
    String? title,
    String? street,
    String? details,
    String? fullName,
    String? email,
    bool? isDefault,
    double? latitude,
    double? longitude,
    int? floorNumber,
    bool? hasLift,
  }) {
    return UserAddress(
      id: id ?? this.id,
      title: title ?? this.title,
      street: street ?? this.street,
      details: details ?? this.details,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      isDefault: isDefault ?? this.isDefault,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      floorNumber: floorNumber ?? this.floorNumber,
      hasLift: hasLift ?? this.hasLift,
    );
  }
}

class UserPaymentMethod {
  final String id;
  final String type;
  final String lastFour;
  final String expiry;

  const UserPaymentMethod({
    required this.id,
    required this.type,
    required this.lastFour,
    required this.expiry,
  });
}

class UserProfile {
  final String name;
  final String email;
  final String phone;
  final String profileImage;

  const UserProfile({
    required this.name,
    required this.email,
    required this.phone,
    required this.profileImage,
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? phone,
    String? profileImage,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      profileImage: profileImage ?? this.profileImage,
    );
  }
}

class Product {
  final String id;
  final String name;
  final String image;
  final double price;
  final String weight;
  final String category;
  final String badgeText;
  final bool isFavorite;
  final String description;
  final List<String> whyChoose;
  final bool isShopActive;
  final String shopId;
  final String shopName;
  final String stockStatus;
  final int stock;

  const Product({
    required this.id,
    required this.name,
    required this.image,
    required this.price,
    required this.weight,
    required this.category,
    this.badgeText = '',
    this.isFavorite = false,
    this.description = '',
    this.whyChoose = const [],
    this.isShopActive = true,
    this.shopId = '',
    this.shopName = '',
    this.stockStatus = 'In Stock',
    this.stock = 0,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: (json['id'] ?? json['_id'])?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      image: (json['image'] ??
              (json['images'] is List && (json['images'] as List).isNotEmpty
                  ? json['images'][0]
                  : ''))
          ?.toString() ??
          '',
      price: double.tryParse(json['price']?.toString() ?? '0') ?? 0.0,
      weight: (json['weight'] ??
              json['description']?.toString().split('\n').first ??
              '')
          ?.toString() ??
          '',
      category: json['category']?.toString() ?? '',
      badgeText: json['badgeText']?.toString() ?? '',
      isFavorite: json['isFavorite'] == true || json['isFavorite'] == 'true',
      description: json['description']?.toString() ?? '',
      whyChoose: (json['whyChoose'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isShopActive: json['isShopActive'] ?? json['isActive'] ?? true,
      shopId: (json['shopId'] ?? json['retailer'])?.toString() ?? '',
      shopName: json['shopName']?.toString() ?? '',
      stockStatus: json['stockStatus']?.toString() ?? 'In Stock',
      stock: (json['stock'] as num?)?.toInt() ?? 0,
    );
  }
}

class WalletTransaction {
  final String id;
  final String orderId;
  final String type; // 'Credit' or 'Debit'
  final String category; // 'Payment', 'Top-up', 'Refund'
  final double amount;
  final double balanceAfter;
  final String description;
  final String status; // 'Success', 'Failed', 'Pending'
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.orderId,
    required this.type,
    required this.category,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    required this.status,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['transactionId']?.toString() ?? json['_id']?.toString() ?? '',
      orderId: json['orderId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Debit',
      category: json['category']?.toString() ?? 'Payment',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      balanceAfter:
          double.tryParse(json['balanceAfter']?.toString() ?? '0') ?? 0.0,
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Success',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

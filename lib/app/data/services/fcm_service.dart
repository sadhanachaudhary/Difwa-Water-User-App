import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../network/api_client.dart';
import '../../../core/storage/secure_storage_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../routes/app_routes.dart';
import '../providers/notification_provider.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized for background isolate if you need to use Firebase services
  // await Firebase.initializeApp(); 

  debugPrint("📩 Background Message Received: ${message.messageId}");
  debugPrint("Data Payload: ${message.data}");

  // Handle background data logic (e.g., updating a local timestamp or clearing a quick cache)
  if (message.data.containsKey('type')) {
    final type = message.data['type'].toString().toUpperCase();
    if (type == 'SYSTEM' || type == 'NOTIFICATION') {
       // Logic to mark that a new notification is available for when the app wakes up
    }
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'difwa_high_importance_v3',
    'Difwa Notifications',
    description: 'Important notifications for orders, OTPs, and updates',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('bell_sound'),
    playSound: true,
  );

  static ProviderContainer? _container;

  static Future<void> init(ProviderContainer container) async {
    _container = container;
    // Background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Create Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          try {
            final data = jsonDecode(response.payload!) as Map<String, dynamic>;
            _handleNavigationFromData(data);
          } catch (e) {
            debugPrint('❌ Error parsing local notification payload: $e');
          }
        }
      },
    );

    // Request permissions
    await FCMService().requestPermission();

    // Foreground listening
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      // Live update the notification list
      if (_container != null) {
        _container!.invalidate(notificationsProvider);
      }

      if (message.notification != null) {
        showNotification(
          title: message.notification!.title ?? 'New Notification',
          body: message.notification!.body ?? '',
          data: message.data,
        );
      }
    });

    // Handle interaction when app is in background but not terminated
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('🔔 Notification caused app to open from background!');
      _handleNavigationFromMessage(message);
    });

    // Handle interaction when app is terminated
    FirebaseMessaging.instance
        .getInitialMessage()
        .then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('🔔 Notification caused app to open from terminated state!');
        _handleNavigationFromMessage(message);
      }
    });

    // Android: Allow foreground notifications to show alerts/sounds
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    listenToTokenRefresh();
    // Initial token send (if user is already logged in)
    unawaited(sendTokenToBackend());

    debugPrint('✅ FCMService initialized (Real Firebase)');
  }

  static void _handleNavigationFromMessage(RemoteMessage message) {
    _handleNavigationFromData(Map<String, dynamic>.from(message.data));
  }

  static void _handleNavigationFromData(Map<String, dynamic> data) {
    debugPrint('🔔 Navigating from notification data: $data');

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️ Navigator context is null, cannot redirect');
      return;
    }

    // Example based on common FCM payloads
    final String type = (data['type']?.toString() ?? '').toUpperCase();
    final String id = (data['id'] ?? data['orderId'] ?? '').toString();

    if (type == 'ORDER' || type == 'NEW_ORDER') {
      Navigator.pushNamed(context, AppRoutes.trackOrder,
          arguments: {'orderId': id});
    } else if (type == 'RIDER_ORDER' || type == 'RIDER_ASSIGNED') {
      Navigator.pushNamed(context, AppRoutes.riderOrderDetails,
          arguments: {'orderId': id});
    } else if (type == 'WALLET' || type == 'PAYMENT') {
      Navigator.pushNamed(context, AppRoutes.wallet);
    } else if (type == 'NOTIFICATION' || type == 'GENERAL' || type == 'SYSTEM') {
      Navigator.pushNamed(context, AppRoutes.notifications);
    } else if (type == 'CHAT') {
      // Navigate to support or specific order chat if implemented
      Navigator.pushNamed(context, AppRoutes.help);
    }
  }

  Future<void> requestPermission() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint('🔔 User granted permission: ${settings.authorizationStatus}');
  }

  Future<String?> getToken() async {
    try {
      final String? token = await FirebaseMessaging.instance.getToken();
      debugPrint('📱 FCM Device Token: $token');
      return token;
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
      return null;
    }
  }

  static Future<void> sendTokenToBackend() async {
    try {
      final token = await FCMService().getToken();
      if (token == null) return;

      final storage = SecureStorageService();
      final authToken = await storage.getAccessToken();
      if (authToken == null) {
        debugPrint('ℹ️ Skip sending FCM token: User not logged in');
        return;
      }

      if (_container != null) {
        final client = _container!.read(apiClientProvider);
        await client.post(
          '/notifications/register-token/app',
          data: {'fcmToken': token},
          requiresAuth: true,
        );
      } else {
        // Fallback for cases where container is not yet available
        final client = ApiClient.createDefault();
        await client.post(
          '/notifications/register-token/app',
          data: {'fcmToken': token},
          requiresAuth: true,
        );
      }
      debugPrint('✅ Device token sent to backend');
    } catch (e) {
      debugPrint('⚠️ Failed to send device token to backend: $e');
    }
  }

  static void listenToTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('🔄 FCM Token refreshed!');
      // Optional: Send to backend immediately if logged in
      await sendTokenToBackend();
    });
  }

  static Future<void> showNotification({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final String? payload = data != null ? jsonEncode(data) : null;
      await _localNotifications.show(
        DateTime.now().millisecond + (title.length * 100),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            sound: const RawResourceAndroidNotificationSound('bell_sound'),
            playSound: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentSound: true,
            sound: 'bell_sound.mp3',
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('❌ Error showing local notification: $e');
    }
  }
}

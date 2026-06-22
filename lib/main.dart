import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app/routes/app_routes.dart';
import 'app/routes/app_pages.dart';
import 'app/data/services/cart_service.dart';
import 'app/data/services/wallet_service.dart';
import 'app/data/services/address_service.dart';
import 'app/data/services/shop_service.dart';
import 'app/data/services/order_service.dart';
import 'app/data/services/db_service.dart';
import 'app/core/theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/data/services/fcm_service.dart';
import 'app/data/models/food_models.dart';
import 'app/core/constants/app_images.dart';
import 'app/modules/auth/provider/auth_provider.dart';
import 'app/core/localization/language_provider.dart';
import 'app/core/localization/supported_languages.dart';
import 'l10n/generated/app_localizations.dart';
import 'firebase_options.dart';

final cartProviderManager = Provider<CartProvider>((ref) {
  final user = ref.watch(currentUserProvider);

  return CartProvider(
    service: ref.watch(cartServiceProvider),
    walletService: ref.watch(walletServiceProvider),
    addressService: ref.watch(addressServiceProvider),
    shopService: ref.watch(shopServiceProvider),
    orderService: ref.watch(orderServiceProvider),
    authService: ref.watch(authServiceProvider),
    user: user != null
        ? UserProfile(
            name: user.fullName,
            email: user.email,
            phone: user.phoneNumber,
            profileImage: AppImages.defaultAvatar,
          )
        : null,
  );
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
  }
  try {
    await dotenv.load(fileName: ".env");
    debugPrint("Dotenv loaded. RAZORPAY_KEY_ID: ${dotenv.env['RAZORPAY_KEY_ID']}");
  } catch (e) {
    debugPrint("Warning: Could not load .env file: $e");
  }

  final container = ProviderContainer();

  // Restore saved language before first frame
  try {
    await container.read(localeProvider.notifier).loadSavedLocale();
  } catch (e) {
    debugPrint("Warning: Could not load saved locale: $e");
  }

  try {
    await FCMService.init(container);
  } catch (e) {
    debugPrint("Warning: Could not initialize FCMService: $e");
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const DifwaWaterApp(),
    ),
  );
}

class DifwaWaterApp extends ConsumerWidget {
  const DifwaWaterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'Difwa Water',
      navigatorKey: FCMService.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: locale,
      supportedLocales: kSupportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (deviceLocale, supportedLocales) {
        // If explicitly set by user, use that (already in locale)
        if (supportedLocales.any(
            (s) => s.languageCode == locale.languageCode)) {
          return locale;
        }
        // Fallback to English
        return const Locale('en');
      },
      initialRoute: AppRoutes.splash,
      routes: AppPages.routes,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
      ),
      builder: (context, child) {
        return Consumer(
          builder: (context, ref, _) {
            final cartProvider = ref.watch(cartProviderManager);
            return CartProviderScope(
              provider: cartProvider,
              child: child!,
            );
          },
        );
      },
    );
  }
}

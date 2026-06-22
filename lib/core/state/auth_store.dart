import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/data/models/auth_models.dart';
import '../../app/data/services/auth_service.dart';
import '../storage/secure_storage_service.dart';
import '../api/auth_interceptor.dart';
import '../../app/data/network/api_client.dart';
import '../../app/data/services/fcm_service.dart';

// Unified Auth Provider for the app
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(client: ref.watch(apiClientProvider));
});

final secureStorageProvider = Provider((ref) => SecureStorageService());

sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  final String? successMessage;
  const AuthInitial({this.successMessage});
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final UserModel user;
  final bool isMock;
  const AuthAuthenticated(this.user, {this.isMock = false});
}

class AuthUnauthenticated extends AuthState {
  final String? error;
  const AuthUnauthenticated({this.error});
}

/// Intermediate state for OTP verification flow
class AuthOtpSent extends AuthState {
  final String phoneNumber;
  final String? verificationId;
  final String? otp;
  final String? message;
  final bool isMock;
  const AuthOtpSent({
    required this.phoneNumber,
    this.verificationId,
    this.otp,
    this.message,
    this.isMock = false,
  });
}

/// One-shot states for UI feedback (error/success)
class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

class AuthSuccess extends AuthState {
  final String message;
  final String? otp;
  const AuthSuccess(this.message, {this.otp});
}

class AuthStore extends Notifier<AuthState> {
  late SecureStorageService _storage;
  StreamSubscription<String>? _logoutSubscription;

  @override
  AuthState build() {
    _storage = ref.watch(secureStorageProvider);

    _logoutSubscription?.cancel();
    _logoutSubscription = AuthInterceptor.onForceLogoutStream.listen((reason) {
      setUnauthenticated(error: reason);
    });

    ref.onDispose(() {
      _logoutSubscription?.cancel();
    });

    return const AuthInitial();
  }

  Future<void> init() async {
    state = const AuthLoading();
    try {
      final String? token = await _storage.getAccessToken();
      if (token == null || token.isEmpty) {
        state = const AuthUnauthenticated();
        return;
      }

      // Use cached profile immediately so navigation doesn't wait for network.
      final cached = await _getCachedUserProfile();
      if (cached != null) {
        state = AuthAuthenticated(cached);
        // Silently verify + refresh in background — won't block splash navigation.
        unawaited(_refreshProfileInBackground());
        return;
      }

      // No cache (first launch after login) — must wait for network once.
      final response = await ref.read(authServiceProvider).getProfile();
      if (response.success && response.data != null) {
        state = AuthAuthenticated(response.data!);
        _cacheUserProfile(response.data!);
        unawaited(syncFcmToken());
      } else if (response.message.contains('401') ||
          response.message.contains('Unauthorized')) {
        await logout();
      } else {
        state = AuthUnauthenticated(error: response.message);
      }
    } catch (e) {
      final cached = await _getCachedUserProfile();
      if (cached != null) {
        state = AuthAuthenticated(cached);
      } else {
        state = AuthUnauthenticated(error: e.toString());
      }
    }
  }

  Future<void> _refreshProfileInBackground() async {
    try {
      final response = await ref.read(authServiceProvider).getProfile();
      if (response.success && response.data != null) {
        state = AuthAuthenticated(response.data!);
        _cacheUserProfile(response.data!);
        unawaited(syncFcmToken());
      } else if (response.message.contains('401') ||
          response.message.contains('Unauthorized')) {
        await logout();
      }
      // Any other error: keep cached state, don't disrupt the user.
    } catch (_) {
      // Network unavailable — user stays on cached profile, no disruption.
    }
  }


  Future<void> sendOtp({required String phoneNumber}) async {
    state = const AuthLoading();
    try {
      final String rawPhone = phoneNumber.trim();
      final response = await ref.read(authServiceProvider).sendOtp(phoneNumber: rawPhone);

      if (response.success) {
        state = AuthOtpSent(
          phoneNumber: rawPhone,
          verificationId: rawPhone,
          otp: response.otp,
          message: response.message,
        );
      } else {
        state = AuthError(response.message);
      }
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  Future<void> verifyOtp({required String phoneNumber, required String otp}) async {
    state = const AuthLoading();
    try {
      final response = await ref.read(authServiceProvider).verifyOtp(
            phoneNumber: phoneNumber,
            otp: otp,
          );

      if (response.success && response.data != null && response.token != null) {
        await _storage.saveTokens(
          access: response.token!,
          refresh: response.refreshToken ?? '',
        );
        state = AuthAuthenticated(response.data!);
        _cacheUserProfile(response.data!);
        unawaited(syncFcmToken());
      } else {
        state = AuthError(response.message);
      }
    } catch (e) {
      state = AuthError(e.toString());
    }
  }


  Future<void> logout() async {
    final wasMock = state is AuthAuthenticated && (state as AuthAuthenticated).isMock;
    state = const AuthLoading();
    try {
      if (!wasMock) {
        await ref.read(authServiceProvider).logout();
      }
    } catch (_) {}
    await _storage.clearAll();
    await _clearSessionCache();
    state = const AuthUnauthenticated();
  }

  void setUnauthenticated({String? error}) {
    _storage.clearAll();
    _clearSessionCache();
    state = AuthUnauthenticated(error: error);
  }

  void reset() {
    state = const AuthInitial();
  }

  Future<void> _cacheUserProfile(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_user_profile', jsonEncode(user.toJson()));
    } catch (e) {
      debugPrint('AuthStore: Error caching user profile: $e');
    }
  }

  Future<UserModel?> _getCachedUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_user_profile');
      if (cachedJson != null && cachedJson.isNotEmpty) {
        return UserModel.fromJson(jsonDecode(cachedJson));
      }
    } catch (e) {
      debugPrint('AuthStore: Error getting cached user profile: $e');
    }
    return null;
  }

  Future<void> _clearSessionCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lang = prefs.getString('selected_language_code');
      await prefs.clear();
      if (lang != null) {
        await prefs.setString('selected_language_code', lang);
      }
    } catch (e) {
      debugPrint('AuthStore: Error clearing session cache: $e');
    }
  }

  Future<void> syncFcmToken() async {
    final fcmToken = await FCMService().getToken();
    if (fcmToken != null) {
      await ref.read(authServiceProvider).updateFcmToken(fcmToken: fcmToken);
    }
  }

  Future<void> updateProfile({required String fullName, required String email}) async {
    if (state is! AuthAuthenticated) return;
    final current = state as AuthAuthenticated;
    try {
      final response = await ref.read(authServiceProvider).updateProfile(
            fullName: fullName,
            email: email,
          );
      if (response.success && response.data != null) {
        state = AuthAuthenticated(response.data!, isMock: current.isMock);
        _cacheUserProfile(response.data!);
      }
    } catch (_) {}
  }

  Future<void> updateName({required String fullName}) async {
    if (state is! AuthAuthenticated) return;
    final current = state as AuthAuthenticated;
    try {
      final response = await ref.read(authServiceProvider).updateName(
            fullName: fullName,
          );
      if (response.success && response.data != null) {
        state = AuthAuthenticated(response.data!, isMock: current.isMock);
        _cacheUserProfile(response.data!);
      }
    } catch (_) {}
  }

  void syncUser(UserModel user) {
    if (state is AuthAuthenticated) {
      final current = state as AuthAuthenticated;
      state = AuthAuthenticated(user, isMock: current.isMock);
      _cacheUserProfile(user);
    }
  }
}

final authStoreProvider = NotifierProvider<AuthStore, AuthState>(() {
  return AuthStore();
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authStoreProvider) is AuthAuthenticated;
});

final currentUserProvider = Provider<UserModel?>((ref) {
  final state = ref.watch(authStoreProvider);
  return state is AuthAuthenticated ? state.user : null;
});

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/network_exception.dart';
import '../utils/retry_helper.dart';
import '../config/app_config.dart';

/// Provider for Firebase Authentication state management.
class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  Future<void>? _googleSignInInitialization;
  late final StreamSubscription<User?> _authSubscription;

  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isSignedIn => _user != null;
  String? get error => _error;
  String get displayName => _user?.displayName ?? 'Anonymous';
  String get email => _user?.email ?? '';
  String? get photoUrl => _user?.photoURL;
  String get userId => _user?.uid ?? '';

  AuthProvider({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance {
    // Firebase is initialized before providers are created. Seed the owner
    // synchronously so local recovery need not wait for the first stream event.
    _user = _auth.currentUser;
    // Listen to auth state changes
    _authSubscription = _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  /// Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      _setLoading(true);

      await _initializeGoogleSignIn();
      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await _auth
          .signInWithCredential(credential)
          .timeout(AppConfig.signInTimeout);
      _setLoading(false);
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        _setLoading(false);
        return false;
      }
      _handleError(e);
      return false;
    } catch (e) {
      _handleError(e);
      return false;
    }
  }

  /// Initialize GoogleSignIn once. A failed initialization is not cached, so
  /// the next sign-in attempt can retry it.
  Future<void> _initializeGoogleSignIn() =>
      _googleSignInInitialization ??= _googleSignIn.initialize().catchError(
        (Object e) {
          _googleSignInInitialization = null;
          throw e;
        },
      );

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  /// Sign out
  Future<void> signOut() async {
    _setLoading(true);
    try {
      try {
        await _initializeGoogleSignIn();
        await _googleSignIn.signOut();
      } catch (e) {
        debugPrint('Google sign-out failed: $e');
      }

      await _auth.signOut();
    } catch (e) {
      _handleError(e);
    } finally {
      _setLoading(false);
    }
  }

  /// Update user display name
  Future<void> updateUserName(String name) async {
    try {
      _setLoading(true);

      await _user?.updateDisplayName(name);
      await _user?.reload();
      _user = _auth.currentUser;

      _setLoading(false);
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  /// Get ID token for API calls with automatic retry on network errors.
  ///
  /// Uses [RetryHelper] to handle transient network issues.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (_user == null) return null;

    return await RetryHelper.execute<String?>(
      () => _user!.getIdToken(forceRefresh),
      maxRetries: AppConfig.maxRetries,
      retryDelays: AppConfig.retryDelays,
    );
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    if (loading) {
      _error = null;
    }
    notifyListeners();
  }

  void _handleError(Object e) {
    if (isNetworkError(e)) {
      _error = NetworkErrorKey.networkError;
    } else {
      _error = e.toString();
    }
    _isLoading = false;
    notifyListeners();
  }
}

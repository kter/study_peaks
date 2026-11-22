import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/study_session.dart';
import '../services/network_exception.dart';
import '../utils/retry_helper.dart';
import '../config/app_config.dart';

/// Provider for Firebase Authentication state management.
class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;
  Future<void>? _googleSignInInitialization;
  Future<User?>? _anonymousSignIn;
  late final StreamSubscription<User?> _authSubscription;

  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  User? get _account => _user?.isAnonymous == false ? _user : null;
  bool get isSignedIn => _account != null;
  String? get error => _error;
  String get displayName => _account?.displayName ?? 'Anonymous';
  String get email => _account?.email ?? '';
  String? get photoUrl => _account?.photoURL;
  String get userId => _account?.uid ?? '';
  String get historyOwnerId => StudySession.ownerFor(userId);

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
      _user = null;
    } catch (e) {
      _handleError(e);
    } finally {
      _setLoading(false);
    }
  }

  /// Get an ID token, creating an anonymous seat identity when needed.
  ///
  /// Uses [RetryHelper] to handle transient network issues.
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = _user ?? _auth.currentUser ?? await _getAnonymousUser();
    if (user == null) return null;

    try {
      return await RetryHelper.execute<String?>(
        () => user.getIdToken(forceRefresh),
        maxRetries: AppConfig.maxRetries,
        retryDelays: AppConfig.retryDelays,
      );
    } catch (_) {
      if (!user.isAnonymous) rethrow;
      return null;
    }
  }

  Future<User?> _getAnonymousUser() =>
      _anonymousSignIn ??= _signInAnonymously().whenComplete(() {
        _anonymousSignIn = null;
      });

  Future<User?> _signInAnonymously() async {
    try {
      final credential =
          await _auth.signInAnonymously().timeout(AppConfig.signInTimeout);
      return credential.user;
    } catch (_) {
      return null;
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    if (loading) {
      _error = null;
    }
    notifyListeners();
  }

  void _handleError(Object e) {
    _error = errorKeyFor(e, e.toString());
    _isLoading = false;
    notifyListeners();
  }
}

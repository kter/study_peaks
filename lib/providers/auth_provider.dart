import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/network_exception.dart';
import '../utils/retry_helper.dart';
import '../config/app_config.dart';

/// Provider for Firebase Authentication state management.
class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

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

  AuthProvider() {
    // Listen to auth state changes
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  /// Sign in with Google
  Future<bool> signInWithGoogle() async {
    try {
      _setLoading(true);

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false);
        return false; // User cancelled
      }

      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
      
      _setLoading(false);
      return true;
    } catch (e) {
      _handleError(e);
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      _setLoading(true);

      await _googleSignIn.signOut();
      await _auth.signOut();

      _setLoading(false);
    } catch (e) {
      _handleError(e);
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

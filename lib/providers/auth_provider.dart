import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/network_exception.dart';

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
      _isLoading = true;
      _error = null;
      notifyListeners();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _isLoading = false;
        notifyListeners();
        return false; // User cancelled
      }

      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Use localization key for network errors
      if (isNetworkError(e)) {
        _error = NetworkErrorKey.networkError;
      } else {
        _error = e.toString();
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      _isLoading = true;
      notifyListeners();

      await _googleSignIn.signOut();
      await _auth.signOut();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      // Use localization key for network errors
      if (isNetworkError(e)) {
        _error = NetworkErrorKey.networkError;
      } else {
        _error = e.toString();
      }
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update user display name
  Future<void> updateUserName(String name) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _user?.updateDisplayName(name);
      await _user?.reload();
      _user = _auth.currentUser;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      // Use localization key for network errors
      if (isNetworkError(e)) {
        _error = NetworkErrorKey.networkError;
      } else {
        _error = e.toString();
      }
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Get ID token for API calls
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return await _user?.getIdToken(forceRefresh);
  }
}

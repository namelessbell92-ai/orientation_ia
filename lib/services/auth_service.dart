import 'package:firebase_auth/firebase_auth.dart';
import 'user_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Connexion
  Future<User?> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await UserService.syncUserSession(user);
    }
    return user;
  }

  // Inscription
  Future<User?> signUp(String email, String password, {String? displayName}) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      if (displayName != null && displayName.isNotEmpty) {
        await user.updateDisplayName(displayName);
      }
      await UserService.syncUserSession(user, defaultName: displayName);
    }
    return user;
  }

  // Déconnexion
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Stream utilisateur
  Stream<User?> get userStream => _auth.authStateChanges();
}

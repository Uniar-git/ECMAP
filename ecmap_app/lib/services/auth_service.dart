import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _google = GoogleSignIn();

  static Stream<User?> get authStateChanges => _auth.authStateChanges();
  static User? get currentUser => _auth.currentUser;

  static Future<void> signInWithEmail(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  static Future<void> signUpWithEmail(String email, String password) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  static Future<void> signInWithGoogle() async {
    final googleUser = await _google.signIn();
    if (googleUser == null) return;
    final googleAuth = await googleUser.authentication;
    await _auth.signInWithCredential(GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    ));
  }

  static Future<void> signOut() async {
    await _google.signOut();
    await _auth.signOut();
  }
}

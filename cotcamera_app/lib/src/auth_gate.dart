import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:developer' as dev; // for clean logging

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        // Not signed in -> show your login UI
        if (user == null) {
          return const _EmailAuthPage();
        }

        // Signed in -> go to your home page
        return const _HomePage();
      },
    );
  }
}

class _EmailAuthPage extends StatefulWidget {
  const _EmailAuthPage();

  @override
  State<_EmailAuthPage> createState() => _EmailAuthPageState();
}

class _EmailAuthPageState extends State<_EmailAuthPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool isLogin = true;
  String? error;

  Future<void> _submit() async {
    setState(() => error = null);
    try {
      if (isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: pass.text,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: pass.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message);
    }
  }

  Future<void> _reset() async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email.text.trim(),
      );
      setState(() => error = 'Password reset email sent');
    } on FirebaseAuthException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isLogin ? 'Sign in' : 'Create account',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pass,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(error!, style: const TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _submit,
                        child: Text(isLogin ? 'Sign in' : 'Sign up'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => isLogin = !isLogin),
                        child: Text(isLogin ? 'Create account' : 'Have an account? Sign in'),
                      ),
                      TextButton(
                        onPressed: _reset,
                        child: const Text('Forgot password?'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  String uid = 'unknown';

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

    // Run once after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await refreshAndLogClaims();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CoTCamera'), actions: [
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: () => FirebaseAuth.instance.signOut(),
        ),
      ]),
      body: Center(child: Text('Signed in as: $uid')),
    );
  }
}

Future<void> refreshAndLogClaims() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  await user.getIdToken(true); // force refresh
  final tokenResult = await user.getIdTokenResult(true);

  dev.log('UID: ${user.uid}', name: 'auth');
  dev.log('Claims: ${tokenResult.claims}', name: 'auth');

  final roles = (tokenResult.claims?['roles'] as List?)?.cast<String>() ?? const [];
  dev.log('Is admin? ${roles.contains('admin')}', name: 'auth');
}

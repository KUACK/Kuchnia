import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'household_gate.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<User?> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text(
                'Nie udało się sprawdzić stanu logowania.\n'
                'Uruchom aplikację ponownie.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          return const LoginScreen();
        }

        return HouseholdGate(key: ValueKey(user.uid), userId: user.uid);
      },
    );
  }
}

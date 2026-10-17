import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'household_setup_screen.dart';

class HouseholdGate extends StatefulWidget {
  final String userId;

  const HouseholdGate({super.key, required this.userId});

  @override
  State<HouseholdGate> createState() => _HouseholdGateState();
}

class _HouseholdGateState extends State<HouseholdGate> {
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userStream;

  @override
  void initState() {
    super.initState();

    _userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .snapshots(includeMetadataChanges: true);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Problem z bazą')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nie udało się odczytać danych użytkownika.\n\n'
                  'Sprawdź połączenie z internetem oraz reguły Firestore. '
                  'Po poprawieniu problemu uruchom aplikację ponownie.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final document = snapshot.data!;
        final data = document.data();
        final householdId = data?['householdId'];

        if (householdId is! String || householdId.trim().isEmpty) {
          return const HouseholdSetupScreen();
        }

        if (document.metadata.hasPendingWrites) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return const HomeScreen();
      },
    );
  }
}

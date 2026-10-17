import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class HouseholdSetupScreen extends StatefulWidget {
  const HouseholdSetupScreen({super.key});

  @override
  State<HouseholdSetupScreen> createState() => _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends State<HouseholdSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createHousehold() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _errorMessage = 'Sesja wygasła. Zaloguj się ponownie.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;

      final householdRef = firestore.collection('households').doc();
      final userRef = firestore.collection('users').doc(user.uid);

      final batch = firestore.batch();

      batch.set(householdRef, {
        'name': _nameController.text.trim(),
        'ownerId': user.uid,
        'memberIds': [user.uid],
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.set(userRef, {
        'email': user.email,
        'displayName': user.displayName ?? '',
        'householdId': householdRef.id,
      }, SetOptions(merge: true));

      await batch.commit();

      // Przejście obsłuży HouseholdGate po odczytaniu danych.
    } on FirebaseException catch (error) {
      if (!mounted) return;

      setState(() {
        if (error.code == 'permission-denied') {
          _errorMessage =
              'Brak uprawnień do zapisu. Sprawdź opublikowane reguły Firestore.';
        } else if (error.code == 'unavailable') {
          _errorMessage = 'Baza jest chwilowo niedostępna. Sprawdź internet.';
        } else {
          _errorMessage = 'Nie udało się utworzyć domu. Kod: ${error.code}';
        }
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Wystąpił nieoczekiwany błąd. Spróbuj ponownie.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Nie udało się wylogować. Spróbuj ponownie.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Twoja spiżarnia'),
        actions: [
          IconButton(
            tooltip: 'Wyloguj się',
            onPressed: _isSaving ? null : _signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.home_outlined,
                      size: 80,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Utwórz swój dom',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Dom to wspólna przestrzeń na produkty '
                      'i listę zakupów. Nadaj mu nazwę — na przykład '
                      '„Moja kuchnia” albo „Dom Grzegorza”.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _nameController,
                      enabled: !_isSaving,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _createHousehold(),
                      decoration: const InputDecoration(
                        labelText: 'Nazwa domu',
                        prefixIcon: Icon(Icons.home_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';

                        if (name.isEmpty) {
                          return 'Wpisz nazwę domu.';
                        }

                        if (name.length > 80) {
                          return 'Nazwa może mieć maksymalnie 80 znaków.';
                        }

                        return null;
                      },
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _isSaving ? null : _createHousehold,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_home_outlined),
                      label: Text(_isSaving ? 'Zapisywanie...' : 'Utwórz dom'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

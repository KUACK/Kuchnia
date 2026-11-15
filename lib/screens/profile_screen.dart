import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  final String householdId;

  const ProfileScreen({super.key, required this.householdId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isSigningOut = false;
  String? _errorMessage;

  Future<void> _signOut() async {
    if (_isSigningOut) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Wylogować się?'),
          content: const Text(
            'Twoje konto, dom i produkty pozostaną zapisane. '
            'Aby ponownie korzystać ze spiżarni, zaloguj się '
            'na to samo konto.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Wyloguj się'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    final navigator = Navigator.of(context);

    setState(() {
      _isSigningOut = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signOut();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _isSigningOut = false;
        _errorMessage = 'Nie udało się wylogować. Kod błędu: ${error.code}';
      });
      return;
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isSigningOut = false;
        _errorMessage = 'Wystąpił nieoczekiwany błąd. Spróbuj ponownie.';
      });
      return;
    }

    if (!navigator.mounted) return;

    // Zamykamy dodatkowe ekrany. Główny AuthGate pokaże logowanie.
    navigator.popUntil((route) => route.isFirst);
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SelectableText(value),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return PopScope(
      canPop: !_isSigningOut,
      child: Scaffold(
        appBar: AppBar(title: const Text('Profil')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Icon(
                    Icons.account_circle_outlined,
                    size: 88,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Twoje konto',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  _buildInfoCard(
                    icon: Icons.email_outlined,
                    title: 'Adres e-mail',
                    value: user?.email ?? 'Brak adresu e-mail',
                  ),
                  const SizedBox(height: 8),
                  _buildInfoCard(
                    icon: Icons.home_outlined,
                    title: 'Identyfikator domu',
                    value: widget.householdId,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Identyfikator domu jest informacją techniczną. '
                    'Nie jest kodem zaproszenia i nie pozwala '
                    'samodzielnie dołączyć do spiżarni.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (_errorMessage != null) ...[
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: _isSigningOut ? null : _signOut,
                    icon: const Icon(Icons.logout),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        _isSigningOut ? 'Wylogowywanie...' : 'Wyloguj się',
                      ),
                    ),
                  ),
                  if (_isSigningOut) ...[
                    const SizedBox(height: 20),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

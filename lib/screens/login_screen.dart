import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _hidePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading || !_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _messageForError(error.code);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Wystąpił nieoczekiwany błąd. Spróbuj ponownie.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _messageForError(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Podaj poprawny adres e-mail.';
      case 'weak-password':
        return 'Hasło jest zbyt słabe. Użyj dłuższego, silniejszego hasła.';
      case 'email-already-in-use':
        return 'Ten adres e-mail jest już przypisany do konta.';
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return 'Nieprawidłowy e-mail lub hasło.';
      case 'user-disabled':
        return 'To konto zostało wyłączone.';
      case 'too-many-requests':
        return 'Zbyt wiele prób. Odczekaj chwilę i spróbuj ponownie.';
      case 'network-request-failed':
        return 'Nie udało się połączyć. Sprawdź połączenie z internetem.';
      case 'operation-not-allowed':
        return 'Logowanie e-mailem i hasłem nie jest włączone w Firebase.';
      default:
        return 'Nie udało się wykonać operacji. Kod błędu: $code';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kuchnia+')),
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
                      Icons.kitchen_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isLogin ? 'Witaj ponownie!' : 'Utwórz konto',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLogin
                          ? 'Zaloguj się do Kuchni+.'
                          : 'Zarejestruj się, aby zacząć korzystać z aplikacji.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final email = value?.trim() ?? '';

                        if (email.isEmpty) {
                          return 'Wpisz adres e-mail.';
                        }

                        if (!RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(email)) {
                          return 'Podaj poprawny adres e-mail.';
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !_isLoading,
                      obscureText: _hidePassword,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Hasło',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword
                              ? 'Pokaż hasło'
                              : 'Ukryj hasło',
                          onPressed: () {
                            setState(() {
                              _hidePassword = !_hidePassword;
                            });
                          },
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Wpisz hasło.';
                        }

                        if (!_isLogin && value.length < 6) {
                          return 'Hasło musi mieć przynajmniej 6 znaków.';
                        }

                        return null;
                      },
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isLoading ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _isLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_isLogin ? 'Zaloguj się' : 'Utwórz konto'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _isLogin = !_isLogin;
                                _errorMessage = null;
                                _passwordController.clear();
                                _formKey.currentState?.reset();
                              });
                            },
                      child: Text(
                        _isLogin
                            ? 'Nie masz konta? Zarejestruj się'
                            : 'Masz już konto? Zaloguj się',
                      ),
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

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/firebase_services.dart';

/// Account flow shown before any Firebase household operation.
class FirebaseAccountPage extends StatefulWidget {
  const FirebaseAccountPage({super.key, required this.services});
  final FirebaseServices services;

  @override
  State<FirebaseAccountPage> createState() => _FirebaseAccountPageState();
}

class _FirebaseAccountPageState extends State<FirebaseAccountPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final displayName = TextEditingController();
  bool registering = false;
  bool busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.services.currentUser;
    if (user != null && !user.emailVerified) {
      return _VerificationPage(
        services: widget.services,
        onVerified: () => setState(() {}),
      );
    }
    if (user != null) {
      return _SignedInPage(
        services: widget.services,
        onContinue: () => Navigator.pop(context, true),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(registering ? 'Create account' : 'Sign in')),
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud_outlined, size: 64),
            const SizedBox(height: 20),
            Text(registering ? 'Keep your household in sync' : 'Sign in to HomeBudget',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Your verified email identifies you in shared households.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (registering) ...[
              TextField(controller: displayName, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Your name')),
              const SizedBox(height: 12),
            ],
            TextField(controller: email, keyboardType: TextInputType.emailAddress,
              autocorrect: false, decoration: const InputDecoration(labelText: 'Email address')),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true,
              decoration: InputDecoration(labelText: 'Password', helperText: registering ? 'Use at least 8 characters.' : null)),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 18),
            FilledButton(onPressed: busy ? null : submit,
              child: Text(busy ? 'Please wait…' : registering ? 'Create account' : 'Sign in')),
            if (!registering) TextButton(onPressed: busy ? null : resetPassword,
              child: const Text('Forgot password?')),
            TextButton(onPressed: busy ? null : () => setState(() { registering = !registering; error = null; }),
              child: Text(registering ? 'I already have an account' : 'Create a new account')),
          ],
        )),
      ))),
    );
  }

  Future<void> submit() async {
    final address = email.text.trim();
    if (address.isEmpty || password.text.isEmpty || (registering && displayName.text.trim().isEmpty)) {
      setState(() => error = 'Complete all required fields.');
      return;
    }
    if (registering && password.text.length < 8) {
      setState(() => error = 'Use a password with at least 8 characters.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      if (registering) {
        await widget.services.register(email: address, password: password.text, displayName: displayName.text);
      } else {
        await widget.services.signIn(email: address, password: password.text);
      }
      if (mounted) setState(() {});
    } on FirebaseAuthException catch (exception) {
      if (mounted) setState(() => error = _authMessage(exception));
    } catch (failure) {
      if (mounted) setState(() => error = 'Account action failed: $failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) {
      setState(() => error = 'Enter your email address first.');
      return;
    }
    try {
      await widget.services.sendPasswordReset(email.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent.')));
    } on FirebaseAuthException catch (exception) {
      if (mounted) setState(() => error = _authMessage(exception));
    }
  }
}

class _VerificationPage extends StatefulWidget {
  const _VerificationPage({required this.services, required this.onVerified});
  final FirebaseServices services;
  final VoidCallback onVerified;
  @override
  State<_VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<_VerificationPage> {
  bool checking = false;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: Padding(
    padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.mark_email_read_outlined, size: 64), const SizedBox(height: 20),
        Text('Verify your email', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10), const Text('Open the verification email, then return here and tap Continue.', textAlign: TextAlign.center),
        const SizedBox(height: 22),
        FilledButton(onPressed: checking ? null : check, child: Text(checking ? 'Checking…' : 'Continue')),
        TextButton(onPressed: checking ? null : resend, child: const Text('Send email again')),
        TextButton(onPressed: useAnotherAccount, child: const Text('Use another account')),
      ],
    )),
  ))));
  Future<void> check() async {
    setState(() => checking = true);
    try {
      final verified = await widget.services.refreshVerification();
      if (!mounted) return;
      if (verified) {
        widget.onVerified();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This email is not verified yet.')));
      }
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification check failed: $failure')));
      }
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> resend() async {
    await widget.services.resendVerification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification email sent.')));
  }

  Future<void> useAnotherAccount() async {
    await widget.services.signOut();
    if (!mounted) return;
    setState(() {});
  }
}

class _SignedInPage extends StatelessWidget {
  const _SignedInPage({required this.services, required this.onContinue});
  final FirebaseServices services;
  final VoidCallback onContinue;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.verified_user_outlined, size: 64), const SizedBox(height: 18),
      Text('Account ready', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8), Text(services.currentUser!.email ?? ''), const SizedBox(height: 22),
      FilledButton(onPressed: onContinue, child: const Text('Continue')),
      TextButton(onPressed: () async {
        await services.signOut();
        if (context.mounted) Navigator.pop(context);
      }, child: const Text('Sign out')),
    ]),
  ))));
}

String _authMessage(FirebaseAuthException error) => switch (error.code) {
  'email-already-in-use' => 'An account already uses this email address.',
  'invalid-email' => 'Enter a valid email address.',
  'weak-password' => 'Choose a stronger password.',
  'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Email or password is incorrect.',
  'too-many-requests' => 'Too many attempts. Try again later.',
  _ => error.message ?? 'Account action could not be completed.',
};

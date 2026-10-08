import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../data/device_settings.dart';
import '../data/firebase_services.dart';
import 'cloud_household_page.dart';
import 'firebase_account_page.dart';
import 'firebase_household_setup_page.dart';
import 'theme.dart';
import 'tutorial_page.dart';

class CloudOnlyApp extends StatefulWidget {
  const CloudOnlyApp({super.key, required this.settings});
  final DeviceSettings settings;

  @override
  State<CloudOnlyApp> createState() => _CloudOnlyAppState();
}

class _CloudOnlyAppState extends State<CloudOnlyApp> with WidgetsBindingObserver {
  final navigatorKey = GlobalKey<NavigatorState>();
  final localAuth = LocalAuthentication();
  FirebaseServices? services;
  CloudHousehold? savedHousehold;
  bool darkTheme = true;
  bool biometricLock = false;
  bool pinEnabled = false;
  bool unlocked = false;
  bool authenticating = false;
  bool sharing = false;
  bool busy = false;
  bool checkingAccount = true;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (sharing) return;
      if (pinEnabled || biometricLock) {
        unlocked = false;
        if (!authenticating) {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      }
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final values = await Future.wait<bool>([
        widget.settings.darkThemeEnabled(),
        widget.settings.biometricLockEnabled(),
        widget.settings.hasPin(),
      ]);
      if (!mounted) return;
      setState(() {
        darkTheme = values[0];
        biometricLock = values[1];
        pinEnabled = values[2];
      });
    } catch (_) {
      // Cloud access remains available if old device preferences cannot load.
    }
  }

  Future<bool> _unlock() async {
    if ((!pinEnabled && !biometricLock) || unlocked) return true;
    if (biometricLock) {
      authenticating = true;
      try {
        if (await localAuth.authenticate(localizedReason: 'Unlock HomeBudget',
          biometricOnly: true, persistAcrossBackgrounding: true)) {
          unlocked = true;
          return true;
        }
      } catch (_) { /* PIN remains available. */ }
      finally { authenticating = false; }
    }
    if (!pinEnabled || !mounted) return false;
    final controller = TextEditingController();
    final pin = await showDialog<String>(context: navigatorKey.currentContext!, builder: (context) => AlertDialog(
      title: const Text('Unlock HomeBudget'),
      content: TextField(controller: controller, obscureText: true,
        keyboardType: TextInputType.number, maxLength: 8,
        decoration: const InputDecoration(labelText: 'Device PIN')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Unlock'))],
    ));
    controller.dispose();
    if (pin == null) return false;
    unlocked = await widget.settings.verifyPin(pin);
    if (!unlocked && mounted) setState(() => error = 'Incorrect PIN.');
    return unlocked;
  }

  Future<void> _setBiometricLock(bool enabled) async {
    if (enabled) {
      authenticating = true;
      try {
        if (!await localAuth.isDeviceSupported() ||
            !await localAuth.authenticate(localizedReason: 'Enable biometric lock', biometricOnly: true)) {
          throw StateError('Biometric authentication is unavailable or was canceled.');
        }
      } finally {
        authenticating = false;
      }
    }
    await widget.settings.setBiometricLockEnabled(enabled);
    if (mounted) setState(() { biometricLock = enabled; unlocked = true; });
  }

  Future<void> _prepareCloud() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp().timeout(const Duration(seconds: 10));
      }
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode ? const AndroidDebugProvider() : const AndroidPlayIntegrityProvider(),
      ).timeout(const Duration(seconds: 10));
      services ??= FirebaseServices();
    } catch (failure) {
      if (mounted) setState(() => error = 'Cloud connection could not start: $failure');
    }
  }

  Future<void> _bootstrap() async {
    await _loadPreferences();
    await _prepareCloud();
    if (services?.currentUser?.emailVerified == true) {
      try {
        savedHousehold = await services!.currentHousehold()
          .timeout(const Duration(seconds: 15));
      } catch (failure) {
        if (mounted) {
          setState(() => error = 'Household could not load. Tap to retry: $failure');
        }
      }
    }
    if (!mounted) return;
    setState(() => checkingAccount = false);
  }

  Future<void> _openCloud() async {
    if (busy || !await _unlock()) return;
    setState(() { busy = true; error = null; });
    try {
      if (services == null) await _prepareCloud();
      if (services == null) {
        throw StateError('Cloud connection is unavailable. Check your internet connection and try again.');
      }
      if (!mounted) return;
      setState(() => busy = false);
      if (services!.currentUser?.emailVerified != true) {
        final signedIn = await Navigator.of(navigatorKey.currentContext!).push<bool>(
          MaterialPageRoute(builder: (_) => FirebaseAccountPage(services: services!)));
        if (signedIn != true || !mounted) return;
      }
      var household = await services!.currentHousehold()
        .timeout(const Duration(seconds: 15));
      if (household == null && mounted) {
        setState(() => savedHousehold = null);
        household = await Navigator.of(navigatorKey.currentContext!).push<CloudHousehold>(
          MaterialPageRoute(builder: (_) => FirebaseHouseholdSetupPage(
            services: services!)));
      }
      if (household == null || !mounted) return;
      final selectedHousehold = household;
      setState(() => savedHousehold = selectedHousehold);
      await Navigator.of(navigatorKey.currentContext!).push<void>(MaterialPageRoute(builder: (_) =>
        CloudHouseholdPage(services: services!, household: selectedHousehold,
          darkTheme: darkTheme, biometricLock: biometricLock, pinEnabled: pinEnabled,
          onThemeChanged: (value) async {
            await widget.settings.setDarkThemeEnabled(value);
            if (mounted) setState(() => darkTheme = value);
          },
          onBiometricChanged: _setBiometricLock,
          onPinSet: (value) async {
            await widget.settings.setPin(value);
            if (mounted) setState(() { pinEnabled = true; unlocked = true; });
          },
          onShareStarted: () => sharing = true,
          onShareFinished: () => sharing = false,
        )));
      if (!mounted) return;
      if (services!.currentUser?.emailVerified == true) {
        try {
          final current = await services!.currentHousehold()
            .timeout(const Duration(seconds: 15));
          if (mounted) setState(() => savedHousehold = current);
        } catch (_) {
          // Keep the last known household available for a manual retry.
        }
      } else {
        setState(() => savedHousehold = null);
      }
    } catch (failure) {
      if (mounted) setState(() => error = 'Cloud connection could not start: $failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: 'HomeBudget', debugShowCheckedModeBanner: false,
    theme: appTheme(), darkTheme: appTheme(brightness: Brightness.dark),
    themeMode: darkTheme ? ThemeMode.dark : ThemeMode.light,
    supportedLocales: const [Locale('en')],
    home: Builder(builder: (context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 70, color: forest),
          const SizedBox(height: 20),
          Text('Welcome to HomeBudget', textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text('Your household budget, together and in sync.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          if (services?.currentUser?.emailVerified == true) ...[
            Text('Signed in as ${services!.currentUser!.email ?? ''}',
              textAlign: TextAlign.center),
            const SizedBox(height: 12),
          ],
          if (savedHousehold != null) ...[
            Text(savedHousehold!.name, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
          ],
          FilledButton.icon(onPressed: busy || checkingAccount ? null : _openCloud,
            icon: const Icon(Icons.cloud_outlined),
            label: Text(busy || checkingAccount ? 'Connecting…' :
              savedHousehold != null ? 'Open household' :
              services?.currentUser?.emailVerified == true ? 'Create or join a household' :
              'Sign in or create an account')),
          if (services?.currentUser?.emailVerified == true) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: busy || checkingAccount ? null : () async {
              await services!.signOut();
              if (mounted) setState(() => savedHousehold = null);
            }, child: const Text('Sign out')),
          ],
          const SizedBox(height: 24),
          Card(color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(leading: const Icon(Icons.school_outlined),
              title: const Text('New here? Take a quick tour'),
              subtitle: const Text('See how households, expenses and sharing work.'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () => Navigator.of(navigatorKey.currentContext!).push(
                MaterialPageRoute(builder: (_) => const AppTutorialPage())))),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 16),
            child: Text(error!, textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ])),
    ))))),
  );
}

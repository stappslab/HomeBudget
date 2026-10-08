import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import '../data/firebase_services.dart';
import '../utils/money.dart';
import '../utils/input_limits.dart';
import 'tutorial_page.dart';

class FirebaseHouseholdSetupPage extends StatefulWidget {
  const FirebaseHouseholdSetupPage({super.key, required this.services});
  final FirebaseServices services;

  @override
  State<FirebaseHouseholdSetupPage> createState() =>
      _FirebaseHouseholdSetupPageState();
}

class _FirebaseHouseholdSetupPageState
    extends State<FirebaseHouseholdSetupPage> {
  CloudHousehold? household;
  bool loading = true;
  bool busy = false;
  bool loadFailed = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final current = await widget.services.currentHousehold().timeout(
        const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        household = current;
        loading = false;
        loadFailed = false;
        error = null;
      });
    } on FirebaseException catch (failure) {
      if (!mounted) return;
      final message = switch (failure.code) {
        'permission-denied' =>
          'Cloud access was denied. Check email verification and publish the latest Firestore rules.',
        'unavailable' =>
          'Cloud is unavailable. Check your connection and try again.',
        _ =>
          'Cloud household could not load (${failure.code}). Please try again.',
      };
      setState(() {
        loading = false;
        loadFailed = true;
        error = message;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          loadFailed = true;
          error = 'Cloud household could not load. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Cloud household'),
      actions: const [TutorialHelpButton(topic: TutorialTopic.household)],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.cloud_sync_outlined, size: 64),
                      const SizedBox(height: 20),
                      if (household != null) ...[
                        Text(
                          'Cloud household connected',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(household!.name, textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, household),
                          child: const Text('Continue'),
                        ),
                      ] else if (!loadFailed) ...[
                        Text(
                          'Set up shared access',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Create a shared household or request access with an invite code.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          onPressed: busy ? null : create,
                          icon: const Icon(Icons.add_home_outlined),
                          label: const Text('Create a cloud household'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: busy ? null : join,
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text('Enter an invite code'),
                        ),
                      ],
                      if (error != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => loading = true);
                            load();
                          },
                          child: const Text('Try again'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
  );

  Future<void> create() async {
    final created = await showDialog<CloudHousehold>(
      context: context,
      builder: (_) => _CreateCloudHouseholdDialog(services: widget.services),
    );
    if (created == null || !mounted) return;
    Navigator.pop(context, created);
  }

  Future<void> join() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinCodeDialog(),
    );
    if (code == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.services.requestToJoin(code);
      if (!mounted) return;
      setState(
        () => error = 'Request sent. The household owner must approve it.',
      );
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _CreateCloudHouseholdDialog extends StatefulWidget {
  const _CreateCloudHouseholdDialog({required this.services});
  final FirebaseServices services;
  @override
  State<_CreateCloudHouseholdDialog> createState() =>
      _CreateCloudHouseholdDialogState();
}

class _CreateCloudHouseholdDialogState
    extends State<_CreateCloudHouseholdDialog> {
  final name = TextEditingController();
  String currency = 'RSD';
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New cloud household'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Choose a name and main currency for your shared household.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: name,
          maxLength: maxHouseholdNameLength,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Household name'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: currency,
          decoration: const InputDecoration(labelText: 'Main currency'),
          items: supportedCurrencies
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList(),
          onChanged: (value) => setState(() => currency = value ?? currency),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: busy || name.text.trim().isEmpty ? null : save,
        child: Text(busy ? 'Creating…' : 'Create'),
      ),
    ],
  );
  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = await widget.services.createHousehold(
        name: name.text,
        currency: currency,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        CloudHousehold(
          id: id,
          name: name.text.trim(),
          currency: currency,
          memberName:
              widget.services.currentUser?.displayName ?? 'Household member',
          ownerId: widget.services.currentUser!.uid,
        ),
      );
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not create household: $failure';
        });
      }
    }
  }
}

class _JoinCodeDialog extends StatefulWidget {
  const _JoinCodeDialog();
  @override
  State<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<_JoinCodeDialog> {
  final code = TextEditingController();
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Join a household'),
    content: TextField(
      controller: code,
      maxLength: maxInviteCodeLength,
      onChanged: (_) => setState(() {}),
      autocorrect: false,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(labelText: 'Invite code'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: code.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, code.text),
        child: const Text('Request access'),
      ),
    ],
  );
}

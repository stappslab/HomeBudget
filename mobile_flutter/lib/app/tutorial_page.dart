import 'package:flutter/material.dart';

class AppTutorialPage extends StatefulWidget {
  const AppTutorialPage({super.key});
  @override State<AppTutorialPage> createState() => _AppTutorialPageState();
}

class _AppTutorialPageState extends State<AppTutorialPage> {
  final controller = PageController();
  var page = 0;
  static const steps = [
    ('Welcome', 'Create an account, then create or join a household.'),
    ('Your budget', 'See monthly spending, budget progress and recent expenses.'),
    ('Settings', 'Choose your currency, theme, PIN and biometric lock.'),
    ('Add an expense', 'Enter an amount and category. Mark it shared if everyone should see it.'),
    ('Another currency', 'Enter your exchange rate. Totals use the main currency.'),
    ('Invite members', 'Share a one-time code. The owner approves each request.'),
  ];

  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('How HomeBudget works'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip'))]),
    body: SafeArea(child: Column(children: [
      Expanded(child: PageView.builder(controller: controller, itemCount: steps.length, onPageChanged: (value) => setState(() => page = value), itemBuilder: (_, index) => _TutorialStep(index: index))),
      Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(steps.length, (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: index == page ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: index == page ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(8),
            ),
          )),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: () {
          if (page == steps.length - 1) {
            Navigator.pop(context);
          } else {
            controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
          }
        }, child: Text(page == steps.length - 1 ? 'Start using HomeBudget' : 'Next')),
      ])),
    ])),
  );
}

class _TutorialStep extends StatelessWidget {
  const _TutorialStep({required this.index}); final int index;
  @override Widget build(BuildContext context) {
    final step = _AppTutorialPageState.steps[index];
    return LayoutBuilder(builder: (context, bounds) {
      final previewHeight = (bounds.maxHeight * .56).clamp(230.0, 440.0);
      return SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(children: [
          SizedBox(height: previewHeight, width: double.infinity,
            child: _PhonePreview(index: index)),
          const SizedBox(height: 16),
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480),
            child: Container(width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.lightbulb_outline, size: 20,
                  color: Theme.of(context).colorScheme.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(step.$1, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(step.$2, style: Theme.of(context).textTheme.bodyMedium),
                ])),
              ])),
          ),
        ]));
    });
  }
}

class _PhonePreview extends StatelessWidget {
  const _PhonePreview({required this.index}); final int index;
  @override Widget build(BuildContext context) => Center(child: FittedBox(
    fit: BoxFit.contain,
    child: SizedBox(width: 360, height: 620,
      child: MediaQuery.withNoTextScaling(child: DecoratedBox(
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface,
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 2),
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 18, offset: Offset(0, 8))]),
        child: ClipRRect(borderRadius: BorderRadius.circular(30),
          child: Padding(padding: const EdgeInsets.all(22), child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: index == 0 ? _welcome() : switch (index) {
                1 => _home(), 2 => _settings(),
                3 => _expense(false), 4 => _expense(true), _ => _members(),
              }))),
      ))),
    ),
  );
  Widget _title(String text) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700));
  Widget _card(Widget child) => Card(margin: const EdgeInsets.only(top: 12), child: Padding(padding: const EdgeInsets.all(12), child: child));
  Widget _item(IconData icon, String title, String detail, {String? amount}) => _card(Row(children: [
    CircleAvatar(radius: 18, child: Icon(icon, size: 19)),
    const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12)),
    ])),
    if (amount != null) ...[const SizedBox(width: 8), Text(amount,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))],
  ]));
  Widget _detailRow(String label, String value) => Row(children: [
    Expanded(child: Text(label)),
    Flexible(child: Text(value, textAlign: TextAlign.end, maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w600))),
  ]);
  Widget _welcome() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.account_balance_wallet_outlined, size: 56), const SizedBox(height: 18), _title('Welcome, John'), const SizedBox(height: 8), const Text('Your household budget, together.'), const SizedBox(height: 20), FilledButton(onPressed: null, child: const Text('Create account')), OutlinedButton(onPressed: null, child: const Text('Sign in'))]);
  Widget _home() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_title('Good evening, John'), const SizedBox(height: 4), const Text('September 2026'), _card(const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Spent this month'), Text('42,580 RSD', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)), LinearProgressIndicator(value: .62), SizedBox(height: 5), Text('62% of 68,000 RSD')])), const SizedBox(height: 12), FilledButton.icon(onPressed: null, icon: const Icon(Icons.add), label: const Text('Add expense')), _item(Icons.shopping_cart_outlined, 'Groceries', 'Today', amount: '8,420 RSD')]);
  Widget _settings() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_title('Settings'), _card(_detailRow('Main currency', 'RSD')), _card(_detailRow('Dark theme', 'On')), _card(_detailRow('Biometric lock', 'On')), _item(Icons.lock_outline, 'App PIN', 'Protect this device')]);
  Widget _expense(bool foreign) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _title('New expense'),
    _card(const Text('Amount\n2,450.00', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
    _card(Column(children: [
      _detailRow('Category', 'Groceries'),
      const SizedBox(height: 8),
      _detailRow('Currency', foreign ? 'EUR' : 'RSD'),
    ])),
    if (foreign) _card(const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Exchange rate'), Text('1 EUR = 117.20 RSD'),
      Text('Total: 287,140 RSD'),
    ])),
    _card(_detailRow('Shared expense', 'On')),
    const SizedBox(height: 16),
    FilledButton(onPressed: null, child: const Text('Save expense')),
  ]);
  Widget _members() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_title('Household members'), _item(Icons.person_outline, 'John Smith', 'Owner'), _item(Icons.person_outline, 'Anna Smith', 'Member'), const SizedBox(height: 12), OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.key_outlined), label: const Text('Create invite code')), _card(const Text('Anna enters the code. John approves her request.'))]);
}

import 'package:flutter/material.dart';

enum TutorialTopic {
  all,
  home,
  activity,
  plan,
  recurring,
  insights,
  settings,
  account,
  household,
  payment,
}

String tutorialTitle(TutorialTopic topic) => switch (topic) {
  TutorialTopic.all => 'How Home Budget works',
  TutorialTopic.home => 'Home help',
  TutorialTopic.activity => 'Activity help',
  TutorialTopic.plan => 'Plan help',
  TutorialTopic.recurring => 'Recurring help',
  TutorialTopic.insights => 'Insights help',
  TutorialTopic.settings => 'Settings help',
  TutorialTopic.account => 'Account help',
  TutorialTopic.household => 'Household help',
  TutorialTopic.payment => 'Expense help',
};

List<int> tutorialSteps(TutorialTopic topic) => switch (topic) {
  TutorialTopic.all => const [0, 1, 2, 3, 13, 4, 5, 12, 6, 7, 8, 9, 10, 11],
  TutorialTopic.home => const [13, 2, 10],
  TutorialTopic.activity => const [12, 4, 11],
  TutorialTopic.plan => const [2],
  TutorialTopic.recurring => const [6, 7, 8, 9, 11],
  TutorialTopic.insights => const [10, 8, 11],
  TutorialTopic.settings => const [1, 3],
  TutorialTopic.account => const [0],
  TutorialTopic.household => const [0, 3],
  TutorialTopic.payment => const [4, 5, 7, 8, 11],
};

/// Help opens a separate route so drafts, filters and the underlying screen survive.
class TutorialHelpButton extends StatelessWidget {
  const TutorialHelpButton({super.key, required this.topic, this.color});
  final TutorialTopic topic;
  final Color? color;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tutorialTitle(topic),
    color: color,
    icon: const Icon(Icons.help_outline),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AppTutorialPage(topic: topic)),
    ),
  );
}

class AppTutorialPage extends StatefulWidget {
  const AppTutorialPage({super.key, this.topic = TutorialTopic.all});
  final TutorialTopic topic;
  @override
  State<AppTutorialPage> createState() => _AppTutorialPageState();
}

class _AppTutorialPageState extends State<AppTutorialPage> {
  final controller = PageController();
  var page = 0;
  List<int> get selectedSteps => tutorialSteps(widget.topic);
  static const steps = [
    (
      'Start your household',
      'John Smith creates an account, verifies his email and creates a cloud household. On later visits, he opens the saved household without signing in again.',
    ),
    (
      'Protect this phone',
      'John chooses the main currency when creating the household. Settings controls the theme, device PIN and biometric lock. Return to start keeps him signed in. An owner must transfer ownership before leaving.',
    ),
    (
      'Plan the month',
      'In Expenses → Plan, John sets the total monthly budget and taps a category to set its limit. Add category creates a new one; its menu can rename or remove it without deleting past expenses. Only the owner manages the plan.',
    ),
    (
      'Invite Anna',
      'John shares a single-use invite code using his chat or email app. Anna signs in, enters it and waits for John’s approval before seeing household data.',
    ),
    (
      'Record everyday spending',
      'John saves groceries with a category, date and optional description. Shared expenses appear in the member comparisons. Editing or deleting a real expense updates spending.',
    ),
    (
      'Use another currency',
      'John saves a 25 EUR purchase at his own rate of 1 EUR = 117.20 RSD. Activity keeps the original 25 EUR; budgets and totals include 2,930 RSD.',
    ),
    (
      'Set up monthly rent',
      'In Expenses → Recurring, John adds Rent: 1,000 EUR, Home, shared, due on day 5 with a three-day grace period. This creates an obligation, not an expense.',
    ),
    (
      'Recognize a payment',
      'On Save, matching category, currency, sharing and description Rent offers a link. A blank description offers matching candidates. John confirms or saves an ordinary expense instead. Link existing connects one already saved, without duplicating it.',
    ),
    (
      'Pay in parts',
      'John confirms a 400 EUR rent payment. Rent shows 400 EUR paid and 600 EUR remaining. A second 600 EUR payment completes that month. A larger payment requires an overpayment confirmation.',
    ),
    (
      'Correct a mistake',
      'To fix Dining → Home, John edits Rent. Only future payments keeps this month’s saved category. Also update this month’s linked payments corrects the current payments only if he authored all of them. Earlier months stay unchanged.',
    ),
    (
      'Know what remains',
      'Insights warns about current-month category budgets and overdue unpaid balances. After the grace period, partly paid Rent warns only about the remaining 600 EUR.',
    ),
    (
      'Keep history accurate',
      'Unlinking keeps the expense in spending but removes it from Rent’s paid amount. Deleting removes the expense from both. New months start with an unpaid obligation; previous monthly expectations stay saved.',
    ),
    (
      'Find any expense',
      'In Expenses → Activity, John chooses a month, Last 30 days, All time or a custom date range. He combines search with category, currency and shared/personal filters. Search and the displayed total cover loaded entries; Load more includes older entries.',
    ),
    (
      'Read your dashboard',
      'Home greets John and shows the remaining total monthly budget, spending pockets and recent activity. View all budgets and categories opens Plan. Tap Add expense to record spending; the avatar returns to the start screen without signing out.',
    ),
  ];

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tutorialTitle(widget.topic)),
      actions: [
        if (widget.topic != TutorialTopic.all)
          PopupMenuButton<String>(
            tooltip: 'More help',
            onSelected: (_) => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(builder: (_) => const AppTutorialPage()),
            ),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'all', child: Text('Full tutorial')),
            ],
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.topic == TutorialTopic.all ? 'Skip' : 'Close'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: controller,
              itemCount: selectedSteps.length,
              onPageChanged: (value) => setState(() => page = value),
              itemBuilder: (_, index) =>
                  _TutorialStep(index: selectedSteps[index]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      selectedSteps.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: index == page ? 20 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: index == page
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${page + 1} / ${selectedSteps.length}',
                  textAlign: TextAlign.center,
                ),
                if (page > 0)
                  TextButton(
                    onPressed: () => controller.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    child: const Text('Previous'),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () {
                    if (page == selectedSteps.length - 1) {
                      Navigator.pop(context);
                    } else {
                      controller.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: Text(
                    page == selectedSteps.length - 1
                        ? (widget.topic == TutorialTopic.all
                              ? 'Start using Home Budget'
                              : 'Back to screen')
                        : 'Next',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _TutorialStep extends StatelessWidget {
  const _TutorialStep({required this.index});
  final int index;
  @override
  Widget build(BuildContext context) {
    final step = _AppTutorialPageState.steps[index];
    return LayoutBuilder(
      builder: (context, bounds) {
        final previewHeight = (bounds.maxHeight * .56).clamp(230.0, 440.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              SizedBox(
                height: previewHeight,
                width: double.infinity,
                child: _PhonePreview(index: index),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        size: 20,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.$1,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              step.$2,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PhonePreview extends StatelessWidget {
  const _PhonePreview({required this.index});
  final int index;
  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: 360,
        height: 620,
        child: MediaQuery.withNoTextScaling(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: switch (index) {
                    0 => _welcome(),
                    1 => _settings(),
                    2 => _plan(),
                    3 => _members(),
                    4 => _expense(false),
                    5 => _expense(true),
                    6 => _recurring(false),
                    7 => _linkPrompt(),
                    8 => _recurring(true),
                    9 => _correction(),
                    10 => _insights(),
                    12 => _activity(),
                    13 => _home(),
                    _ => _history(),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget _title(String text) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
  );
  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.only(top: 12),
    child: Padding(padding: const EdgeInsets.all(12), child: child),
  );
  Widget _item(IconData icon, String title, String detail, {String? amount}) =>
      _card(
        Row(
          children: [
            CircleAvatar(radius: 18, child: Icon(icon, size: 19)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (amount != null) ...[
              const SizedBox(width: 8),
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      );
  Widget _detailRow(String label, String value) => Row(
    children: [
      Expanded(child: Text(label)),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
  Widget _welcome() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(Icons.account_balance_wallet_outlined, size: 56),
      const SizedBox(height: 18),
      _title('Welcome, John'),
      const SizedBox(height: 8),
      const Text('Your household budget, together.'),
      const SizedBox(height: 20),
      FilledButton(onPressed: null, child: const Text('Create account')),
      OutlinedButton(onPressed: null, child: const Text('Sign in')),
    ],
  );
  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('Settings'),
      _card(_detailRow('Main currency', 'RSD')),
      _card(_detailRow('Dark theme', 'On')),
      _card(_detailRow('Biometric lock', 'On')),
      _item(Icons.lock_outline, 'App PIN', 'Protect this device'),
    ],
  );
  Widget _plan() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('Expenses · Plan'),
      _card(_detailRow('Monthly budget', '68,000 RSD')),
      _item(
        Icons.shopping_basket_outlined,
        'Groceries',
        '13,620 of 20,000 RSD',
      ),
      _item(Icons.home_outlined, 'Home', '10,200 of 18,000 RSD'),
      _item(Icons.directions_car_outlined, 'Transport', '6,810 of 10,000 RSD'),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
    ],
  );
  Widget _recurring(bool paid) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('Expenses · Recurring'),
      const SizedBox(height: 10),
      const Text('September 2026', style: TextStyle(fontSize: 16)),
      _item(
        Icons.home_outlined,
        'Rent',
        paid ? 'Partially paid · day 5' : 'Due on day 5',
        amount: '1,000 EUR',
      ),
      _card(_detailRow(paid ? 'Paid' : 'Category', paid ? '400 EUR' : 'Home')),
      if (paid) _card(_detailRow('Remaining', '600 EUR')),
      _card(_detailRow('Grace period', '3 days')),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: null,
        icon: Icon(paid ? Icons.check_circle_outline : Icons.add),
        label: Text(paid ? 'Record remaining payment' : 'Record payment'),
      ),
      if (!paid)
        OutlinedButton(
          onPressed: null,
          child: const Text('Link existing expense'),
        ),
    ],
  );
  Widget _insights() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('Insights'),
      _card(
        const Text(
          'This month · 42,580 RSD',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ),
      _item(
        Icons.warning_amber_rounded,
        'Groceries budget',
        '90% used this month',
      ),
      _item(
        Icons.event_repeat_outlined,
        'Rent may be overdue',
        '600 EUR remains unpaid',
      ),
      _item(
        Icons.people_outline,
        'Shared spending',
        'John 18,400 · Anna 12,850',
      ),
    ],
  );
  Widget _expense(bool foreign) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('New expense'),
      _card(
        Text(
          foreign ? 'Amount\n25.00' : 'Amount\n2,450.00',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
      _card(
        Column(
          children: [
            _detailRow('Category', 'Groceries'),
            const SizedBox(height: 8),
            _detailRow('Currency', foreign ? 'EUR' : 'RSD'),
          ],
        ),
      ),
      if (foreign)
        _card(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Exchange rate'),
              Text('1 EUR = 117.20 RSD'),
              Text('Total: 2,930 RSD'),
            ],
          ),
        ),
      _card(_detailRow('Shared expense', 'On')),
      const SizedBox(height: 16),
      FilledButton(onPressed: null, child: const Text('Save expense')),
    ],
  );
  Widget _linkPrompt() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title('Link to Rent?'),
      _card(
        const Text(
          'Payment month: 2026-09\nExpected: 1,000 EUR\nAlready paid: 0 EUR\nThis payment: 400 EUR',
        ),
      ),
      _card(
        const Text('Record a partial payment? 600 EUR will remain unpaid.'),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: null, child: const Text('Confirm payment')),
      OutlinedButton(onPressed: null, child: const Text('Cancel')),
    ],
  );
  Widget _correction() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title('Apply this change to…'),
      _card(
        const Text(
          'Rent category: Dining → Home\nPrevious months stay unchanged.',
        ),
      ),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: null,
        child: const Text('Only future payments'),
      ),
      FilledButton(
        onPressed: null,
        child: const Text('Also update this month’s linked payments'),
      ),
      _card(
        const Text(
          'Payments by other members must be corrected by their authors.',
        ),
      ),
    ],
  );
  Widget _history() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('Rent · September'),
      _item(
        Icons.home_outlined,
        'First payment',
        'Linked to Rent',
        amount: '400 EUR',
      ),
      _item(
        Icons.home_outlined,
        'Second payment',
        'Unlinked · still spending',
        amount: '600 EUR',
      ),
      _card(_detailRow('Remaining rent', '600 EUR')),
      _card(
        const Text(
          'Deleting a payment removes its actual spending. The obligation remains.',
        ),
      ),
    ],
  );
  Widget _activity() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _title('Expenses · Activity'),
      _card(_detailRow('Period', 'September 2026')),
      _card(const Text('Search expenses…')),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        children: [
          const Chip(label: Text('Shared')),
          const Chip(label: Text('Home')),
          const Chip(label: Text('EUR')),
        ],
      ),
      _item(Icons.home_outlined, 'Rent', '5 Sep · shared', amount: '400 EUR'),
      _card(_detailRow('Loaded total', '46,880 RSD')),
      OutlinedButton(onPressed: null, child: const Text('Load more')),
    ],
  );
  Widget _home() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _card(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Good evening, John.',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            Text('SAFE TO SPEND'),
            Text('25,420 RSD', style: TextStyle(fontSize: 24)),
            Text('42,580 spent of 68,000 RSD'),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _title('Your spending pockets'),
      _item(Icons.shopping_basket_outlined, 'Groceries', '6,380 RSD remaining'),
      _item(Icons.home_outlined, 'Home', '7,800 RSD remaining'),
      OutlinedButton(
        onPressed: null,
        child: const Text('View all budgets and categories'),
      ),
      FilledButton(onPressed: null, child: const Text('Add expense')),
    ],
  );
  Widget _members() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _title('Household members'),
      _item(Icons.person_outline, 'John Smith', 'Owner'),
      _item(Icons.person_outline, 'Anna Smith', 'Member'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.key_outlined),
        label: const Text('Create invite code'),
      ),
      _card(const Text('Anna enters the code. John approves her request.')),
    ],
  );
}

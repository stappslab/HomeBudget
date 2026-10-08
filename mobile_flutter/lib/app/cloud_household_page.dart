import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../data/cloud_totals.dart';
import '../data/firebase_services.dart';
import '../data/recurring_period.dart';
import '../data/recurring_payments.dart';
import 'recurring_payment_dialog.dart';
import '../utils/input_limits.dart';
import '../utils/expense_period.dart';
import '../utils/money.dart';
import 'budget_amount_dialog.dart';
import 'tutorial_page.dart';

class CloudHouseholdPage extends StatefulWidget {
  const CloudHouseholdPage({
    super.key,
    required this.services,
    required this.household,
    required this.darkTheme,
    required this.biometricLock,
    required this.pinEnabled,
    required this.onThemeChanged,
    required this.onBiometricChanged,
    required this.onPinSet,
    this.onShareStarted,
    this.onShareFinished,
  });
  final FirebaseServices services;
  final CloudHousehold household;
  final bool darkTheme, biometricLock;
  final bool pinEnabled;
  final Future<void> Function(bool) onThemeChanged, onBiometricChanged;
  final Future<void> Function(String) onPinSet;
  final VoidCallback? onShareStarted, onShareFinished;

  @override
  State<CloudHouseholdPage> createState() => _CloudHouseholdPageState();
}

class _CloudHouseholdPageState extends State<CloudHouseholdPage> {
  late final Stream<List<CloudExpense>> expenses = widget.services
      .watchExpenses(widget.household.id);
  late final Stream<List<CloudCategory>> categories = widget.services
      .watchCategories(widget.household.id);
  late final Stream<List<CloudBudget>> budgets = widget.services.watchBudgets(
    widget.household.id,
  );
  late final Stream<DateTime> sharedReset = widget.services.watchSharedResetAt(
    widget.household.id,
  );
  late final Stream<List<CloudRecurringTemplate>> recurringTemplates = widget
      .services
      .watchRecurringTemplates(widget.household.id);
  StreamSubscription<List<CloudRecurringTemplate>>? recurringSubscription;
  List<CloudRecurringTemplate> latestRecurring = const [];
  List<CloudCategory> latestCategories = const [];
  List<CloudCategory> allCategories = const [];
  late bool darkTheme = widget.darkTheme;
  late bool biometricLock = widget.biometricLock;
  late bool pinEnabled = widget.pinEnabled;
  int tab = 0;
  int expensesSection = 0;
  final tabHistory = <int>[];
  bool closing = false;
  final Set<String> deletingExpenseIds = {};
  final search = TextEditingController();
  String expenseType = 'all';
  String? expenseCategory;
  String? expenseCurrency;
  ExpensePeriodMode expensePeriodMode = ExpensePeriodMode.month;
  DateTime expenseMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTimeRange? customExpenseDates;
  DateTime recurringDate = DateTime(DateTime.now().year, DateTime.now().month);
  final Set<String> insightCategories = {};
  static const historyPageSize = 100;
  int historyLimit = historyPageSize;
  String? historyQueryKey;
  Stream<List<CloudExpense>>? historyStream;
  String? recurringExpenseMonth;
  Stream<List<CloudExpense>>? recurringExpenseStream;
  Stream<List<CloudRecurringOccurrence>>? recurringPeriodStream;
  late final insightPayments = widget.services.watchRecurringPayments(
    widget.household.id,
    recurringMonth(DateTime.now()),
  );
  late final insightPeriods = widget.services.watchRecurringOccurrences(
    widget.household.id,
    recurringMonth(DateTime.now()),
  );
  Future<(Map<String, int>, List<CloudMember>)>? runningSummary;
  String? runningSummaryKey;

  Future<(Map<String, int>, List<CloudMember>)> _loadRunningSummary(
    DateTime resetAt,
  ) async {
    final members = await widget.services.members(widget.household.id);
    final totals = await widget.services.sharedRunningTotals(
      widget.household.id,
      resetAt,
      members.map((member) => member.uid).toList(),
    );
    return (totals, members);
  }

  @override
  void initState() {
    super.initState();
    recurringSubscription = recurringTemplates.listen(
      (value) {
        if (mounted) setState(() => latestRecurring = value);
      },
      onError: (Object error) {
        if (mounted) _showError(error);
      },
    );
  }

  @override
  void dispose() {
    recurringSubscription?.cancel();
    search.dispose();
    super.dispose();
  }

  bool get owner =>
      widget.household.ownerId == widget.services.currentUser?.uid;

  void _selectTab(int value) {
    if (value == tab) return;
    setState(() {
      tabHistory.add(tab);
      tab = value;
      if (value == 2) runningSummaryKey = null;
    });
  }

  void _goBackTab() {
    if (tabHistory.isEmpty) {
      Navigator.pop(context);
      return;
    }
    setState(() => tab = tabHistory.removeLast());
  }

  void _returnToStart() {
    setState(() => closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: closing || tabHistory.isEmpty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && tabHistory.isNotEmpty) _goBackTab();
    },
    child: Scaffold(
      appBar: tab == 0
          ? null
          : AppBar(
              title: Text(switch (tab) {
                1 => 'Expenses',
                2 => 'Insights',
                _ => 'Settings',
              }),
              actions: [
                TutorialHelpButton(
                  topic: switch (tab) {
                    1 => switch (expensesSection) {
                      1 => TutorialTopic.plan,
                      2 => TutorialTopic.recurring,
                      _ => TutorialTopic.activity,
                    },
                    2 => TutorialTopic.insights,
                    _ => TutorialTopic.settings,
                  },
                ),
              ],
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Previous screen',
                onPressed: _goBackTab,
              ),
            ),
      body: StreamBuilder<List<CloudCategory>>(
        stream: categories,
        builder: (context, categorySnapshot) {
          if (categorySnapshot.hasError) return _error(categorySnapshot.error!);
          if (!categorySnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          allCategories = categorySnapshot.data!;
          latestCategories = allCategories
              .where((category) => !category.archived)
              .toList();
          return StreamBuilder<List<CloudExpense>>(
            stream: expenses,
            builder: (context, expenseSnapshot) {
              return StreamBuilder<List<CloudBudget>>(
                stream: budgets,
                builder: (context, budgetSnapshot) {
                  if (tab == 3) return _settings();
                  if (expenseSnapshot.hasError) {
                    return _error(expenseSnapshot.error!);
                  }
                  if (!expenseSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = expenseSnapshot.data!;
                  final names = {
                    for (final c in categorySnapshot.data!) c.id: c.name,
                  };
                  return switch (tab) {
                    0 => _overview(items, names, budgetSnapshot),
                    1 => _expensesTab(items, names, budgetSnapshot),
                    _ => _insights(items, names, budgetSnapshot),
                  };
                },
              );
            },
          );
        },
      ),
      floatingActionButton: (tab == 0 || (tab == 1 && expensesSection == 0))
          ? FloatingActionButton.extended(
              onPressed: _addExpense,
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Expenses',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            label: 'Settings',
          ),
        ],
      ),
    ),
  );

  Widget _error(Object error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'Cloud data could not load. Check your connection and access.\n$error',
        textAlign: TextAlign.center,
      ),
    ),
  );

  Widget _overview(
    List<CloudExpense> items,
    Map<String, String> names,
    AsyncSnapshot<List<CloudBudget>> budgetSnapshot,
  ) {
    final totals = calculateCloudTotals(items, DateTime.now());
    if (budgetSnapshot.hasError) return _error(budgetSnapshot.error!);
    if (!budgetSnapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    final limits = {
      for (final budget in budgetSnapshot.data!)
        budget.categoryId: budget.amountCents,
    };
    final monthly = limits[''];
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _CloudHero(
          memberName: widget.household.memberName,
          currency: widget.household.currency,
          spent: totals.monthlyCents,
          budget: monthly,
          onStart: _returnToStart,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (totals.unconvertedCount > 0)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.currency_exchange),
                    title: Text(
                      '${totals.unconvertedCount} expenses need a conversion rate',
                    ),
                    subtitle: const Text('They are excluded from totals.'),
                  ),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  'Your spending pockets',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    setState(() => expensesSection = 1);
                    _selectTab(1);
                  },
                  icon: const Icon(Icons.tune_outlined),
                  label: const Text('View all budgets and categories'),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.savings_outlined),
                      title: const Text('Monthly budget'),
                      subtitle: Text(
                        monthly == null
                            ? 'Not set'
                            : '${money(totals.monthlyCents, widget.household.currency)} of ${money(monthly, widget.household.currency)} spent',
                      ),
                      trailing: owner ? const Icon(Icons.edit_outlined) : null,
                      onTap: owner
                          ? () => _setBudget('', 'Monthly', monthly)
                          : null,
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: latestCategories.length > 4
                        ? 4
                        : latestCategories.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          mainAxisExtent: 164,
                        ),
                    itemBuilder: (context, index) {
                      final category = latestCategories[index];
                      return _CloudPocket(
                        category: category.name,
                        cents: totals.byCategory[category.id] ?? 0,
                        budgetCents: limits[category.id],
                        currency: widget.household.currency,
                        index: index,
                        onTap: owner
                            ? () => _setBudget(
                                category.id,
                                category.name,
                                limits[category.id],
                              )
                            : null,
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _addExpense,
                icon: const Icon(Icons.add),
                label: const Text('Add expense'),
              ),
              const SizedBox(height: 12),
              Text(
                'Recent activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('No recent expenses.'),
                  ),
                ),
              ...items.take(5).map((item) => _expenseTile(item, names)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _expensesTab(
    List<CloudExpense> items,
    Map<String, String> names,
    AsyncSnapshot<List<CloudBudget>> budgetSnapshot,
  ) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.receipt_long_outlined),
                label: Text('Activity'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.savings_outlined),
                label: Text('Plan'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.event_repeat_outlined),
                label: Text('Recurring'),
              ),
            ],
            selected: {expensesSection},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                setState(() => expensesSection = selection.first),
          ),
        ),
      ),
      Expanded(
        child: switch (expensesSection) {
          0 => _activity(names),
          1 => _budgetPlan(items, budgetSnapshot),
          _ => _recurringTab(names),
        },
      ),
    ],
  );

  Widget _activity(Map<String, String> names) {
    final period = ExpensePeriod(
      mode: expensePeriodMode,
      month: expenseMonth,
      customRange: customExpenseDates,
    );
    final range = period.range(DateTime.now());
    final start = range?.start;
    final end = range == null
        ? null
        : DateTime(range.end.year, range.end.month, range.end.day + 1);
    final periodKey = '${start?.toIso8601String()}/${end?.toIso8601String()}';
    if (historyQueryKey?.split('|').first != periodKey) {
      historyLimit = historyPageSize;
    }
    final key = '$periodKey|$historyLimit';
    if (historyQueryKey != key) {
      historyQueryKey = key;
      historyStream = widget.services.watchExpenseHistory(
        widget.household.id,
        start: start,
        end: end,
        limit: historyLimit + 1,
      );
    }
    return StreamBuilder<List<CloudExpense>>(
      stream: historyStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return _error(snapshot.error!);
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final more = snapshot.data!.length > historyLimit;
        return _expenseList(
          snapshot.data!.take(historyLimit).toList(),
          names,
          hasMore: more,
        );
      },
    );
  }

  Widget _recurringTab(Map<String, String> names) {
    final month = recurringMonth(recurringDate);
    if (recurringExpenseMonth != month) {
      recurringExpenseMonth = month;
      recurringExpenseStream = widget.services.watchRecurringPayments(
        widget.household.id,
        month,
      );
      recurringPeriodStream = widget.services.watchRecurringOccurrences(
        widget.household.id,
        month,
      );
    }
    return StreamBuilder<List<CloudExpense>>(
      key: ValueKey('recurring-expenses-$month'),
      stream: recurringExpenseStream,
      builder: (context, expenseSnapshot) {
        if (expenseSnapshot.hasError) return _error(expenseSnapshot.error!);
        if (!expenseSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = expenseSnapshot.data!;
        return StreamBuilder<List<CloudRecurringOccurrence>>(
          key: ValueKey(month),
          stream: recurringPeriodStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _error(snapshot.error!);
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final grouped = groupRecurringPayments(items, month);
            final paid = {
              for (final occurrence in snapshot.data!)
                occurrence.recurringId: occurrence,
            };
            final visible = latestRecurring
                .where(
                  (template) =>
                      template.startMonth.compareTo(month) <= 0 &&
                      (!template.archived || paid.containsKey(template.id)),
                )
                .toList();
            final now = DateTime.now();
            final isCurrentMonth =
                recurringDate.year == now.year &&
                recurringDate.month == now.month;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(
                        () => recurringDate = DateTime(
                          recurringDate.year,
                          recurringDate.month - 1,
                        ),
                      ),
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Previous month',
                    ),
                    Expanded(
                      child: Text(
                        DateFormat.yMMMM().format(recurringDate),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: isCurrentMonth
                          ? null
                          : () => setState(
                              () => recurringDate = DateTime(
                                recurringDate.year,
                                recurringDate.month + 1,
                              ),
                            ),
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next month',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Payments appear here when linked to a real expense. The month resets automatically.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (visible.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text('No recurring expenses for this month'),
                      subtitle: Text(
                        'Add a monthly item such as rent, utilities, or a subscription.',
                      ),
                    ),
                  ),
                for (final template in visible)
                  _recurringCard(
                    template,
                    paid[template.id],
                    grouped[template.id] ?? const [],
                    names,
                  ),
                if (owner)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton.icon(
                      onPressed: () => _editRecurring(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add recurring expense'),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _recurringCard(
    CloudRecurringTemplate template,
    CloudRecurringOccurrence? occurrence,
    List<CloudExpense> items,
    Map<String, String> names,
  ) {
    final effective = occurrence?.effectiveTemplate(template) ?? template;
    final summary = summarizeRecurringPayments(effective, items);
    final due = recurringDueDate(
      recurringDate.year,
      recurringDate.month,
      effective.dueDay,
    );
    final status = recurringStatus(
      paid: summary.settled,
      paidCents: summary.paidCents,
      expectedCents: summary.expectedCents,
      today: DateTime.now(),
      dueDate: due,
      graceDays: effective.graceDays,
    );
    final label = switch (status) {
      RecurringStatus.paid => 'Paid',
      RecurringStatus.overpaid => 'Overpaid',
      RecurringStatus.partial => 'Partially paid',
      RecurringStatus.overdue => 'Overdue',
      RecurringStatus.due => 'Due',
      RecurringStatus.upcoming => 'Upcoming',
    };
    final syncing = items.any((item) => item.pendingSync);
    final balance = summary.overpaidCents > 0
        ? 'Overpaid: ${money(summary.overpaidCents, effective.currency)}'
        : 'Remaining: ${money(summary.remainingCents, effective.currency)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _cloudCategoryIcon(names[effective.categoryId] ?? 'Other'),
              ),
              title: Text(effective.name),
              subtitle: Text(
                '${names[effective.categoryId] ?? 'Category'} · '
                '${effective.dueDay == 0 ? 'End of month' : 'Day ${effective.dueDay}'} · $label${syncing ? ' · syncing' : ''}',
              ),
              trailing: owner
                  ? PopupMenuButton<String>(
                      onSelected: (value) => value == 'edit'
                          ? _editRecurring(template)
                          : _archiveRecurring(template),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'archive',
                          child: Text(
                            template.archived ? 'Restore' : 'Archive',
                          ),
                        ),
                      ],
                    )
                  : null,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Expected: ${money(summary.expectedCents, effective.currency)}\n'
                'Paid: ${money(summary.paidCents, effective.currency)}\n$balance',
              ),
            ),
            const SizedBox(height: 8),
            if (!template.archived)
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  children: [
                    TextButton(
                      onPressed: () => _linkExisting(effective, items),
                      child: const Text('Link existing'),
                    ),
                    FilledButton(
                      onPressed: () => _addExpense(
                        template: effective,
                        month: recurringMonth(recurringDate),
                        paymentCents: summary.remainingCents > 0
                            ? summary.remainingCents
                            : null,
                      ),
                      child: const Text('Record payment'),
                    ),
                  ],
                ),
              ),
            for (final payment in items) ...[
              if (payment.categoryId != effective.categoryId ||
                  payment.isShared != effective.isShared ||
                  payment.currency != effective.currency)
                const ListTile(
                  leading: Icon(Icons.warning_amber_rounded),
                  title: Text('Linked payment needs review'),
                  subtitle: Text(
                    'Its author can unlink and correct the category, currency or sharing. Actual spending keeps the expense’s recorded values.',
                  ),
                ),
              _expenseTile(payment, names),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _archiveRecurring(CloudRecurringTemplate template) async {
    try {
      await widget.services.setRecurringArchived(
        widget.household.id,
        template.id,
        !template.archived,
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editRecurring(CloudRecurringTemplate? existing) async {
    if (latestCategories.isEmpty) {
      _showError('Add a category first.');
      return;
    }
    final availableCategories = [
      ...latestCategories,
      ...allCategories.where(
        (category) => category.archived && category.id == existing?.categoryId,
      ),
    ];
    final name = TextEditingController(text: existing?.name ?? '');
    final amount = TextEditingController(
      text: existing == null
          ? ''
          : (existing.amountCents / 100).toStringAsFixed(2),
    );
    var categoryId = existing?.categoryId ?? latestCategories.first.id;
    var currency = existing?.currency ?? widget.household.currency;
    var dueDay = existing?.dueDay ?? 1;
    var graceDays = existing?.graceDays ?? 0;
    var shared = existing?.isShared ?? true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  existing == null
                      ? 'New recurring expense'
                      : 'Edit recurring expense',
                ),
              ),
              const TutorialHelpButton(topic: TutorialTopic.recurring),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: maxRecurringNameLength,
                    decoration: const InputDecoration(
                      labelText: 'Name, e.g. Rent',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    maxLength: 20,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Expected amount',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: availableCategories
                        .map(
                          (category) => DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        refresh(() => categoryId = value ?? categoryId),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: currency,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: supportedCurrencies
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        refresh(() => currency = value ?? currency),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: dueDay,
                    decoration: const InputDecoration(labelText: 'Due day'),
                    items: [
                      const DropdownMenuItem(
                        value: 0,
                        child: Text('End of month'),
                      ),
                      ...List.generate(
                        28,
                        (index) => DropdownMenuItem(
                          value: index + 1,
                          child: Text('Day ${index + 1}'),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        refresh(() => dueDay = value ?? dueDay),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: graceDays,
                    decoration: const InputDecoration(
                      labelText: 'Grace period',
                    ),
                    items: List.generate(
                      15,
                      (index) => DropdownMenuItem(
                        value: index,
                        child: Text('$index days'),
                      ),
                    ),
                    onChanged: (value) =>
                        refresh(() => graceDays = value ?? graceDays),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Shared expense'),
                    value: shared,
                    onChanged: (value) => refresh(() => shared = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final enteredName = name.text;
    final enteredAmount = amount.text;
    name.dispose();
    amount.dispose();
    if (result == true && mounted) {
      final cents = parseCents(enteredAmount);
      if (enteredName.trim().isEmpty || cents == null || cents <= 0) {
        _showError('Enter a name and positive amount.');
      } else {
        try {
          var updatePayments = false;
          if (existing != null &&
              (existing.categoryId != categoryId ||
                  existing.name != name.text.trim())) {
            final month = recurringMonth(DateTime.now());
            final payments = (await widget.services.recurringPayments(
              widget.household.id,
              month,
            )).where((item) => item.recurringId == existing.id).toList();
            if (!mounted) return;
            if (payments.isNotEmpty) {
              final canUpdate =
                  payments.every(
                    (item) => item.authorId == widget.services.currentUser?.uid,
                  ) &&
                  payments.length <= 450 &&
                  payments.every(
                    (item) =>
                        item.currency == currency && item.isShared == shared,
                  );
              final scope = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Apply this change to…'),
                  content: Text(
                    canUpdate
                        ? 'Only future payments keeps this month’s saved category. Previous months stay unchanged. You can also correct all ${payments.length} linked payments currently shown for this month.'
                        : 'Current-month payments include another member’s expense, different currency or sharing, or too many records. Only future payments can change. Each author can unlink and correct their own expense.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Only future payments'),
                    ),
                    FilledButton(
                      onPressed: canUpdate
                          ? () => Navigator.pop(dialogContext, true)
                          : null,
                      child: const Text(
                        'Also update this month’s linked payments',
                      ),
                    ),
                  ],
                ),
              );
              if (scope == null || !mounted) return;
              updatePayments = scope;
            }
          }
          await widget.services.saveRecurringTemplate(
            widget.household.id,
            id: existing?.id,
            name: name.text,
            categoryId: categoryId,
            amountCents: cents,
            currency: currency,
            dueDay: dueDay,
            graceDays: graceDays,
            shared: shared,
            startMonth: existing?.startMonth ?? recurringMonth(DateTime.now()),
            updateCurrentMonthPayments: updatePayments,
          );
        } catch (error) {
          _showError(error);
        }
      }
    }
  }

  Future<void> _linkExisting(
    CloudRecurringTemplate template,
    List<CloudExpense> items,
  ) async {
    final month = recurringMonth(recurringDate);
    List<CloudExpense> available;
    try {
      available = await widget.services.expensesInMonth(
        widget.household.id,
        recurringDate,
      );
    } catch (error) {
      _showError(error);
      return;
    }
    if (!mounted) return;
    final candidates = available
        .where(
          (expense) =>
              expense.authorId == widget.services.currentUser?.uid &&
              expense.recurringId == null &&
              expense.categoryId == template.categoryId &&
              expense.currency == template.currency &&
              expense.isShared == template.isShared &&
              expense.rateToBaseMicros != null,
        )
        .toList();
    if (candidates.isEmpty) {
      _showError('No matching unlinked expense in this month.');
      return;
    }
    final chosen = await showDialog<CloudExpense>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Link ${template.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: candidates
                .map(
                  (expense) => ListTile(
                    title: Text(
                      expense.description.isEmpty
                          ? 'Expense'
                          : expense.description,
                    ),
                    subtitle: Text(
                      DateFormat.yMMMd().format(expense.expenseDate),
                    ),
                    trailing: Text(
                      money(expense.amountCents, expense.currency),
                    ),
                    onTap: () => Navigator.pop(dialogContext, expense),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      final payments = await widget.services.recurringPayments(
        widget.household.id,
        month,
      );
      if (!mounted) return;
      final confirmed = await confirmRecurringPayment(
        context,
        name: template.name,
        month: month,
        currency: template.currency,
        amountCents: chosen.amountCents,
        summary: summarizeRecurringPayments(
          template,
          payments.where((item) => item.recurringId == template.id),
        ),
      );
      if (!confirmed || !mounted) return;
      await widget.services.updateCloudExpense(
        householdId: widget.household.id,
        expenseId: chosen.id,
        categoryId: chosen.categoryId,
        amountCents: chosen.amountCents,
        currency: chosen.currency,
        rateToBaseMicros: chosen.rateToBaseMicros!,
        description: chosen.description,
        shared: chosen.isShared,
        date: chosen.expenseDate,
        recurring: RecurringLink(template.id, month),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Widget _budgetPlan(
    List<CloudExpense> items,
    AsyncSnapshot<List<CloudBudget>> snapshot,
  ) {
    final totals = calculateCloudTotals(items, DateTime.now());
    if (snapshot.hasError) return _error(snapshot.error!);
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    final limits = {
      for (final budget in snapshot.data!)
        budget.categoryId: budget.amountCents,
    };
    final monthly = limits[''];
    final active = latestCategories;
    final allocated = active.fold<int>(
      0,
      (sum, category) => sum + (limits[category.id] ?? 0),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Text('Monthly plan', style: Theme.of(context).textTheme.titleLarge),
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Total monthly budget'),
            subtitle: Text(
              monthly == null
                  ? 'Not set'
                  : '${money(totals.monthlyCents, widget.household.currency)} spent of ${money(monthly, widget.household.currency)}',
            ),
            trailing: owner ? const Icon(Icons.edit_outlined) : null,
            onTap: owner ? () => _setBudget('', 'Monthly', monthly) : null,
          ),
        ),
        if (monthly != null && allocated > monthly)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              'Category limits exceed the total monthly budget by '
              '${money(allocated - monthly, widget.household.currency)}.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        Text('Category budgets', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          owner
              ? 'Tap a category to set its monthly limit.'
              : 'Monthly limits set by the household owner.',
        ),
        const SizedBox(height: 8),
        for (final category in allCategories)
          Card(
            child: ListTile(
              leading: Icon(_cloudCategoryIcon(category.name)),
              title: Text(category.name),
              subtitle: Text(
                category.archived
                    ? 'Removed from new expenses'
                    : limits[category.id] == null
                    ? 'No budget set'
                    : '${money(totals.byCategory[category.id] ?? 0, widget.household.currency)} spent of '
                          '${money(limits[category.id]!, widget.household.currency)}',
              ),
              trailing: owner
                  ? PopupMenuButton<String>(
                      tooltip: 'Category options',
                      onSelected: (action) {
                        if (action == 'rename') _editCategory(category);
                        if (action == 'archive') _setCategoryArchived(category);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Text(category.archived ? 'Restore' : 'Remove'),
                        ),
                      ],
                    )
                  : null,
              onTap: owner && !category.archived
                  ? () => _setBudget(
                      category.id,
                      category.name,
                      limits[category.id],
                    )
                  : null,
            ),
          ),
        if (owner) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _editCategory(null),
            icon: const Icon(Icons.add),
            label: const Text('Add category'),
          ),
        ],
      ],
    );
  }

  Future<void> _editCategory(CloudCategory? category) async {
    var name = category?.name ?? '';
    final chosen = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(category == null ? 'Add category' : 'Rename category'),
        content: TextFormField(
          initialValue: name,
          maxLength: 40,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name'),
          onChanged: (value) => name = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, name.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen.isEmpty) {
      _showError('Enter a category name.');
      return;
    }
    try {
      if (category == null) {
        await widget.services.createCloudCategory(widget.household.id, chosen);
      } else if (chosen != category.name) {
        await widget.services.renameCloudCategory(
          widget.household.id,
          category.id,
          chosen,
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _setCategoryArchived(CloudCategory category) async {
    if (!category.archived) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remove category?'),
          content: const Text(
            'It will disappear from new expense choices. Existing expenses remain saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await widget.services.setCloudCategoryArchived(
        widget.household.id,
        category.id,
        !category.archived,
      );
    } catch (error) {
      _showError(error);
    }
  }

  Widget _expenseList(
    List<CloudExpense> items,
    Map<String, String> names, {
    required bool hasMore,
  }) {
    final query = search.text.trim().toLowerCase();
    final now = DateTime.now();
    final period = ExpensePeriod(
      mode: expensePeriodMode,
      month: expenseMonth,
      customRange: customExpenseDates,
    );
    final filtered = items.where((item) {
      if (expenseType == 'shared' && !item.isShared) return false;
      if (expenseType == 'personal' && item.isShared) return false;
      if (expenseCategory != null && item.categoryId != expenseCategory) {
        return false;
      }
      if (expenseCurrency != null && item.currency != expenseCurrency) {
        return false;
      }
      if (!period.includes(item.expenseDate, now)) return false;
      return query.isEmpty ||
          '${item.description} ${names[item.categoryId] ?? ''} ${item.currency}'
              .toLowerCase()
              .contains(query);
    }).toList();
    final currencies = items.map((item) => item.currency).toSet().toList()
      ..sort();
    final totalCents = filtered.fold<int>(
      0,
      (sum, item) => sum + (item.baseAmountCents ?? 0),
    );
    final unconverted = filtered
        .where((item) => item.baseAmountCents == null)
        .length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _chooseExpensePeriod,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _expensePeriodTitle(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    _expensePeriodSubtitle(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.expand_more),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => _shiftExpenseMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: _canAdvanceExpenseMonth()
                        ? () => _shiftExpenseMonth(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SearchBar(
            controller: search,
            hintText: 'Search loaded expenses',
            leading: const Icon(Icons.search),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'all', label: Text('All')),
                  ButtonSegment(value: 'shared', label: Text('Shared')),
                  ButtonSegment(value: 'personal', label: Text('Personal')),
                ],
                selected: {expenseType},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => expenseType = value.first),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: expenseCategory,
                hint: const Text('Category'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All categories'),
                  ),
                  ...names.entries.map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => expenseCategory = value),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: expenseCurrency,
                hint: const Text('Currency'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All currencies'),
                  ),
                  ...currencies.map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  ),
                ],
                onChanged: (value) => setState(() => expenseCurrency = value),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LOADED TOTAL IN ${widget.household.currency}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          money(totalCents, widget.household.currency),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  Text('${filtered.length} shown'),
                ],
              ),
            ),
          ),
        ),
        if (unconverted > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '$unconverted expenses without a conversion rate are excluded from the total.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Older expenses are available below. The total and search cover loaded expenses.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: filtered.isEmpty && !hasMore
              ? const Center(child: Text('No matching expenses.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: filtered.length + (hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == filtered.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              setState(() => historyLimit += historyPageSize),
                          icon: const Icon(Icons.expand_more),
                          label: const Text('Load 100 more expenses'),
                        ),
                      );
                    }
                    final item = filtered[index];
                    final previous = index == 0 ? null : filtered[index - 1];
                    final showDay =
                        previous == null ||
                        !DateUtils.isSameDay(
                          item.expenseDate,
                          previous.expenseDate,
                        );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDay)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 4, 5),
                            child: Text(
                              DateFormat(
                                'EEEE, d MMM',
                              ).format(item.expenseDate),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                        _expenseTile(item, names),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _expensePeriodTitle() => switch (expensePeriodMode) {
    ExpensePeriodMode.month => DateFormat('MMMM yyyy').format(expenseMonth),
    ExpensePeriodMode.last30Days => 'Last 30 days',
    ExpensePeriodMode.allTime => 'All time',
    ExpensePeriodMode.custom => 'Custom range',
  };

  String _expensePeriodSubtitle() {
    final range = ExpensePeriod(
      mode: expensePeriodMode,
      month: expenseMonth,
      customRange: customExpenseDates,
    ).range(DateTime.now());
    if (range == null) return 'All recorded expenses';
    return '${DateFormat('d MMM yyyy').format(range.start)} – '
        '${DateFormat('d MMM yyyy').format(range.end)}';
  }

  bool _canAdvanceExpenseMonth() {
    final anchor = expensePeriodMode == ExpensePeriodMode.month
        ? expenseMonth
        : DateTime.now();
    final now = DateTime.now();
    return DateTime(
      anchor.year,
      anchor.month,
    ).isBefore(DateTime(now.year, now.month));
  }

  void _shiftExpenseMonth(int change) {
    final anchor = expensePeriodMode == ExpensePeriodMode.month
        ? expenseMonth
        : DateTime(DateTime.now().year, DateTime.now().month);
    setState(() {
      expensePeriodMode = ExpensePeriodMode.month;
      expenseMonth = DateTime(anchor.year, anchor.month + change);
    });
  }

  Future<void> _chooseExpensePeriod() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose a period',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in [
                    (ExpensePeriodMode.month, 'This month'),
                    (ExpensePeriodMode.month, 'Last month'),
                    (ExpensePeriodMode.last30Days, 'Last 30 days'),
                    (ExpensePeriodMode.allTime, 'All time'),
                  ])
                    ActionChip(
                      label: Text(choice.$2),
                      onPressed: () {
                        final now = DateTime.now();
                        setState(() {
                          expensePeriodMode = choice.$1;
                          if (choice.$1 == ExpensePeriodMode.month) {
                            expenseMonth = DateTime(
                              now.year,
                              now.month + (choice.$2 == 'Last month' ? -1 : 0),
                            );
                          }
                        });
                        Navigator.pop(sheetContext);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range_outlined),
                label: const Text('Choose custom dates'),
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  final selected = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    initialDateRange: customExpenseDates,
                  );
                  if (selected != null && mounted) {
                    setState(() {
                      customExpenseDates = selected;
                      expensePeriodMode = ExpensePeriodMode.custom;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expenseTile(CloudExpense item, Map<String, String> names) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: Row(
        children: [
          CircleAvatar(
            child: Icon(_cloudCategoryIcon(names[item.categoryId] ?? 'Other')),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description.isEmpty
                      ? names[item.categoryId] ?? 'Other'
                      : item.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${names[item.categoryId] ?? 'Other'} · ${item.expenseDate.day}/${item.expenseDate.month}/${item.expenseDate.year}'
                  '${item.baseAmountCents == null ? ' · Conversion needed' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            money(item.amountCents, item.currency),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (deletingExpenseIds.contains(item.id))
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (item.authorId == widget.services.currentUser?.uid)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') _deleteExpense(item);
                if (value == 'edit') _editExpense(item);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _insights(
    List<CloudExpense> items,
    Map<String, String> names,
    AsyncSnapshot<List<CloudBudget>> budgetSnapshot,
  ) {
    final totals = calculateCloudTotals(items, DateTime.now());
    final sorted = totals.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final now = DateTime.now();
    final months = List.generate(
      6,
      (index) => DateTime(now.year, now.month - 5 + index),
    );
    final filtered = insightCategories.isEmpty
        ? items
        : items
              .where((item) => insightCategories.contains(item.categoryId))
              .toList();
    final monthly = months
        .map(
          (month) => filtered
              .where(
                (item) =>
                    item.expenseDate.year == month.year &&
                    item.expenseDate.month == month.month,
              )
              .fold<int>(0, (sum, item) => sum + (item.baseAmountCents ?? 0)),
        )
        .toList();
    final maxMonthly = monthly.fold<int>(
      1,
      (max, value) => value > max ? value : max,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('This month', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Trend categories · select several or clear for all',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('All'),
                selected: insightCategories.isEmpty,
                onSelected: (_) => setState(insightCategories.clear),
              ),
              const SizedBox(width: 6),
              for (final category in latestCategories) ...[
                FilterChip(
                  label: Text(category.name),
                  selected: insightCategories.contains(category.id),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      insightCategories.add(category.id);
                    } else {
                      insightCategories.remove(category.id);
                    }
                  }),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        if (budgetSnapshot.hasData) ...[
          for (final budget in budgetSnapshot.data!)
            if (budget.categoryId.isNotEmpty &&
                budget.amountCents > 0 &&
                (totals.byCategory[budget.categoryId] ?? 0) * 10 >=
                    budget.amountCents * 9)
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    '${names[budget.categoryId] ?? 'Category'} budget '
                    '${(totals.byCategory[budget.categoryId] ?? 0) > budget.amountCents ? 'exceeded' : 'almost reached'}',
                  ),
                  subtitle: Text(
                    '${money(totals.byCategory[budget.categoryId] ?? 0, widget.household.currency)} '
                    'of ${money(budget.amountCents, widget.household.currency)} this month',
                  ),
                ),
              ),
        ],
        StreamBuilder<List<CloudExpense>>(
          stream: insightPayments,
          builder: (context, payments) =>
              StreamBuilder<List<CloudRecurringOccurrence>>(
                stream: insightPeriods,
                builder: (context, periods) {
                  if (payments.hasError || periods.hasError) {
                    return const Card(
                      child: ListTile(
                        title: Text('Recurring status unavailable'),
                      ),
                    );
                  }
                  if (!payments.hasData || !periods.hasData) {
                    return const SizedBox.shrink();
                  }
                  final grouped = groupRecurringPayments(
                    payments.data!,
                    recurringMonth(now),
                  );
                  final plans = {
                    for (final plan in periods.data!) plan.recurringId: plan,
                  };
                  return Column(
                    children: [
                      for (final template in latestRecurring)
                        if (!template.archived &&
                            template.startMonth.compareTo(
                                  recurringMonth(now),
                                ) <=
                                0)
                          _recurringWarning(
                            plans[template.id]?.effectiveTemplate(template) ??
                                template,
                            grouped[template.id] ?? const [],
                            now,
                          ),
                    ],
                  );
                },
              ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total spending'),
                const SizedBox(height: 8),
                Text(
                  money(monthly.last, widget.household.currency),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Six-month trend',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 155,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      6,
                      (index) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: monthly[index] / maxMonthly,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${months[index].month}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Shared spending'),
            trailing: Text(
              money(totals.sharedCents, widget.household.currency),
            ),
          ),
        ),
        StreamBuilder<DateTime>(
          stream: sharedReset,
          builder: (context, snapshot) {
            if (snapshot.hasError) return _error(snapshot.error!);
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final key =
                '${snapshot.data!.toIso8601String()}/'
                '${Object.hashAll(items.map((item) => Object.hash(item.id, item.authorId, item.expenseDate, item.baseAmountCents, item.isShared)))}';
            if (runningSummaryKey != key) {
              runningSummaryKey = key;
              runningSummary = _loadRunningSummary(snapshot.data!);
            }
            return FutureBuilder<(Map<String, int>, List<CloudMember>)>(
              future: runningSummary,
              builder: (context, summary) {
                if (summary.hasError) {
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: const Text('Running totals unavailable'),
                      subtitle: const Text(
                        'Connect to refresh totals across the full household history.',
                      ),
                      trailing: TextButton(
                        onPressed: () =>
                            setState(() => runningSummaryKey = null),
                        child: const Text('Retry'),
                      ),
                    ),
                  );
                }
                if (!summary.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final running = summary.data!.$1[''] ?? 0;
                final monthlyByMember = calculateMemberSharedSpending(
                  items,
                  DateTime.now(),
                  sharedResetAt: snapshot.data,
                );
                final byMember =
                    [
                      for (final member in summary.data!.$2)
                        MapEntry(
                          member.uid,
                          MemberSharedSpending(
                            name: member.displayName,
                            monthlyCents:
                                monthlyByMember[member.uid]?.monthlyCents ?? 0,
                            runningCents: summary.data!.$1[member.uid] ?? 0,
                          ),
                        ),
                    ]..sort(
                      (a, b) =>
                          b.value.monthlyCents.compareTo(a.value.monthlyCents),
                    );
                final formerMembersCents =
                    running -
                    byMember.fold<int>(
                      0,
                      (sum, entry) => sum + entry.value.runningCents,
                    );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: ListTile(
                        title: const Text('Shared since reset'),
                        subtitle: owner ? const Text('Tap to reset') : null,
                        trailing: Text(
                          money(running, widget.household.currency),
                        ),
                        onTap: owner ? _resetSharedTotal : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Shared spending by member',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    const Text('Only shared expenses are included.'),
                    if (byMember.isEmpty)
                      const Card(
                        child: ListTile(title: Text('No shared expenses yet.')),
                      ),
                    for (final entry in byMember)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry.value.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('This month'),
                                  Text(
                                    money(
                                      entry.value.monthlyCents,
                                      widget.household.currency,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Since reset'),
                                  Text(
                                    money(
                                      entry.value.runningCents,
                                      widget.household.currency,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (formerMembersCents > 0)
                      Card(
                        child: ListTile(
                          title: const Text('Former members'),
                          subtitle: const Text(
                            'Shared expenses remain in the household.',
                          ),
                          trailing: Text(
                            money(
                              formerMembersCents,
                              widget.household.currency,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
        const SizedBox(height: 16),
        Text('By category', style: Theme.of(context).textTheme.titleLarge),
        ...sorted.map(
          (entry) => Card(
            child: ListTile(
              leading: Icon(_cloudCategoryIcon(names[entry.key] ?? 'Other')),
              title: Text(names[entry.key] ?? 'Other'),
              trailing: Text(money(entry.value, widget.household.currency)),
            ),
          ),
        ),
        if (totals.unconvertedCount > 0)
          Text(
            '${totals.unconvertedCount} expenses without conversion are excluded.',
          ),
      ],
    );
  }

  Widget _recurringWarning(
    CloudRecurringTemplate template,
    List<CloudExpense> payments,
    DateTime now,
  ) {
    final summary = summarizeRecurringPayments(template, payments);
    final status = recurringStatus(
      paid: summary.settled,
      today: now,
      dueDate: recurringDueDate(now.year, now.month, template.dueDay),
      graceDays: template.graceDays,
    );
    if (status != RecurringStatus.overdue) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event_repeat_outlined),
        title: Text('${template.name} may be overdue'),
        subtitle: Text(
          '${money(summary.remainingCents, template.currency)} remains unpaid${payments.any((item) => item.pendingSync) ? ' · syncing' : ''}.',
        ),
        onTap: () {
          setState(() {
            expensesSection = 2;
            recurringDate = DateTime(now.year, now.month);
          });
          _selectTab(1);
        },
      ),
    );
  }

  Widget _settings() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.home_outlined),
          title: Text(widget.household.name),
          subtitle: Text(
            'Main currency: ${widget.household.currency} · set when the household was created',
          ),
        ),
      ),
      Text(
        'Appearance & security',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      Card(
        child: Column(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.dark_mode_outlined),
              title: const Text('Dark theme'),
              value: darkTheme,
              onChanged: (value) async {
                try {
                  await widget.onThemeChanged(value);
                  if (mounted) setState(() => darkTheme = value);
                } catch (error) {
                  _showError(error);
                }
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Biometric lock on this device'),
              value: biometricLock,
              onChanged: (value) async {
                try {
                  await widget.onBiometricChanged(value);
                  if (mounted) setState(() => biometricLock = value);
                } catch (error) {
                  _showError(error);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: Text(pinEnabled ? 'Change device PIN' : 'Set device PIN'),
              onTap: _setPin,
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text('People & sharing', style: Theme.of(context).textTheme.titleLarge),
      StreamBuilder<List<CloudMember>>(
        stream: widget.services.watchMembers(widget.household.id),
        builder: (context, snapshot) => snapshot.hasError
            ? _error(snapshot.error!)
            : Column(
                children: [
                  ...(snapshot.data ?? []).map(
                    (member) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(member.displayName),
                        subtitle: Text(member.role),
                      ),
                    ),
                  ),
                  if (owner)
                    OutlinedButton.icon(
                      onPressed:
                          (snapshot.data ?? []).any(
                            (member) =>
                                member.uid !=
                                    widget.services.currentUser?.uid &&
                                member.status == 'active',
                          )
                          ? () => _transferHousehold(snapshot.data!)
                          : null,
                      icon: const Icon(Icons.swap_horiz),
                      label: const Text('Transfer household'),
                    ),
                ],
              ),
      ),
      if (owner) ...[
        FilledButton.icon(
          onPressed: _createInvite,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Create invite code'),
        ),
        const SizedBox(height: 12),
        Text('Join requests', style: Theme.of(context).textTheme.titleLarge),
        StreamBuilder<List<CloudJoinRequest>>(
          stream: widget.services.watchJoinRequests(widget.household.id),
          builder: (context, snapshot) => snapshot.hasError
              ? _error(snapshot.error!)
              : Column(
                  children: (snapshot.data ?? [])
                      .map(
                        (request) => Card(
                          child: ListTile(
                            title: Text(request.displayName),
                            trailing: TextButton(
                              onPressed: () async {
                                try {
                                  await widget.services.approveJoinRequest(
                                    householdId: widget.household.id,
                                    request: request,
                                  );
                                } catch (error) {
                                  _showError(error);
                                }
                              },
                              child: const Text('Approve'),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.arrow_back_outlined),
          title: const Text('Return to start screen'),
          subtitle: const Text('Open your household or take the tour.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _returnToStart,
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.exit_to_app),
          title: const Text('Leave household'),
          subtitle: Text(
            owner
                ? 'Transfer ownership to another member first.'
                : 'Your past expenses stay with the household.',
          ),
          onTap: owner ? null : _leaveHousehold,
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.person_remove_outlined),
          title: const Text('Request account deletion'),
          subtitle: const Text(
            'Ask to remove your cloud account and personal data.',
          ),
          onTap: _requestAccountDeletion,
        ),
      ),
      OutlinedButton(
        onPressed: () async {
          await widget.services.signOut();
          if (mounted) _returnToStart();
        },
        child: const Text('Sign out'),
      ),
    ],
  );

  Future<void> _requestAccountDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: Text(
          owner
              ? 'Your request will be saved, but transfer household ownership before your account can be removed. Household expenses shared with other members will remain.'
              : 'Your request will be saved for processing. Shared expenses in the household will remain, without access to your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (await widget.services.hasPendingAccountDeletion()) {
        if (mounted) {
          _showError('An account deletion request is already pending.');
        }
        return;
      }
      await widget.services.requestAccountDeletion(widget.household.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account deletion request saved.')),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _addExpense({
    CloudRecurringTemplate? template,
    String? month,
    int? paymentCents,
  }) async {
    try {
      final available = [
        ...latestCategories,
        ...allCategories.where(
          (category) =>
              category.archived && category.id == template?.categoryId,
        ),
      ];
      if (available.isEmpty) {
        _showError('No categories are available.');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _CloudExpenseForm(
          household: widget.household,
          categories: available,
          services: widget.services,
          recurringTemplates: latestRecurring,
          prefillRecurring: template,
          prefillRecurringMonth: month,
          prefillAmountCents: paymentCents,
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editExpense(CloudExpense expense) async {
    final available = [
      ...latestCategories,
      ...allCategories.where(
        (category) => category.id == expense.categoryId && category.archived,
      ),
    ];
    if (available.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CloudExpenseForm(
        household: widget.household,
        categories: available,
        services: widget.services,
        expense: expense,
        recurringTemplates: latestRecurring,
      ),
    );
  }

  Future<void> _deleteExpense(CloudExpense item) async {
    if (deletingExpenseIds.contains(item.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
          item.recurringId == null
              ? 'Delete this expense? This cannot be undone.'
              : 'Delete this expense and unlink its recurring payment for the month? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => deletingExpenseIds.add(item.id));
    try {
      await widget.services.deleteCloudExpense(widget.household.id, item.id);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          const SnackBar(content: Text('Expense deleted from the household.')),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is FirebaseException
          ? switch (error.code) {
              'permission-denied' =>
                'Deletion was denied. The expense is still saved. Check that you are its author and that the latest household rules are published.',
              'unavailable' || 'deadline-exceeded' =>
                'Connect to the internet and try again. Deletion could not be confirmed.',
              _ =>
                'Deletion could not be confirmed (${error.code}). The expense may still be saved. Please try again.',
            }
          : 'Deletion could not be confirmed: $error';
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Expense was not deleted'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          deletingExpenseIds.remove(item.id);
          runningSummaryKey = null;
        });
      }
    }
  }

  Future<void> _setBudget(
    String categoryId,
    String categoryName,
    int? current,
  ) async {
    final cents = await showBudgetAmountDialog(
      context,
      title: categoryName,
      currency: widget.household.currency,
      current: current,
    );
    if (cents == null || !mounted) {
      return;
    }
    try {
      if (categoryId.isEmpty) {
        await widget.services.setCloudMonthlyBudget(
          widget.household.id,
          widget.household.currency,
          cents,
        );
      } else {
        await widget.services.setCloudBudget(
          widget.household.id,
          categoryId,
          widget.household.currency,
          cents,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$categoryName budget saved.')));
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _createInvite() async {
    try {
      final code = await widget.services.createInvite(widget.household.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invite code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                code,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Single use · expires in 24 hours',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite code copied.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy code'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  widget.onShareStarted?.call();
                  try {
                    await SharePlus.instance.share(
                      ShareParams(
                        text:
                            'Join my Home Budget household with this one-time code: $code\n'
                            'Open Home Budget, choose Join with an invite code, and enter it. '
                            'The code expires in 24 hours.',
                        subject: 'Home Budget household invitation',
                      ),
                    );
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Could not share invite: $error'),
                        ),
                      );
                    }
                  } finally {
                    widget.onShareFinished?.call();
                  }
                },
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share via an app'),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _transferHousehold(List<CloudMember> members) async {
    final eligible = members
        .where(
          (member) =>
              member.uid != widget.services.currentUser?.uid &&
              member.status == 'active',
        )
        .toList();
    final chosen = await showDialog<CloudMember>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose the new owner'),
        children: eligible
            .map(
              (member) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, member),
                child: Text(member.displayName),
              ),
            )
            .toList(),
      ),
    );
    if (chosen == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer household?'),
        content: Text(
          '${chosen.displayName} will become the owner. You will remain a member and can then leave.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.services.transferHousehold(
        householdId: widget.household.id,
        newOwnerId: chosen.uid,
      );
      if (mounted) _returnToStart();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _leaveHousehold() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave household?'),
        content: const Text(
          'You will lose access to this household. Your past expenses remain visible to its members. To return, request a new invite.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.services.leaveHousehold(widget.household.id);
      if (mounted) _returnToStart();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _setPin() async {
    var first = '';
    var second = '';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(pinEnabled ? 'Change device PIN' : 'Set device PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'New PIN (4–8 digits)',
              ),
              onChanged: (value) => first = value,
            ),
            TextFormField(
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
              onChanged: (value) => second = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, first == second ? first : ''),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    if (!RegExp(r'^\d{4,8}$').hasMatch(value)) {
      _showError('PINs must match and contain 4–8 digits.');
      return;
    }
    try {
      await widget.onPinSet(value);
      if (mounted) setState(() => pinEnabled = true);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _resetSharedTotal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset shared total?'),
        content: const Text(
          'Expenses remain saved. Only the running shared total starts again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.services.resetSharedTotal(widget.household.id);
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _CloudExpenseForm extends StatefulWidget {
  const _CloudExpenseForm({
    required this.household,
    required this.categories,
    required this.services,
    required this.recurringTemplates,
    this.expense,
    this.prefillRecurring,
    this.prefillRecurringMonth,
    this.prefillAmountCents,
  });
  final CloudHousehold household;
  final List<CloudCategory> categories;
  final FirebaseServices services;
  final CloudExpense? expense;
  final List<CloudRecurringTemplate> recurringTemplates;
  final CloudRecurringTemplate? prefillRecurring;
  final String? prefillRecurringMonth;
  final int? prefillAmountCents;
  @override
  State<_CloudExpenseForm> createState() => _CloudExpenseFormState();
}

class _CloudExpenseFormState extends State<_CloudExpenseForm> {
  final amount = TextEditingController();
  final rate = TextEditingController();
  final description = TextEditingController();
  late String categoryId;
  late String currency;
  late DateTime date;
  late bool shared;
  String? recurringId;
  String? paymentMonth;
  bool busy = false;
  String? formError;

  @override
  void initState() {
    super.initState();
    final existing = widget.expense;
    categoryId = widget.categories.any((c) => c.id == existing?.categoryId)
        ? existing!.categoryId
        : widget.categories.first.id;
    currency = existing?.currency ?? widget.household.currency;
    date = existing?.expenseDate ?? DateTime.now();
    shared = existing?.isShared ?? false;
    recurringId = existing?.recurringId ?? widget.prefillRecurring?.id;
    paymentMonth = existing?.recurringMonth ?? widget.prefillRecurringMonth;
    if (widget.prefillRecurring case final template?) {
      categoryId = template.categoryId;
      currency = template.currency;
      shared = template.isShared;
      amount.text = ((widget.prefillAmountCents ?? template.amountCents) / 100)
          .toStringAsFixed(2);
      description.text = template.name;
    }
    if (existing != null) {
      amount.text = (existing.amountCents / 100).toStringAsFixed(2);
      description.text = existing.description;
      if (existing.rateToBaseMicros != null &&
          currency != widget.household.currency) {
        rate.text = (existing.rateToBaseMicros! / 1000000).toStringAsFixed(6);
      }
    }
  }

  @override
  void dispose() {
    amount.dispose();
    rate.dispose();
    description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AbsorbPointer(
    absorbing: busy,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.expense == null ? 'New expense' : 'Edit expense',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const TutorialHelpButton(topic: TutorialTopic.payment),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: amount,
              maxLength: 20,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('category-$categoryId'),
              initialValue: categoryId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: widget.categories
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  )
                  .toList(),
              onChanged: recurringId == null
                  ? (value) => setState(() {
                      categoryId = value ?? categoryId;
                      formError = null;
                    })
                  : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('currency-$currency'),
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: supportedCurrencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: recurringId == null
                  ? (value) => setState(() {
                      currency = value ?? currency;
                      rate.clear();
                      formError = null;
                    })
                  : null,
            ),
            if (currency != widget.household.currency) ...[
              const SizedBox(height: 12),
              TextField(
                controller: rate,
                maxLength: 20,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Exchange rate',
                  helperText: '1 $currency = ? ${widget.household.currency}',
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: description,
              maxLength: maxExpenseDescriptionLength,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            if (widget.recurringTemplates.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: recurringId,
                decoration: const InputDecoration(
                  labelText: 'Recurring payment',
                  helperText:
                      'Link this expense to one monthly item, if applicable.',
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('None')),
                  ...widget.recurringTemplates
                      .where(
                        (template) =>
                            !template.archived || template.id == recurringId,
                      )
                      .map(
                        (template) => DropdownMenuItem(
                          value: template.id,
                          child: Text(template.name),
                        ),
                      ),
                ],
                onChanged: (value) => setState(() {
                  recurringId = value == '' ? null : value;
                  formError = null;
                  final match = widget.recurringTemplates.where(
                    (item) => item.id == recurringId,
                  );
                  if (match.isNotEmpty) {
                    categoryId = match.first.categoryId;
                    if (currency != match.first.currency) rate.clear();
                    currency = match.first.currency;
                    shared = match.first.isShared;
                  }
                }),
              ),
              if (recurringId != null)
                Text(
                  'Payment month: '
                  '${paymentMonth ?? recurringMonth(date)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (recurringId != null)
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final value = await showDatePicker(
                            context: context,
                            initialDate: DateTime.parse(
                              '${paymentMonth ?? recurringMonth(date)}-01',
                            ),
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (value != null && mounted) {
                            setState(
                              () => paymentMonth = recurringMonth(value),
                            );
                          }
                        },
                  child: const Text('Change payment month'),
                ),
              if (recurringId != null)
                const Text(
                  'Unlink the recurring payment to change its category, currency or sharing.',
                  style: TextStyle(fontSize: 12),
                ),
            ],
            SwitchListTile(
              title: const Text('Shared expense'),
              value: shared,
              onChanged: recurringId == null
                  ? (value) => setState(() {
                      shared = value;
                      formError = null;
                    })
                  : null,
            ),
            ListTile(
              title: const Text('Date'),
              subtitle: Text('${date.day}/${date.month}/${date.year}'),
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (selected != null && mounted) {
                  setState(() => date = selected);
                }
              },
            ),
            if (formError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  formError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: busy ? null : _save,
              child: Text(
                busy
                    ? 'Saving…'
                    : widget.expense == null
                    ? 'Save expense'
                    : 'Save changes',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _save() async {
    final descriptionError = textInputError(
      description.text,
      label: 'Description',
      maximum: maxExpenseDescriptionLength,
      optional: true,
    );
    if (descriptionError != null) {
      setState(() => formError = descriptionError);
      return;
    }
    final cents = parseCents(amount.text);
    final micros = currency == widget.household.currency
        ? 1000000
        : parseRateMicros(rate.text);
    if (cents == null ||
        cents <= 0 ||
        micros == null ||
        convertCents(cents, micros) <= 0) {
      setState(() => formError = 'Enter a valid amount and exchange rate.');
      return;
    }
    setState(() {
      busy = true;
      formError = null;
    });
    try {
      final month = paymentMonth ?? recurringMonth(date);
      var selectedId = recurringId;
      final periods = await widget.services.recurringPeriods(
        widget.household.id,
        month,
      );
      final plans = {for (final plan in periods) plan.recurringId: plan};
      final effective = widget.recurringTemplates
          .map((item) => plans[item.id]?.effectiveTemplate(item) ?? item)
          .toList();
      if (selectedId == null && widget.expense?.recurringId == null) {
        final candidates = recurringCandidates(
          effective,
          month: month,
          categoryId: categoryId,
          currency: currency,
          shared: shared,
          description: description.text,
        );
        if (candidates.isNotEmpty) {
          if (!mounted) return;
          selectedId = await showDialog<String>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Is this a recurring payment?'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        description.text.trim().isEmpty
                            ? 'These monthly items match the category, currency and sharing. Choose one only if this expense is its payment.'
                            : 'The category, currency, sharing and description match a saved monthly item.',
                      ),
                      for (final candidate in candidates)
                        ListTile(
                          title: Text(candidate.name),
                          subtitle: Text(
                            money(candidate.amountCents, candidate.currency),
                          ),
                          onTap: () =>
                              Navigator.pop(dialogContext, candidate.id),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, ''),
                  child: const Text('Save as ordinary expense'),
                ),
              ],
            ),
          );
          if (selectedId == null) return;
          if (selectedId.isEmpty) selectedId = null;
        }
      }
      final link = selectedId == null ? null : RecurringLink(selectedId, month);
      if (link != null) {
        final template = widget.recurringTemplates.firstWhere(
          (item) => item.id == selectedId,
        );
        final monthly = plans[link.id]?.effectiveTemplate(template) ?? template;
        if (monthly.categoryId != categoryId ||
            monthly.currency != currency ||
            monthly.isShared != shared) {
          throw StateError(
            'This month uses ${monthly.name}, ${monthly.currency} and its original category and sharing. Unlink, or record payment from that month’s recurring card.',
          );
        }
        final payments = await widget.services.recurringPayments(
          widget.household.id,
          month,
        );
        if (!mounted) return;
        final confirmed = await confirmRecurringPayment(
          context,
          name: monthly.name,
          month: month,
          currency: currency,
          amountCents: cents,
          summary: summarizeRecurringPayments(
            monthly,
            payments.where((item) => item.recurringId == selectedId),
            excludeExpenseId: widget.expense?.id,
          ),
        );
        if (!confirmed || !mounted) return;
      }
      if (widget.expense == null) {
        await widget.services.addCloudExpense(
          householdId: widget.household.id,
          categoryId: categoryId,
          amountCents: cents,
          currency: currency,
          rateToBaseMicros: micros,
          description: description.text,
          shared: shared,
          date: date,
          recurring: link,
        );
      } else {
        await widget.services.updateCloudExpense(
          householdId: widget.household.id,
          expenseId: widget.expense!.id,
          categoryId: categoryId,
          amountCents: cents,
          currency: currency,
          rateToBaseMicros: micros,
          description: description.text,
          shared: shared,
          date: date,
          recurring: link,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        busy = false;
        formError = 'Could not save expense: $error';
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _CloudHero extends StatelessWidget {
  const _CloudHero({
    required this.memberName,
    required this.currency,
    required this.spent,
    required this.budget,
    required this.onStart,
  });
  final String memberName, currency;
  final int spent;
  final int? budget;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    return Container(
      constraints: const BoxConstraints(minHeight: 238),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF315943), Color(0xFF234638), Color(0xFF315C59)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -72,
            top: -105,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x24FFFFFF)),
              ),
              child: Center(
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x18FFFFFF)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -10,
            bottom: -45,
            child: Container(
              width: 150,
              height: 110,
              decoration: BoxDecoration(
                color: const Color(0x33F2C187),
                borderRadius: BorderRadius.circular(70),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'YOUR CLOUD HOUSEHOLD',
                        style: TextStyle(
                          color: Color(0xFFDDE9DF),
                          fontSize: 11,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const TutorialHelpButton(
                      topic: TutorialTopic.home,
                      color: Colors.white,
                    ),
                    IconButton(
                      tooltip: 'Return to start screen',
                      onPressed: onStart,
                      icon: CircleAvatar(
                        backgroundColor: const Color(0x33FFFFFF),
                        foregroundColor: Colors.white,
                        child: Text(
                          memberName.trim().isEmpty
                              ? '?'
                              : memberName.trim()[0].toUpperCase(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  '$greeting,',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$memberName.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF3C796),
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  budget == null ? 'SPENT THIS MONTH' : 'SAFE TO SPEND',
                  style: const TextStyle(
                    color: Color(0xFFDDE9DF),
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  money(budget == null ? spent : budget! - spent, currency),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (budget != null)
                  Text(
                    '${money(spent, currency)} spent of ${money(budget!, currency)}',
                    style: const TextStyle(
                      color: Color(0xFFDDE9DF),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudPocket extends StatelessWidget {
  const _CloudPocket({
    required this.category,
    required this.cents,
    required this.budgetCents,
    required this.currency,
    required this.index,
    required this.onTap,
  });
  final String category, currency;
  final int cents, index;
  final int? budgetCents;
  final VoidCallback? onTap;
  static const colors = [
    Color(0xFF5B9C6A),
    Color(0xFFDF815D),
    Color(0xFF7888C1),
    Color(0xFFD0A947),
  ];

  @override
  Widget build(BuildContext context) {
    final color = colors[index % colors.length];
    final progress = budgetCents == null || budgetCents == 0
        ? 0.0
        : (cents / budgetCents!).clamp(0.0, 1.0);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _cloudCategoryIcon(category),
                  color: color,
                  size: 21,
                ),
              ),
              const Spacer(),
              Text(
                category,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                money(
                  budgetCents == null ? cents : budgetCents! - cents,
                  currency,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 5),
              LinearProgressIndicator(
                value: progress,
                color: color,
                backgroundColor: color.withValues(alpha: .14),
              ),
              const SizedBox(height: 4),
              Text(
                budgetCents == null
                    ? (onTap == null ? 'No budget set' : 'Tap to set a budget')
                    : '${money(cents, currency)} spent',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _cloudCategoryIcon(String category) =>
    switch (category.toLowerCase()) {
      'home' => Icons.home_outlined,
      'groceries' => Icons.shopping_basket_outlined,
      'dining' => Icons.restaurant_outlined,
      'transport' => Icons.directions_car_outlined,
      'health' => Icons.health_and_safety_outlined,
      'leisure' => Icons.movie_outlined,
      'gifts' => Icons.card_giftcard_outlined,
      _ => Icons.wallet_outlined,
    };

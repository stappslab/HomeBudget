import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/cloud_totals.dart';
import '../data/firebase_services.dart';
import '../utils/money.dart';
import 'budget_amount_dialog.dart';

class CloudHouseholdPage extends StatefulWidget {
  const CloudHouseholdPage({super.key, required this.services, required this.household,
    required this.darkTheme, required this.biometricLock,
    required this.pinEnabled, required this.onThemeChanged,
    required this.onBiometricChanged, required this.onPinSet,
    this.onShareStarted, this.onShareFinished});
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
  late final Stream<List<CloudExpense>> expenses = widget.services.watchExpenses(widget.household.id);
  late final Stream<List<CloudCategory>> categories = widget.services.watchCategories(widget.household.id);
  late final Stream<List<CloudBudget>> budgets = widget.services.watchBudgets(widget.household.id);
  List<CloudCategory> latestCategories = const [];
  List<CloudCategory> allCategories = const [];
  late bool darkTheme = widget.darkTheme;
  late bool biometricLock = widget.biometricLock;
  late bool pinEnabled = widget.pinEnabled;
  int tab = 0;
  final tabHistory = <int>[];
  bool closing = false;
  final search = TextEditingController();
  String expenseType = 'all';
  String? expenseCategory;
  String? expenseCurrency;
  DateTimeRange? expenseDates;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  bool get owner => widget.household.ownerId == widget.services.currentUser?.uid;

  void _selectTab(int value) {
    if (value == tab) return;
    setState(() {
      tabHistory.add(tab);
      tab = value;
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
    appBar: tab == 0 ? null : AppBar(title: Text(switch (tab) {
      1 => 'Expenses', 2 => 'Insights', _ => 'Settings',
    }), leading: IconButton(icon: const Icon(Icons.arrow_back),
      tooltip: 'Previous screen', onPressed: _goBackTab)),
    body: StreamBuilder<List<CloudCategory>>(
      stream: categories,
      builder: (context, categorySnapshot) {
        if (categorySnapshot.hasError) return _error(categorySnapshot.error!);
        if (!categorySnapshot.hasData) return const Center(child: CircularProgressIndicator());
        allCategories = categorySnapshot.data!;
        latestCategories = allCategories.where((category) => !category.archived).toList();
        return StreamBuilder<List<CloudExpense>>(
          stream: expenses,
          builder: (context, expenseSnapshot) {
            if (tab == 3) return _settings();
            if (expenseSnapshot.hasError) return _error(expenseSnapshot.error!);
            if (!expenseSnapshot.hasData) return const Center(child: CircularProgressIndicator());
            final items = expenseSnapshot.data!;
            final names = {for (final c in categorySnapshot.data!) c.id: c.name};
            return switch (tab) {
              0 => _overview(items, names),
              1 => _expenseList(items, names),
              _ => _insights(items, names),
            };
          },
        );
      },
    ),
    floatingActionButton: tab < 2 ? FloatingActionButton.extended(
      onPressed: _addExpense, icon: const Icon(Icons.add), label: const Text('Add expense')) : null,
    bottomNavigationBar: NavigationBar(selectedIndex: tab,
      onDestinationSelected: _selectTab,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Expenses'),
        NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Insights'),
        NavigationDestination(icon: Icon(Icons.tune_outlined), label: 'Settings'),
      ]),
    ),
  );

  Widget _error(Object error) => Center(child: Padding(padding: const EdgeInsets.all(24),
    child: Text('Cloud data could not load. Check your connection and access.\n$error',
      textAlign: TextAlign.center)));

  Widget _overview(List<CloudExpense> items, Map<String, String> names) {
    final totals = calculateCloudTotals(items, DateTime.now());
    return StreamBuilder<List<CloudBudget>>(stream: budgets, builder: (context, snapshot) {
    if (snapshot.hasError) return _error(snapshot.error!);
    final limits = {for (final budget in snapshot.data ?? <CloudBudget>[])
      budget.categoryId: budget.amountCents};
    final monthly = limits[''];
    return ListView(padding: EdgeInsets.zero, children: [
      _CloudHero(memberName: widget.household.memberName,
        currency: widget.household.currency, spent: totals.monthlyCents,
        budget: monthly, onStart: _returnToStart),
      Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (totals.unconvertedCount > 0) Card(child: ListTile(
        leading: const Icon(Icons.currency_exchange),
        title: Text('${totals.unconvertedCount} migrated expenses need a conversion rate'),
        subtitle: const Text('They are excluded from totals.'),
      )),
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text('Your spending pockets', style: Theme.of(context).textTheme.titleLarge)),
      if (owner) Align(alignment: Alignment.centerRight,
        child: TextButton.icon(onPressed: () => _selectTab(3),
          icon: const Icon(Icons.tune_outlined),
          label: const Text('Set budgets for all categories'))),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(child: ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('Monthly budget'),
            subtitle: Text(monthly == null ? 'Not set' :
              '${money(totals.monthlyCents, widget.household.currency)} of ${money(monthly, widget.household.currency)} spent'),
            trailing: owner ? const Icon(Icons.edit_outlined) : null,
            onTap: owner ? () => _setBudget('', 'Monthly', monthly) : null,
          )),
          GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: names.length > 4 ? 4 : names.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
              mainAxisExtent: 164),
            itemBuilder: (context, index) {
              final entry = names.entries.elementAt(index);
              return _CloudPocket(category: entry.value,
                cents: totals.byCategory[entry.key] ?? 0,
                budgetCents: limits[entry.key], currency: widget.household.currency,
                index: index, onTap: owner ? () => _setBudget(entry.key, entry.value, limits[entry.key]) : null);
            }),
        ]),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: _addExpense, icon: const Icon(Icons.add),
        label: const Text('Add expense')),
      const SizedBox(height: 12),
      Text('Recent activity', style: Theme.of(context).textTheme.titleLarge),
      if (items.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18),
        child: Text('No expenses yet.'))),
      ...items.take(5).map((item) => _expenseTile(item, names)),
      ])),
    ]);
    });
  }

  Widget _expenseList(List<CloudExpense> items, Map<String, String> names) {
    final query = search.text.trim().toLowerCase();
    final filtered = items.where((item) {
      if (expenseType == 'shared' && !item.isShared) return false;
      if (expenseType == 'personal' && item.isShared) return false;
      if (expenseCategory != null && item.categoryId != expenseCategory) return false;
      if (expenseCurrency != null && item.currency != expenseCurrency) return false;
      if (expenseDates != null && (DateUtils.dateOnly(item.expenseDate)
          .isBefore(DateUtils.dateOnly(expenseDates!.start)) ||
          DateUtils.dateOnly(item.expenseDate)
          .isAfter(DateUtils.dateOnly(expenseDates!.end)))) {
        return false;
      }
      return query.isEmpty || '${item.description} ${names[item.categoryId] ?? ''} ${item.currency}'
        .toLowerCase().contains(query);
    }).toList();
    final currencies = items.map((item) => item.currency).toSet().toList()..sort();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: SearchBar(
        controller: search, hintText: 'Search expenses',
        leading: const Icon(Icons.search), onChanged: (_) => setState(() {}))),
      SingleChildScrollView(scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'all', label: Text('All')),
            ButtonSegment(value: 'shared', label: Text('Shared')),
            ButtonSegment(value: 'personal', label: Text('Personal'))],
          selected: {expenseType}, showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => expenseType = value.first)),
          const SizedBox(width: 10),
          DropdownButton<String>(value: expenseCategory,
            hint: const Text('Category'), items: [
              const DropdownMenuItem(value: null, child: Text('All categories')),
              ...names.entries.map((entry) => DropdownMenuItem(
                value: entry.key, child: Text(entry.value))),
            ], onChanged: (value) => setState(() => expenseCategory = value)),
          const SizedBox(width: 10),
          DropdownButton<String>(value: expenseCurrency,
            hint: const Text('Currency'), items: [
              const DropdownMenuItem(value: null, child: Text('All currencies')),
              ...currencies.map((value) => DropdownMenuItem(
                value: value, child: Text(value))),
            ], onChanged: (value) => setState(() => expenseCurrency = value)),
          TextButton.icon(icon: const Icon(Icons.date_range_outlined),
            label: Text(expenseDates == null ? 'Date' :
              '${expenseDates!.start.day}/${expenseDates!.start.month}–${expenseDates!.end.day}/${expenseDates!.end.month}'),
            onPressed: () async {
              final selected = await showDateRangePicker(context: context,
                firstDate: DateTime(2000), lastDate: DateTime.now(),
                initialDateRange: expenseDates);
              if (selected != null && mounted) setState(() => expenseDates = selected);
            }),
          if (expenseDates != null) IconButton(onPressed: () =>
            setState(() => expenseDates = null), icon: const Icon(Icons.close)),
        ])),
      Expanded(child: filtered.isEmpty ? const Center(child: Text('No matching expenses.')) :
        ListView.builder(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: filtered.length,
          itemBuilder: (context, index) => _expenseTile(filtered[index], names))),
    ]);
  }

  Widget _expenseTile(CloudExpense item, Map<String, String> names) => Card(
    child: Padding(padding: const EdgeInsets.fromLTRB(12, 12, 4, 12), child: Row(children: [
      CircleAvatar(child: Icon(_cloudCategoryIcon(names[item.categoryId] ?? 'Other'))),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.description.isEmpty ? names[item.categoryId] ?? 'Other' : item.description,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${names[item.categoryId] ?? 'Other'} · ${item.expenseDate.day}/${item.expenseDate.month}/${item.expenseDate.year}'
          '${item.baseAmountCents == null ? ' · Conversion needed' : ''}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall),
      ])),
      const SizedBox(width: 6),
      Text(money(item.amountCents, item.currency),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      if (item.authorId == widget.services.currentUser?.uid)
        PopupMenuButton<String>(onSelected: (value) {
          if (value == 'delete') _deleteExpense(item);
          if (value == 'edit') _editExpense(item);
        }, itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ]),
    ])));

  Widget _insights(List<CloudExpense> items, Map<String, String> names) {
    final totals = calculateCloudTotals(items, DateTime.now());
    final sorted = totals.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final now = DateTime.now();
    final months = List.generate(6, (index) => DateTime(now.year, now.month - 5 + index));
    final monthly = months.map((month) => items.where((item) =>
      item.expenseDate.year == month.year && item.expenseDate.month == month.month)
      .fold<int>(0, (sum, item) => sum + (item.baseAmountCents ?? 0))).toList();
    final maxMonthly = monthly.fold<int>(1, (max, value) => value > max ? value : max);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('This month', style: Theme.of(context).textTheme.headlineMedium),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total spending'),
          const SizedBox(height: 8),
          Text(money(totals.monthlyCents, widget.household.currency),
            style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          const Text('Six-month trend', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          SizedBox(height: 155, child: Row(crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(6, (index) => Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Expanded(child: Align(alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(heightFactor: monthly[index] / maxMonthly,
                    child: Container(decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(7)))))),
                const SizedBox(height: 6),
                Text('${months[index].month}', style: Theme.of(context).textTheme.labelSmall),
              ])))),
          )),
        ]))),
      Card(child: ListTile(title: const Text('Shared spending'),
        trailing: Text(money(totals.sharedCents, widget.household.currency)))),
      StreamBuilder<DateTime>(stream: widget.services.watchSharedResetAt(widget.household.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _error(snapshot.error!);
          final running = calculateCloudTotals(items, DateTime.now(),
            sharedResetAt: snapshot.data).runningSharedCents;
          return Card(child: ListTile(
            title: const Text('Shared since reset'),
            subtitle: owner ? const Text('Tap to reset') : null,
            trailing: Text(money(running, widget.household.currency)),
            onTap: owner ? _resetSharedTotal : null,
          ));
        }),
      const SizedBox(height: 16),
      Text('By category', style: Theme.of(context).textTheme.titleLarge),
      ...sorted.map((entry) => Card(child: ListTile(
        leading: Icon(_cloudCategoryIcon(names[entry.key] ?? 'Other')),
        title: Text(names[entry.key] ?? 'Other'),
        trailing: Text(money(entry.value, widget.household.currency))))),
      if (totals.unconvertedCount > 0) Text(
        '${totals.unconvertedCount} unconverted migrated expenses are excluded.'),
    ]);
  }

  Widget _settings() => ListView(padding: const EdgeInsets.all(16), children: [
    Card(child: ListTile(leading: const Icon(Icons.home_outlined),
      title: Text(widget.household.name),
      subtitle: Text('Main currency: ${widget.household.currency} · set when the household was created'))),
    if (owner) Text('Category budgets', style: Theme.of(context).textTheme.titleLarge),
    if (owner) const Padding(padding: EdgeInsets.only(bottom: 8),
      child: Text('Tap any category to set or change its monthly limit.')),
    if (owner) StreamBuilder<List<CloudBudget>>(stream: budgets, builder: (context, snapshot) {
      final limits = {for (final budget in snapshot.data ?? <CloudBudget>[])
        budget.categoryId: budget.amountCents};
      return Card(child: Column(children: [
        ListTile(leading: const Icon(Icons.savings_outlined),
          title: const Text('Monthly budget'),
          subtitle: Text(limits[''] == null ? 'Not set' :
            money(limits['']!, widget.household.currency)),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _setBudget('', 'Monthly', limits[''])),
        StreamBuilder<List<CloudCategory>>(stream: categories, builder: (context, categorySnapshot) =>
          Column(children: [for (final category in categorySnapshot.data ?? <CloudCategory>[])
            ListTile(leading: Icon(_cloudCategoryIcon(category.name)),
              title: Text(category.name),
              subtitle: Text(limits[category.id] == null ? 'No pocket budget' :
                money(limits[category.id]!, widget.household.currency)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _setBudget(category.id, category.name, limits[category.id]))])),
      ]));
    }),
    const SizedBox(height: 16),
    Text('Appearance & security', style: Theme.of(context).textTheme.titleLarge),
    Card(child: Column(children: [
      SwitchListTile(secondary: const Icon(Icons.dark_mode_outlined),
        title: const Text('Dark theme'), value: darkTheme,
        onChanged: (value) async {
          try {
            await widget.onThemeChanged(value);
            if (mounted) setState(() => darkTheme = value);
          } catch (error) { _showError(error); }
        }),
      SwitchListTile(secondary: const Icon(Icons.fingerprint),
        title: const Text('Biometric lock on this device'), value: biometricLock,
        onChanged: (value) async {
          try {
            await widget.onBiometricChanged(value);
            if (mounted) setState(() => biometricLock = value);
          } catch (error) { _showError(error); }
        }),
      ListTile(leading: const Icon(Icons.pin_outlined),
        title: Text(pinEnabled ? 'Change device PIN' : 'Set device PIN'),
        onTap: _setPin),
    ])),
    const SizedBox(height: 16),
    Card(child: ListTile(leading: const Icon(Icons.category_outlined),
      title: const Text('Expense categories'),
      subtitle: Text(owner ? 'Add, rename or remove categories' : 'View household categories'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
        _CategoryManagerPage(services: widget.services,
          householdId: widget.household.id, owner: owner))),
    )),
    const SizedBox(height: 16),
    Text('People & sharing', style: Theme.of(context).textTheme.titleLarge),
    StreamBuilder<List<CloudMember>>(stream: widget.services.watchMembers(widget.household.id),
      builder: (context, snapshot) => snapshot.hasError ? _error(snapshot.error!) :
        Column(children: [
          ...(snapshot.data ?? []).map((member) => Card(child: ListTile(
            leading: const Icon(Icons.person_outline), title: Text(member.displayName),
            subtitle: Text(member.role)))),
          if (owner) OutlinedButton.icon(
            onPressed: (snapshot.data ?? []).any((member) =>
                member.uid != widget.services.currentUser?.uid && member.status == 'active')
              ? () => _transferHousehold(snapshot.data!) : null,
            icon: const Icon(Icons.swap_horiz), label: const Text('Transfer household'),
          ),
        ])),
    if (owner) ...[
      FilledButton.icon(onPressed: _createInvite,
        icon: const Icon(Icons.person_add_alt_1), label: const Text('Create invite code')),
      const SizedBox(height: 12),
      Text('Join requests', style: Theme.of(context).textTheme.titleLarge),
      StreamBuilder<List<CloudJoinRequest>>(
        stream: widget.services.watchJoinRequests(widget.household.id),
        builder: (context, snapshot) => snapshot.hasError ? _error(snapshot.error!) :
          Column(children: (snapshot.data ?? []).map((request) => Card(child: ListTile(
            title: Text(request.displayName),
            trailing: TextButton(onPressed: () async {
              try {
                await widget.services.approveJoinRequest(
                  householdId: widget.household.id, request: request);
              } catch (error) { _showError(error); }
            }, child: const Text('Approve'))))).toList()),
      ),
    ],
    const SizedBox(height: 16),
    Card(child: ListTile(
      leading: const Icon(Icons.arrow_back_outlined),
      title: const Text('Return to start screen'),
      subtitle: const Text('Choose an account or open the tutorial.'),
      trailing: const Icon(Icons.chevron_right),
      onTap: _returnToStart,
    )),
    Card(child: ListTile(
      leading: const Icon(Icons.exit_to_app),
      title: const Text('Leave household'),
      subtitle: Text(owner
        ? 'Transfer ownership to another member first.'
        : 'Your past expenses stay with the household.'),
      onTap: owner ? null : _leaveHousehold,
    )),
    OutlinedButton(onPressed: () async {
      await widget.services.signOut();
      if (mounted) _returnToStart();
    }, child: const Text('Sign out')),
  ]);

  Future<void> _addExpense() async {
    try {
      final available = latestCategories;
      if (available.isEmpty) { _showError('No categories are available.'); return; }
      await showModalBottomSheet<void>(context: context, isScrollControlled: true,
        showDragHandle: true, builder: (_) => _CloudExpenseForm(
          household: widget.household, categories: available, services: widget.services));
    } catch (error) { _showError(error); }
  }

  Future<void> _editExpense(CloudExpense expense) async {
    final available = [
      ...latestCategories,
      ...allCategories.where((category) =>
        category.id == expense.categoryId && category.archived),
    ];
    if (available.isEmpty) return;
    await showModalBottomSheet<void>(context: context, isScrollControlled: true,
      showDragHandle: true, builder: (_) => _CloudExpenseForm(
        household: widget.household, categories: available,
        services: widget.services, expense: expense));
  }

  Future<void> _deleteExpense(CloudExpense item) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Delete expense?'), content: const Text('This cannot be undone.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (confirmed != true) return;
    try { await widget.services.deleteCloudExpense(widget.household.id, item.id); }
    catch (error) { _showError(error); }
  }

  Future<void> _setBudget(String categoryId, String categoryName, int? current) async {
    final cents = await showBudgetAmountDialog(context,
      title: categoryName, currency: widget.household.currency,
      current: current);
    if (cents == null || cents < 0) {
      if (mounted && cents != null) _showError('Enter a valid budget amount.');
      return;
    }
    try {
      if (categoryId.isEmpty) {
        await widget.services.setCloudMonthlyBudget(widget.household.id, widget.household.currency, cents);
      } else {
        await widget.services.setCloudBudget(widget.household.id, categoryId, widget.household.currency, cents);
      }
    }
    catch (error) { _showError(error); }
  }

  Future<void> _createInvite() async {
    try {
      final code = await widget.services.createInvite(widget.household.id);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Invite code'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SelectableText(code, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Single use · expires in 24 hours', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invite code copied.')));
              }
            }, icon: const Icon(Icons.copy_outlined), label: const Text('Copy code')),
            const SizedBox(height: 8),
            FilledButton.icon(onPressed: () async {
              widget.onShareStarted?.call();
              try {
                await SharePlus.instance.share(ShareParams(
                  text: 'Join my HomeBudget household with this one-time code: $code\n'
                    'Open HomeBudget, choose Join with an invite code, and enter it. '
                    'The code expires in 24 hours.',
                  subject: 'HomeBudget household invitation',
                ));
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not share invite: $error')));
                }
              } finally {
                widget.onShareFinished?.call();
              }
            }, icon: const Icon(Icons.share_outlined),
              label: const Text('Share via an app')),
          ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))]));
    } catch (error) { _showError(error); }
  }

  Future<void> _transferHousehold(List<CloudMember> members) async {
    final eligible = members.where((member) =>
      member.uid != widget.services.currentUser?.uid && member.status == 'active').toList();
    final chosen = await showDialog<CloudMember>(context: context,
      builder: (context) => SimpleDialog(title: const Text('Choose the new owner'),
        children: eligible.map((member) => SimpleDialogOption(
          onPressed: () => Navigator.pop(context, member),
          child: Text(member.displayName))).toList()));
    if (chosen == null || !mounted) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Transfer household?'),
      content: Text('${chosen.displayName} will become the owner. You will remain a member and can then leave.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Transfer'))]));
    if (confirmed != true) return;
    try {
      await widget.services.transferHousehold(
        householdId: widget.household.id, newOwnerId: chosen.uid);
      if (mounted) _returnToStart();
    } catch (error) { _showError(error); }
  }

  Future<void> _leaveHousehold() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Leave household?'),
      content: const Text('You will lose access to this household. Your past expenses remain visible to its members. To return, request a new invite.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Leave'))]));
    if (confirmed != true) return;
    try {
      await widget.services.leaveHousehold(widget.household.id);
      if (mounted) _returnToStart();
    } catch (error) { _showError(error); }
  }

  Future<void> _setPin() async {
    var first = '';
    var second = '';
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(pinEnabled ? 'Change device PIN' : 'Set device PIN'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(obscureText: true, keyboardType: TextInputType.number,
          maxLength: 8, decoration: const InputDecoration(labelText: 'New PIN (4–8 digits)'),
          onChanged: (value) => first = value),
        TextFormField(obscureText: true, keyboardType: TextInputType.number,
          maxLength: 8, decoration: const InputDecoration(labelText: 'Confirm PIN'),
          onChanged: (value) => second = value),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context,
          first == second ? first : ''), child: const Text('Save'))],
    ));
    if (value == null) return;
    if (!RegExp(r'^\d{4,8}$').hasMatch(value)) {
      _showError('PINs must match and contain 4–8 digits.');
      return;
    }
    try {
      await widget.onPinSet(value);
      if (mounted) setState(() => pinEnabled = true);
    } catch (error) { _showError(error); }
  }

  Future<void> _resetSharedTotal() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Reset shared total?'),
      content: const Text('Expenses remain saved. Only the running shared total starts again.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset'))]));
    if (confirmed != true) return;
    try { await widget.services.resetSharedTotal(widget.household.id); }
    catch (error) { _showError(error); }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _CloudExpenseForm extends StatefulWidget {
  const _CloudExpenseForm({required this.household, required this.categories,
    required this.services, this.expense});
  final CloudHousehold household;
  final List<CloudCategory> categories;
  final FirebaseServices services;
  final CloudExpense? expense;
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
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.expense;
    categoryId = widget.categories.any((c) => c.id == existing?.categoryId)
      ? existing!.categoryId : widget.categories.first.id;
    currency = existing?.currency ?? widget.household.currency;
    date = existing?.expenseDate ?? DateTime.now();
    shared = existing?.isShared ?? false;
    if (existing != null) {
      amount.text = (existing.amountCents / 100).toStringAsFixed(2);
      description.text = existing.description;
      if (existing.rateToBaseMicros != null && currency != widget.household.currency) {
        rate.text = (existing.rateToBaseMicros! / 1000000).toStringAsFixed(6);
      }
    }
  }

  @override
  void dispose() { amount.dispose(); rate.dispose(); description.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
    child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.expense == null ? 'New cloud expense' : 'Edit cloud expense',
        style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Amount')),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: categoryId,
        decoration: const InputDecoration(labelText: 'Category'),
        items: widget.categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
        onChanged: (value) => setState(() => categoryId = value ?? categoryId)),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(initialValue: currency,
        decoration: const InputDecoration(labelText: 'Currency'),
        items: supportedCurrencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
        onChanged: (value) => setState(() { currency = value ?? currency; rate.clear(); })),
      if (currency != widget.household.currency) ...[
        const SizedBox(height: 12),
        TextField(controller: rate, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Exchange rate',
            helperText: '1 $currency = ? ${widget.household.currency}')),
      ],
      const SizedBox(height: 12),
      TextField(controller: description, decoration: const InputDecoration(labelText: 'Description (optional)')),
      SwitchListTile(title: const Text('Shared expense'), value: shared,
        onChanged: (value) => setState(() => shared = value)),
      ListTile(title: const Text('Date'), subtitle: Text('${date.day}/${date.month}/${date.year}'),
        onTap: () async {
          final selected = await showDatePicker(context: context, initialDate: date,
            firstDate: DateTime(2000), lastDate: DateTime.now());
          if (selected != null && mounted) setState(() => date = selected);
        }),
      FilledButton(onPressed: busy ? null : _save,
        child: Text(busy ? 'Saving…' : widget.expense == null ? 'Save expense' : 'Save changes')),
    ])),
  );

  Future<void> _save() async {
    final cents = parseCents(amount.text);
    final micros = currency == widget.household.currency ? 1000000 : parseRateMicros(rate.text);
    if (cents == null || cents <= 0 || micros == null || convertCents(cents, micros) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount and exchange rate.')));
      return;
    }
    setState(() => busy = true);
    try {
      if (widget.expense == null) {
        await widget.services.addCloudExpense(householdId: widget.household.id,
          categoryId: categoryId, amountCents: cents, currency: currency,
          rateToBaseMicros: micros, description: description.text, shared: shared, date: date);
      } else {
        await widget.services.updateCloudExpense(householdId: widget.household.id,
          expenseId: widget.expense!.id, categoryId: categoryId, amountCents: cents,
          currency: currency, rateToBaseMicros: micros,
          description: description.text, shared: shared, date: date);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save expense: $error')));
    }
  }
}

class _CloudHero extends StatelessWidget {
  const _CloudHero({required this.memberName, required this.currency,
    required this.spent, required this.budget, required this.onStart});
  final String memberName, currency;
  final int spent;
  final int? budget;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12 ? 'Good morning' :
      now.hour < 18 ? 'Good afternoon' : 'Good evening';
    return Container(
      constraints: const BoxConstraints(minHeight: 238),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF315943), Color(0xFF234638), Color(0xFF315C59)]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: Stack(children: [
        Positioned(right: -72, top: -105, child: Container(width: 250, height: 250,
          decoration: BoxDecoration(shape: BoxShape.circle,
            border: Border.all(color: const Color(0x24FFFFFF))),
          child: Center(child: Container(width: 190, height: 190,
            decoration: BoxDecoration(shape: BoxShape.circle,
              border: Border.all(color: const Color(0x18FFFFFF))))))),
        Positioned(right: -10, bottom: -45, child: Container(width: 150, height: 110,
          decoration: BoxDecoration(color: const Color(0x33F2C187),
            borderRadius: BorderRadius.circular(70)))),
        Padding(padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('YOUR CLOUD HOUSEHOLD', style: TextStyle(
                color: Color(0xFFDDE9DF), fontSize: 11, letterSpacing: 1.1)),
              IconButton(tooltip: 'Return to start screen', onPressed: onStart,
                icon: CircleAvatar(backgroundColor: const Color(0x33FFFFFF),
                  foregroundColor: Colors.white,
                  child: Text(memberName.trim().isEmpty ? '?' :
                    memberName.trim()[0].toUpperCase()))),
            ]),
            const SizedBox(height: 20),
            Text('$greeting,', style: const TextStyle(color: Colors.white,
              fontSize: 27, fontWeight: FontWeight.w700)),
            Text('$memberName.', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFF3C796),
                fontSize: 27, fontWeight: FontWeight.w700)),
            const SizedBox(height: 22),
            Text(budget == null ? 'SPENT THIS MONTH' : 'SAFE TO SPEND',
              style: const TextStyle(color: Color(0xFFDDE9DF),
                fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Text(money(budget == null ? spent : budget! - spent, currency),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 25,
                fontWeight: FontWeight.w800)),
            if (budget != null) Text(
              '${money(spent, currency)} spent of ${money(budget!, currency)}',
              style: const TextStyle(color: Color(0xFFDDE9DF), fontSize: 11)),
          ])),
      ]),
    );
  }
}

class _CloudPocket extends StatelessWidget {
  const _CloudPocket({required this.category, required this.cents,
    required this.budgetCents, required this.currency, required this.index,
    required this.onTap});
  final String category, currency;
  final int cents, index;
  final int? budgetCents;
  final VoidCallback? onTap;
  static const colors = [Color(0xFF5B9C6A), Color(0xFFDF815D),
    Color(0xFF7888C1), Color(0xFFD0A947)];

  @override
  Widget build(BuildContext context) {
    final color = colors[index % colors.length];
    final progress = budgetCents == null || budgetCents == 0 ? 0.0 :
      (cents / budgetCents!).clamp(0.0, 1.0);
    return Card(child: InkWell(borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(14), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 38, height: 38,
            decoration: BoxDecoration(color: color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(12)),
            child: Icon(_cloudCategoryIcon(category), color: color, size: 21)),
          const Spacer(),
          Text(category, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(money(budgetCents == null ? cents : budgetCents! - cents, currency),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 5),
          LinearProgressIndicator(value: progress, color: color,
            backgroundColor: color.withValues(alpha: .14)),
          const SizedBox(height: 4),
          Text(budgetCents == null ? (onTap == null ? 'No budget set' : 'Tap to set a budget') :
            '${money(cents, currency)} spent',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall),
        ]))),
    );
  }
}

IconData _cloudCategoryIcon(String category) => switch (category.toLowerCase()) {
  'home' => Icons.home_outlined,
  'groceries' => Icons.shopping_basket_outlined,
  'dining' => Icons.restaurant_outlined,
  'transport' => Icons.directions_car_outlined,
  'health' => Icons.health_and_safety_outlined,
  'leisure' => Icons.movie_outlined,
  'gifts' => Icons.card_giftcard_outlined,
  _ => Icons.wallet_outlined,
};

class _CategoryManagerPage extends StatelessWidget {
  const _CategoryManagerPage({required this.services, required this.householdId,
    required this.owner});
  final FirebaseServices services;
  final String householdId;
  final bool owner;

  Future<String?> _askName(BuildContext context, {String? current}) async {
    var value = current ?? '';
    return showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text(current == null ? 'New category' : 'Rename category'),
      content: TextFormField(initialValue: value, maxLength: 40,
        textCapitalization: TextCapitalization.words,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Category name'),
        onChanged: (text) => value = text),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, value.trim()),
          child: const Text('Save')),
      ],
    ));
  }

  Future<void> _create(BuildContext context) async {
    final name = await _askName(context);
    if (name == null || name.isEmpty) return;
    try {
      await services.createCloudCategory(householdId, name);
    } catch (error) {
      if (context.mounted) _showCategoryError(context, error);
    }
  }

  Future<void> _rename(BuildContext context, CloudCategory category) async {
    final name = await _askName(context, current: category.name);
    if (name == null || name.isEmpty || name == category.name) return;
    try {
      await services.renameCloudCategory(householdId, category.id, name);
    } catch (error) {
      if (context.mounted) _showCategoryError(context, error);
    }
  }

  Future<void> _setArchived(BuildContext context, CloudCategory category) async {
    if (!category.archived) {
      final confirmed = await showDialog<bool>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Remove category?'),
          content: const Text('It will disappear from new expense choices. Existing expenses and their category name stay intact.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Remove')),
          ],
        ));
      if (confirmed != true) return;
    }
    try {
      await services.setCloudCategoryArchived(
        householdId, category.id, !category.archived);
    } catch (error) {
      if (context.mounted) _showCategoryError(context, error);
    }
  }

  void _showCategoryError(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Category could not be saved: $error')));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Expense categories')),
    floatingActionButton: owner ? FloatingActionButton.extended(
      onPressed: () => _create(context), icon: const Icon(Icons.add),
      label: const Text('Add category')) : null,
    body: StreamBuilder<List<CloudCategory>>(
      stream: services.watchCategories(householdId),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Categories could not load: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final categories = snapshot.data!;
        if (categories.isEmpty) return const Center(child: Text('No categories yet.'));
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [for (final category in categories)
            Card(child: ListTile(
              leading: Icon(_cloudCategoryIcon(category.name)),
              title: Text(category.name),
              subtitle: category.archived ? const Text('Removed from new expenses') : null,
              trailing: owner ? PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'rename') _rename(context, category);
                  if (action == 'archive') _setArchived(context, category);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'archive', child: Text(category.archived ?
                    'Restore' : 'Remove')),
                ]) : null,
            )),
          ],
        );
      },
    ),
  );
}

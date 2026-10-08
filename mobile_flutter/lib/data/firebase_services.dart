import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'recurring_period.dart';
import '../utils/input_limits.dart';
import '../utils/money.dart';

const starterCategories = <String>[
  'Home',
  'Groceries',
  'Dining',
  'Transport',
  'Health',
  'Leisure',
  'Gifts',
  'Other',
];

void _validateExpenseInput(
  int amountCents,
  int baseCents,
  int rateToBaseMicros,
  String currency,
  String description,
) {
  if (amountCents <= 0 ||
      amountCents > 1000000000 ||
      baseCents <= 0 ||
      baseCents > 1000000000 ||
      rateToBaseMicros <= 0 ||
      rateToBaseMicros > 1000000000) {
    throw const FormatException(
      'Enter an amount and rate within the supported range.',
    );
  }
  if (!supportedCurrencies.contains(currency)) {
    throw const FormatException('Choose a supported currency.');
  }
  final descriptionError = textInputError(
    description,
    label: 'Description',
    maximum: maxExpenseDescriptionLength,
    optional: true,
  );
  if (descriptionError != null) throw FormatException(descriptionError);
}

/// Firebase access boundary. It is only constructed after Firebase has been
/// initialized and an authenticated, verified user is present.
class FirebaseServices {
  FirebaseServices({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> get authChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final emailError = emailInputError(email);
    final passwordError = passwordInputError(password, creating: true);
    final nameError = textInputError(
      displayName,
      label: 'your name',
      maximum: maxDisplayNameLength,
    );
    if (emailError != null || passwordError != null || nameError != null) {
      throw FormatException(emailError ?? passwordError ?? nameError!);
    }
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user!.updateDisplayName(displayName.trim());
    await credential.user!.sendEmailVerification();
  }

  Future<void> signIn({required String email, required String password}) async {
    final emailError = emailInputError(email);
    final passwordError = passwordInputError(password, creating: false);
    if (emailError != null || passwordError != null) {
      throw FormatException(emailError ?? passwordError!);
    }
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  Future<bool> hasPendingAccountDeletion() async {
    final user = _requireVerifiedUser();
    final document = await _firestore
        .collection('accountDeletionRequests')
        .doc(user.uid)
        .get();
    return document.exists;
  }

  Future<void> requestAccountDeletion(String householdId) async {
    final user = _requireVerifiedUser();
    await _firestore.collection('accountDeletionRequests').doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'householdId': householdId,
      'requestedAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  Future<void> sendPasswordReset(String email) async {
    final error = emailInputError(email);
    if (error != null) throw FormatException(error);
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> resendVerification() async {
    final user = _requireUser();
    await user.sendEmailVerification();
  }

  Future<bool> refreshVerification() async {
    final user = _requireUser();
    await user.reload();
    final refreshed = _auth.currentUser;
    if (refreshed?.emailVerified == true) {
      await refreshed!.getIdToken(true);
      return true;
    }
    return false;
  }

  Future<void> ensureProfile() async {
    final user = _requireVerifiedUser();
    final profile = _firestore.collection('users').doc(user.uid);
    final existing = await profile.get();
    if (existing.exists) return;
    await profile.set({
      'displayName': _displayName(user),
      'email': user.email,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Creates a Firestore household and the owner's membership atomically.
  Future<String> createHousehold({
    required String name,
    required String currency,
  }) async {
    final nameError = textInputError(
      name,
      label: 'a household name',
      maximum: maxHouseholdNameLength,
    );
    if (nameError != null) throw FormatException(nameError);
    if (!supportedCurrencies.contains(currency)) {
      throw const FormatException('Choose a supported currency.');
    }
    final user = _requireVerifiedUser();
    await ensureProfile();
    final household = _firestore.collection('households').doc();
    final member = household.collection('members').doc(user.uid);
    final foundation = _firestore.batch();
    foundation.set(household, {
      'name': name.trim(),
      'baseCurrency': currency,
      'ownerId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    foundation.set(member, {
      'uid': user.uid,
      'displayName': _displayName(user),
      'role': 'owner',
      'status': 'active',
      'joinedAt': FieldValue.serverTimestamp(),
    });
    foundation.set(_firestore.collection('membershipIndex').doc(user.uid), {
      'uid': user.uid,
      'householdId': household.id,
    });
    for (final category in starterCategories) {
      foundation.set(household.collection('categories').doc(), {
        'name': category,
        'archived': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    foundation.set(household.collection('settings').doc('shared'), {
      'runningResetAt': Timestamp.fromDate(DateTime.utc(2000)),
    });
    await foundation.commit();
    return household.id;
  }

  /// Finds the active household for the signed-in account. The first release
  /// supports one active household per account.
  Future<CloudHousehold?> currentHousehold() async {
    final user = _requireVerifiedUser();
    final index = await _firestore
        .collection('membershipIndex')
        .doc(user.uid)
        .get();
    final indexedHouseholdId = index.data()?['householdId'] as String?;
    if (indexedHouseholdId != null) {
      final household = await _firestore
          .collection('households')
          .doc(indexedHouseholdId)
          .get();
      if (household.exists) {
        return CloudHousehold.fromSnapshot(
          household,
          memberName: _displayName(user),
        );
      }
    }
    // Households created before the index was introduced use the owner's UID as
    // their document ID. Repair their index and those of previously approved members.
    try {
      final owned = await _firestore
          .collection('households')
          .doc(user.uid)
          .get();
      if (!owned.exists || owned.data()?['ownerId'] != user.uid) return null;
      final members = await owned.reference.collection('members').get();
      for (final member in members.docs) {
        if (member.data()['status'] != 'active') continue;
        final ref = _firestore.collection('membershipIndex').doc(member.id);
        try {
          await ref.set({'uid': member.id, 'householdId': owned.id});
        } on FirebaseException catch (error) {
          // An existing index is immutable, so a retry is denied by the rules.
          if (error.code != 'permission-denied') rethrow;
        }
      }
      return CloudHousehold.fromSnapshot(owned, memberName: _displayName(user));
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
    }
    return null;
  }

  Future<List<CloudMember>> members(String householdId) async {
    final snapshot = await _firestore
        .collection('households')
        .doc(householdId)
        .collection('members')
        .orderBy('joinedAt')
        .get();
    return snapshot.docs.map(CloudMember.fromSnapshot).toList();
  }

  Stream<List<CloudExpense>> watchExpenses(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('expenses')
      .where(
        'expenseDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(
          DateTime(DateTime.now().year, DateTime.now().month - 5),
        ),
      )
      .orderBy('expenseDate', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(CloudExpense.fromSnapshot).toList());

  Stream<List<CloudExpense>> watchExpenseHistory(
    String householdId, {
    DateTime? start,
    DateTime? end,
    required int limit,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('households')
        .doc(householdId)
        .collection('expenses');
    if (start != null) {
      query = query.where(
        'expenseDate',
        isGreaterThanOrEqualTo: Timestamp.fromDate(start),
      );
    }
    if (end != null) {
      query = query.where('expenseDate', isLessThan: Timestamp.fromDate(end));
    }
    return query
        .orderBy('expenseDate', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(CloudExpense.fromSnapshot).toList(),
        );
  }

  Future<Map<String, int>> sharedRunningTotals(
    String householdId,
    DateTime resetAt,
    List<String> memberIds,
  ) async {
    _requireVerifiedUser();
    final expenses = _firestore
        .collection('households')
        .doc(householdId)
        .collection('expenses');
    Future<int> totalFor(String? authorId) async {
      Query<Map<String, dynamic>> query = expenses
          .where('isShared', isEqualTo: true)
          .where(
            'expenseDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(resetAt),
          )
          .where('expenseDate', isLessThanOrEqualTo: Timestamp.now());
      if (authorId != null) {
        query = query.where('authorId', isEqualTo: authorId);
      }
      final snapshot = await query.aggregate(sum('baseAmountCents')).get();
      return snapshot.getSum('baseAmountCents')?.round() ?? 0;
    }

    final ids = ['', ...memberIds];
    final values = await Future.wait(
      ids.map((id) => totalFor(id.isEmpty ? null : id)),
    );
    return {
      for (var index = 0; index < ids.length; index++)
        ids[index]: values[index],
    };
  }

  Stream<List<CloudCategory>> watchCategories(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('categories')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(CloudCategory.fromSnapshot).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  Future<void> createCloudCategory(String householdId, String name) async {
    _requireVerifiedUser();
    final clean = name.trim();
    final error = textInputError(
      clean,
      label: 'a category name',
      maximum: maxCategoryNameLength,
    );
    if (error != null) throw FormatException(error);
    await _firestore
        .collection('households')
        .doc(householdId)
        .collection('categories')
        .add({
          'name': clean,
          'archived': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> renameCloudCategory(
    String householdId,
    String categoryId,
    String name,
  ) async {
    _requireVerifiedUser();
    final clean = name.trim();
    final error = textInputError(
      clean,
      label: 'a category name',
      maximum: maxCategoryNameLength,
    );
    if (error != null) throw FormatException(error);
    await _firestore
        .collection('households')
        .doc(householdId)
        .collection('categories')
        .doc(categoryId)
        .update({'name': clean});
  }

  Future<void> setCloudCategoryArchived(
    String householdId,
    String categoryId,
    bool archived,
  ) async {
    _requireVerifiedUser();
    await _firestore
        .collection('households')
        .doc(householdId)
        .collection('categories')
        .doc(categoryId)
        .update({'archived': archived});
  }

  Stream<List<CloudBudget>> watchBudgets(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('budgets')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(CloudBudget.fromSnapshot).toList());

  Stream<List<CloudRecurringTemplate>> watchRecurringTemplates(
    String householdId,
  ) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('recurringTemplates')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(CloudRecurringTemplate.fromSnapshot).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  Stream<List<CloudRecurringOccurrence>> watchRecurringOccurrences(
    String householdId,
    String month,
  ) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('recurringOccurrences')
      .where('month', isEqualTo: month)
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) =>
            snapshot.docs.map(CloudRecurringOccurrence.fromSnapshot).toList(),
      );

  Stream<List<CloudExpense>> watchRecurringPayments(
    String householdId,
    String month,
  ) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('expenses')
      .where('recurringMonth', isEqualTo: month)
      .snapshots(includeMetadataChanges: true)
      .map((snapshot) => snapshot.docs.map(CloudExpense.fromSnapshot).toList());

  Future<List<CloudExpense>> recurringPayments(
    String householdId,
    String month,
  ) async {
    final snapshot = await _firestore
        .collection('households')
        .doc(householdId)
        .collection('expenses')
        .where('recurringMonth', isEqualTo: month)
        .get();
    return snapshot.docs.map(CloudExpense.fromSnapshot).toList();
  }

  Future<List<CloudRecurringOccurrence>> recurringPeriods(
    String householdId,
    String month,
  ) async {
    final snapshot = await _firestore
        .collection('households')
        .doc(householdId)
        .collection('recurringOccurrences')
        .where('month', isEqualTo: month)
        .get();
    return snapshot.docs.map(CloudRecurringOccurrence.fromSnapshot).toList();
  }

  Future<List<CloudExpense>> expensesInMonth(
    String householdId,
    DateTime month,
  ) async {
    final snapshot = await _firestore
        .collection('households')
        .doc(householdId)
        .collection('expenses')
        .where(
          'expenseDate',
          isGreaterThanOrEqualTo: Timestamp.fromDate(
            DateTime(month.year, month.month),
          ),
        )
        .where(
          'expenseDate',
          isLessThan: Timestamp.fromDate(DateTime(month.year, month.month + 1)),
        )
        .get();
    return snapshot.docs.map(CloudExpense.fromSnapshot).toList();
  }

  Future<CloudRecurringOccurrence> ensureRecurringPeriod(
    String householdId,
    RecurringLink link,
  ) async {
    _requireVerifiedUser();
    final household = _firestore.collection('households').doc(householdId);
    final ref = household
        .collection('recurringOccurrences')
        .doc('${link.id}_${link.month}');
    final cached = await ref.get();
    if (cached.exists && cached.data()?['version'] == 2) {
      return CloudRecurringOccurrence.fromSnapshot(cached);
    }
    await _firestore.runTransaction((transaction) async {
      final period = await transaction.get(ref);
      if (period.exists && period.data()?['version'] == 2) return;
      final templateDoc = await transaction.get(
        household.collection('recurringTemplates').doc(link.id),
      );
      if (!templateDoc.exists) {
        throw StateError('Recurring item no longer exists.');
      }
      final template = templateDoc.data()!;
      if (template['startMonth'].toString().compareTo(link.month) > 0 ||
          (!period.exists && template['archived'] == true)) {
        throw StateError('This recurring item is not active for that month.');
      }
      Map<String, dynamic>? oldPayment;
      final oldExpenseId = period.data()?['expenseId'] as String?;
      if (oldExpenseId != null) {
        oldPayment = (await transaction.get(
          household.collection('expenses').doc(oldExpenseId),
        )).data();
      }
      final currency = oldPayment?['currency'] ?? template['currency'];
      transaction.set(ref, {
        'version': 2,
        'recurringId': link.id,
        'month': link.month,
        'name': template['name'],
        'expectedAmountCents': currency == template['currency']
            ? template['amountCents']
            : oldPayment!['amountCents'],
        'categoryId': oldPayment?['categoryId'] ?? template['categoryId'],
        'currency': currency,
        'isShared': oldPayment?['isShared'] ?? template['isShared'],
        'dueDay': template['dueDay'],
        'graceDays': template['graceDays'],
        'createdAt':
            period.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return CloudRecurringOccurrence.fromSnapshot(await ref.get());
  }

  void _checkRecurringFields(
    CloudRecurringOccurrence period,
    String categoryId,
    String currency,
    bool shared,
  ) {
    if (period.categoryId != categoryId ||
        period.currency != currency ||
        period.isShared != shared) {
      throw StateError(
        'Use the category, currency and sharing of this monthly recurring item, or unlink the payment.',
      );
    }
  }

  Future<void> saveRecurringTemplate(
    String householdId, {
    String? id,
    required String name,
    required String categoryId,
    required int amountCents,
    required String currency,
    required int dueDay,
    required int graceDays,
    required bool shared,
    required String startMonth,
    bool updateCurrentMonthPayments = false,
  }) async {
    _requireVerifiedUser();
    final cleanName = name.trim();
    if (textInputError(
              cleanName,
              label: 'a recurring name',
              maximum: maxRecurringNameLength,
            ) !=
            null ||
        amountCents <= 0 ||
        amountCents > 1000000000 ||
        (dueDay != 0 && (dueDay < 1 || dueDay > 28)) ||
        graceDays < 0 ||
        graceDays > 14 ||
        !supportedCurrencies.contains(currency)) {
      throw const FormatException(
        'Check the recurring name, amount and due date.',
      );
    }
    final collection = _firestore
        .collection('households')
        .doc(householdId)
        .collection('recurringTemplates');
    final values = <String, Object>{
      'name': cleanName,
      'categoryId': categoryId,
      'amountCents': amountCents,
      'currency': currency,
      'dueDay': dueDay,
      'graceDays': graceDays,
      'isShared': shared,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (id == null) {
      await collection.add({
        ...values,
        'startMonth': startMonth,
        'archived': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Freeze legacy months before changing the template; no expenses are copied.
      final periods = await _firestore
          .collection('households')
          .doc(householdId)
          .collection('recurringOccurrences')
          .where('recurringId', isEqualTo: id)
          .get();
      for (final period in periods.docs) {
        if (period.data()['version'] != 2) {
          await ensureRecurringPeriod(
            householdId,
            RecurringLink(id, period.data()['month'] as String),
          );
        }
      }
      final month = recurringMonth(DateTime.now());
      final payments = (await recurringPayments(
        householdId,
        month,
      )).where((payment) => payment.recurringId == id).toList();
      CloudRecurringOccurrence? current;
      final currentTemplate = (await collection.doc(id).get()).data();
      if (payments.isNotEmpty ||
          (currentTemplate != null &&
              currentTemplate['archived'] != true &&
              currentTemplate['startMonth'].toString().compareTo(month) <= 0)) {
        current = await ensureRecurringPeriod(
          householdId,
          RecurringLink(id, month),
        );
      }
      final batch = _firestore.batch();
      batch.update(collection.doc(id), values);
      if (updateCurrentMonthPayments && current != null) {
        if (current.currency != currency || current.isShared != shared) {
          throw StateError(
            'Currency and sharing changes apply only to future payments.',
          );
        }
        if (payments.any(
          (payment) => payment.authorId != _requireVerifiedUser().uid,
        )) {
          throw StateError(
            'Some payments belong to another member. Choose Only future payments.',
          );
        }
        if (payments.length > 450) {
          throw StateError(
            'Too many linked payments to update atomically. Choose Only future payments.',
          );
        }
        batch.update(
          _firestore
              .collection('households')
              .doc(householdId)
              .collection('recurringOccurrences')
              .doc('${id}_$month'),
          {
            'categoryId': categoryId,
            'name': cleanName,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
        for (final payment in payments) {
          batch.update(
            _firestore
                .collection('households')
                .doc(householdId)
                .collection('expenses')
                .doc(payment.id),
            {
              'categoryId': categoryId,
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );
        }
      }
      await batch.commit();
    }
  }

  Future<void> setRecurringArchived(
    String householdId,
    String recurringId,
    bool archived,
  ) async {
    _requireVerifiedUser();
    await _firestore
        .collection('households')
        .doc(householdId)
        .collection('recurringTemplates')
        .doc(recurringId)
        .update({
          'archived': archived,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Stream<DateTime> watchSharedResetAt(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('settings')
      .doc('shared')
      .snapshots()
      .map(
        (snapshot) =>
            (snapshot.data()?['runningResetAt'] as Timestamp?)?.toDate() ??
            DateTime.utc(2000),
      );

  Future<void> resetSharedTotal(String householdId) async {
    _requireVerifiedUser();
    await _firestore
        .collection('households')
        .doc(householdId)
        .collection('settings')
        .doc('shared')
        .update({'runningResetAt': FieldValue.serverTimestamp()});
  }

  Stream<List<CloudMember>> watchMembers(String householdId) => _firestore
      .collection('households')
      .doc(householdId)
      .collection('members')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(CloudMember.fromSnapshot).toList());

  Stream<List<CloudJoinRequest>> watchJoinRequests(String householdId) =>
      _firestore
          .collection('households')
          .doc(householdId)
          .collection('joinRequests')
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map(CloudJoinRequest.fromSnapshot).toList(),
          );

  Future<void> addCloudExpense({
    required String householdId,
    required String categoryId,
    required int amountCents,
    required String currency,
    required int rateToBaseMicros,
    required String description,
    required bool shared,
    required DateTime date,
    RecurringLink? recurring,
  }) async {
    final user = _requireVerifiedUser();
    final baseCents = convertCents(amountCents, rateToBaseMicros);
    _validateExpenseInput(
      amountCents,
      baseCents,
      rateToBaseMicros,
      currency,
      description,
    );
    final household = _firestore.collection('households').doc(householdId);
    final expenses = household.collection('expenses');
    final expense = expenses.doc();
    final data = <String, Object>{
      'authorId': user.uid,
      'authorName': _displayName(user),
      'amountCents': amountCents,
      'baseAmountCents': baseCents,
      'rateToBaseMicros': rateToBaseMicros,
      'currency': currency,
      'categoryId': categoryId,
      'description': description.trim(),
      'isShared': shared,
      'expenseDate': Timestamp.fromDate(date),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (recurring == null) {
      await expense.set(data);
      return;
    }
    final period = await ensureRecurringPeriod(householdId, recurring);
    _checkRecurringFields(period, categoryId, currency, shared);
    data['recurringId'] = recurring.id;
    data['recurringMonth'] = recurring.month;
    await expense.set(data);
  }

  Future<void> updateCloudExpense({
    required String householdId,
    required String expenseId,
    required String categoryId,
    required int amountCents,
    required String currency,
    required int rateToBaseMicros,
    required String description,
    required bool shared,
    required DateTime date,
    RecurringLink? recurring,
  }) async {
    final user = _requireVerifiedUser();
    final baseCents = convertCents(amountCents, rateToBaseMicros);
    _validateExpenseInput(
      amountCents,
      baseCents,
      rateToBaseMicros,
      currency,
      description,
    );
    final household = _firestore.collection('households').doc(householdId);
    final expense = household.collection('expenses').doc(expenseId);
    final existing = await expense.get();
    if (!existing.exists) throw StateError('Expense no longer exists.');
    final oldId = existing.data()?['recurringId'] as String?;
    final oldMonth = existing.data()?['recurringMonth'] as String?;
    final oldLink = oldId != null && oldMonth != null
        ? RecurringLink(oldId, oldMonth)
        : null;
    if (existing.data()?['authorId'] != user.uid) {
      throw StateError('Only the author can edit this expense.');
    }
    if (recurring != null) {
      final period = await ensureRecurringPeriod(householdId, recurring);
      final unchangedFields =
          recurring == oldLink &&
          existing.data()?['categoryId'] == categoryId &&
          existing.data()?['currency'] == currency &&
          existing.data()?['isShared'] == shared;
      if (!unchangedFields) {
        _checkRecurringFields(period, categoryId, currency, shared);
      }
    }
    final values = <String, Object>{
      'amountCents': amountCents,
      'baseAmountCents': baseCents,
      'rateToBaseMicros': rateToBaseMicros,
      'currency': currency,
      'categoryId': categoryId,
      'description': description.trim(),
      'isShared': shared,
      'expenseDate': Timestamp.fromDate(date),
      'updatedAt': FieldValue.serverTimestamp(),
      'recurringId': recurring?.id ?? FieldValue.delete(),
      'recurringMonth': recurring?.month ?? FieldValue.delete(),
    };
    await expense.update(values);
  }

  Future<void> deleteCloudExpense(String householdId, String expenseId) async {
    final user = _requireVerifiedUser();
    final household = _firestore.collection('households').doc(householdId);
    final expense = household.collection('expenses').doc(expenseId);
    // Confirm deletion online. Monthly plans remain; paid totals derive from expenses.
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(expense);
      if (!existing.exists) return;
      final data = existing.data()!;
      if (data['authorId'] != user.uid) {
        throw StateError('Only the author can delete this expense.');
      }
      transaction.delete(expense);
    });
  }

  Future<void> setCloudBudget(
    String householdId,
    String categoryId,
    String currency,
    int amountCents,
  ) async {
    _requireVerifiedUser();
    if (amountCents < 0 || amountCents > 1000000000) {
      throw ArgumentError('Budget must be between 0 and 10,000,000.00.');
    }
    await _firestore
        .collection('households')
        .doc(householdId)
        .collection('budgets')
        .doc(categoryId)
        .set({
          'categoryId': categoryId,
          'currency': currency,
          'amountCents': amountCents,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> setCloudMonthlyBudget(
    String householdId,
    String currency,
    int amountCents,
  ) async {
    _requireVerifiedUser();
    if (amountCents < 0 || amountCents > 1000000000) {
      throw ArgumentError('Budget must be between 0 and 10,000,000.00.');
    }
    await _firestore
        .collection('households')
        .doc(householdId)
        .collection('budgets')
        .doc('monthly')
        .set({
          'categoryId': '',
          'currency': currency,
          'amountCents': amountCents,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<String> createInvite(String householdId) async {
    final user = _requireVerifiedUser();
    final code = _newInviteCode();
    await _firestore.collection('invites').doc(code).set({
      'householdId': householdId,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(
        DateTime.now().toUtc().add(const Duration(hours: 24)),
      ),
      'redeemedBy': null,
      'redeemedAt': null,
    });
    return code;
  }

  /// Consumes the code and records an approval request in one transaction.
  Future<void> requestToJoin(String code) async {
    final user = _requireVerifiedUser();
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty ||
        normalized.length > maxInviteCodeLength ||
        !RegExp(r'^[A-Z0-9_-]+$').hasMatch(normalized)) {
      throw const FirebaseJoinException('Enter a valid invitation code.');
    }
    final invite = _firestore.collection('invites').doc(normalized);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(invite);
      if (!snapshot.exists) {
        throw const FirebaseJoinException('That invitation code is invalid.');
      }
      final data = snapshot.data()!;
      final expiry = data['expiresAt'] as Timestamp?;
      if (expiry == null || expiry.toDate().isBefore(DateTime.now().toUtc())) {
        throw const FirebaseJoinException('That invitation code has expired.');
      }
      if (data['redeemedBy'] != null) {
        throw const FirebaseJoinException(
          'That invitation code was already used.',
        );
      }
      final householdId = data['householdId'] as String?;
      if (householdId == null) {
        throw const FirebaseJoinException('That invitation is incomplete.');
      }
      final request = _firestore
          .collection('households')
          .doc(householdId)
          .collection('joinRequests')
          .doc(user.uid);
      transaction.update(invite, {
        'redeemedBy': user.uid,
        'redeemedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(request, {
        'uid': user.uid,
        'displayName': _displayName(user),
        'inviteCode': normalized,
        'requestedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<List<CloudJoinRequest>> pendingJoinRequests(String householdId) async {
    final snapshot = await _firestore
        .collection('households')
        .doc(householdId)
        .collection('joinRequests')
        .orderBy('requestedAt')
        .get();
    return snapshot.docs.map(CloudJoinRequest.fromSnapshot).toList();
  }

  Future<void> approveJoinRequest({
    required String householdId,
    required CloudJoinRequest request,
  }) async {
    final batch = _firestore.batch();
    batch.set(
      _firestore
          .collection('households')
          .doc(householdId)
          .collection('members')
          .doc(request.uid),
      {
        'uid': request.uid,
        'displayName': request.displayName,
        'role': 'member',
        'status': 'active',
        'joinedAt': FieldValue.serverTimestamp(),
      },
    );
    batch.delete(
      _firestore
          .collection('households')
          .doc(householdId)
          .collection('joinRequests')
          .doc(request.uid),
    );
    batch.set(_firestore.collection('membershipIndex').doc(request.uid), {
      'uid': request.uid,
      'householdId': householdId,
    });
    await batch.commit();
  }

  Future<void> transferHousehold({
    required String householdId,
    required String newOwnerId,
  }) async {
    final user = _requireVerifiedUser();
    if (newOwnerId == user.uid) throw ArgumentError('Choose another member.');
    final household = _firestore.collection('households').doc(householdId);
    final currentMember = household.collection('members').doc(user.uid);
    final nextMember = household.collection('members').doc(newOwnerId);
    await _firestore.runTransaction((transaction) async {
      final home = await transaction.get(household);
      final current = await transaction.get(currentMember);
      final next = await transaction.get(nextMember);
      if (home.data()?['ownerId'] != user.uid ||
          current.data()?['role'] != 'owner') {
        throw StateError('Only the current owner can transfer this household.');
      }
      if (next.data()?['status'] != 'active' ||
          next.data()?['role'] != 'member') {
        throw StateError('Choose an active member.');
      }
      transaction.update(household, {
        'ownerId': newOwnerId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(currentMember, {'role': 'member'});
      transaction.update(nextMember, {'role': 'owner'});
    });
  }

  Future<void> leaveHousehold(String householdId) async {
    final user = _requireVerifiedUser();
    final member = _firestore
        .collection('households')
        .doc(householdId)
        .collection('members')
        .doc(user.uid);
    final snapshot = await member.get();
    if (!snapshot.exists) {
      throw StateError('You are not a member of this household.');
    }
    if (snapshot.data()?['role'] == 'owner') {
      throw StateError('Transfer ownership to another member before leaving.');
    }
    final batch = _firestore.batch();
    batch.delete(member);
    batch.delete(_firestore.collection('membershipIndex').doc(user.uid));
    await batch.commit();
  }

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) throw FirebaseAuthException(code: 'not-signed-in');
    return user;
  }

  User _requireVerifiedUser() {
    final user = _requireUser();
    if (!user.emailVerified) {
      throw FirebaseAuthException(code: 'email-not-verified');
    }
    return user;
  }

  String _displayName(User user) {
    final value = user.displayName?.trim() ?? '';
    if (textInputError(
          value,
          label: 'your name',
          maximum: maxDisplayNameLength,
        ) !=
        null) {
      return 'Household member';
    }
    return value;
  }

  String _newInviteCode() {
    final bytes = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '').toUpperCase();
  }
}

class CloudHousehold {
  const CloudHousehold({
    required this.id,
    required this.name,
    required this.currency,
    required this.memberName,
    required this.ownerId,
  });
  final String id;
  final String name;
  final String currency;
  final String memberName;
  final String ownerId;

  factory CloudHousehold.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    required String memberName,
  }) {
    final data = snapshot.data()!;
    return CloudHousehold(
      id: snapshot.id,
      name: data['name'] as String? ?? 'My household',
      currency: data['baseCurrency'] as String? ?? 'RSD',
      memberName: memberName,
      ownerId: data['ownerId'] as String? ?? '',
    );
  }
}

class CloudCategory {
  const CloudCategory({
    required this.id,
    required this.name,
    required this.archived,
  });
  final String id, name;
  final bool archived;

  factory CloudCategory.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;
    return CloudCategory(
      id: snapshot.id,
      name: data['name'] as String? ?? 'Other',
      archived: data['archived'] == true,
    );
  }
}

class CloudBudget {
  const CloudBudget({
    required this.categoryId,
    required this.currency,
    required this.amountCents,
  });
  final String categoryId, currency;
  final int amountCents;

  factory CloudBudget.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;
    return CloudBudget(
      categoryId: data['categoryId'] as String? ?? '',
      currency: data['currency'] as String? ?? 'RSD',
      amountCents: data['amountCents'] as int? ?? 0,
    );
  }
}

class CloudExpense {
  const CloudExpense({
    required this.id,
    required this.authorId,
    required this.amountCents,
    required this.baseAmountCents,
    this.rateToBaseMicros,
    required this.currency,
    required this.categoryId,
    required this.description,
    required this.isShared,
    required this.expenseDate,
    this.authorName = '',
    this.recurringId,
    this.recurringMonth,
    this.pendingSync = false,
  });
  final String id, authorId, authorName, currency, categoryId, description;
  final int amountCents;
  final int? baseAmountCents;
  final int? rateToBaseMicros;
  final bool isShared;
  final DateTime expenseDate;
  final String? recurringId, recurringMonth;
  final bool pendingSync;

  factory CloudExpense.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;
    String stringValue(String key, String fallback) =>
        data[key] is String ? data[key] as String : fallback;
    int? intValue(String key) => data[key] is int ? data[key] as int : null;
    return CloudExpense(
      id: snapshot.id,
      authorId: stringValue('authorId', ''),
      authorName: stringValue('authorName', ''),
      amountCents: intValue('amountCents') ?? 0,
      baseAmountCents: intValue('baseAmountCents'),
      rateToBaseMicros: intValue('rateToBaseMicros'),
      currency: stringValue('currency', 'RSD'),
      categoryId: stringValue('categoryId', ''),
      description: stringValue('description', ''),
      isShared: data['isShared'] == true,
      expenseDate: data['expenseDate'] is Timestamp
          ? (data['expenseDate'] as Timestamp).toDate()
          : DateTime(2000),
      recurringId: data['recurringId'] is String
          ? data['recurringId'] as String
          : null,
      recurringMonth: data['recurringMonth'] is String
          ? data['recurringMonth'] as String
          : null,
      pendingSync: snapshot.metadata.hasPendingWrites,
    );
  }
}

class CloudRecurringTemplate {
  const CloudRecurringTemplate({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.amountCents,
    required this.currency,
    required this.dueDay,
    required this.graceDays,
    required this.isShared,
    required this.startMonth,
    required this.archived,
  });
  final String id, name, categoryId, currency, startMonth;
  final int amountCents, dueDay, graceDays;
  final bool isShared, archived;

  factory CloudRecurringTemplate.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    return CloudRecurringTemplate(
      id: snapshot.id,
      name: data['name'] as String? ?? '',
      categoryId: data['categoryId'] as String? ?? '',
      amountCents: data['amountCents'] as int? ?? 0,
      currency: data['currency'] as String? ?? 'RSD',
      dueDay: data['dueDay'] as int? ?? 1,
      graceDays: data['graceDays'] as int? ?? 0,
      isShared: data['isShared'] == true,
      startMonth: data['startMonth'] as String? ?? '',
      archived: data['archived'] == true,
    );
  }
}

class CloudRecurringOccurrence {
  const CloudRecurringOccurrence({
    required this.recurringId,
    required this.month,
    this.expenseId = '',
    this.authorId = '',
    required this.pendingSync,
    this.expectedCents,
    this.name,
    this.categoryId,
    this.currency,
    this.isShared,
    this.dueDay,
    this.graceDays,
  });
  final String recurringId, month, expenseId, authorId;
  final bool pendingSync;
  final int? expectedCents, dueDay, graceDays;
  final String? name, categoryId, currency;
  final bool? isShared;
  bool get legacy => expectedCents == null;

  CloudRecurringTemplate effectiveTemplate(CloudRecurringTemplate template) =>
      CloudRecurringTemplate(
        id: template.id,
        name: name ?? template.name,
        categoryId: categoryId ?? template.categoryId,
        amountCents: expectedCents ?? template.amountCents,
        currency: currency ?? template.currency,
        dueDay: dueDay ?? template.dueDay,
        graceDays: graceDays ?? template.graceDays,
        isShared: isShared ?? template.isShared,
        startMonth: template.startMonth,
        archived: template.archived,
      );

  factory CloudRecurringOccurrence.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data()!;
    return CloudRecurringOccurrence(
      recurringId: data['recurringId'] as String? ?? '',
      month: data['month'] as String? ?? '',
      expenseId: data['expenseId'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      expectedCents: data['expectedAmountCents'] as int?,
      name: data['name'] as String?,
      categoryId: data['categoryId'] as String?,
      currency: data['currency'] as String?,
      isShared: data['isShared'] as bool?,
      dueDay: data['dueDay'] as int?,
      graceDays: data['graceDays'] as int?,
      pendingSync: snapshot.metadata.hasPendingWrites,
    );
  }
}

class CloudMember {
  const CloudMember({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.status,
  });
  final String uid;
  final String displayName;
  final String role;
  final String status;

  factory CloudMember.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    return CloudMember(
      uid: data['uid'] as String,
      displayName: data['displayName'] as String? ?? 'Household member',
      role: data['role'] as String? ?? 'member',
      status: data['status'] as String? ?? 'pending',
    );
  }
}

class CloudJoinRequest {
  const CloudJoinRequest({
    required this.uid,
    required this.displayName,
    required this.requestedAt,
  });
  final String uid;
  final String displayName;
  final DateTime? requestedAt;

  factory CloudJoinRequest.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => CloudJoinRequest(
    uid: snapshot.data()['uid'] as String,
    displayName:
        snapshot.data()['displayName'] as String? ?? 'Household member',
    requestedAt: (snapshot.data()['requestedAt'] as Timestamp?)?.toDate(),
  );
}

class FirebaseJoinException implements Exception {
  const FirebaseJoinException(this.message);
  final String message;
  @override
  String toString() => message;
}

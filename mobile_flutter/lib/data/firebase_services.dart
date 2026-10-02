import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/money.dart';

const starterCategories = <String>[
  'Home', 'Groceries', 'Dining', 'Transport',
  'Health', 'Leisure', 'Gifts', 'Other',
];

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
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user!.updateDisplayName(displayName.trim());
    await credential.user!.sendEmailVerification();
  }

  Future<void> signIn({required String email, required String password}) =>
      _auth.signInWithEmailAndPassword(email: email.trim(), password: password);

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

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
    final index = await _firestore.collection('membershipIndex').doc(user.uid).get();
    final indexedHouseholdId = index.data()?['householdId'] as String?;
    if (indexedHouseholdId != null) {
      final household = await _firestore.collection('households').doc(indexedHouseholdId).get();
      if (household.exists) return CloudHousehold.fromSnapshot(household, memberName: _displayName(user));
    }
    // Households created before the index was introduced use the owner's UID as
    // their document ID. Repair their index and those of previously approved members.
    try {
      final owned = await _firestore.collection('households').doc(user.uid).get();
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
      .collection('households').doc(householdId).collection('expenses')
      .orderBy('expenseDate', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(CloudExpense.fromSnapshot).toList());

  Stream<List<CloudCategory>> watchCategories(String householdId) => _firestore
      .collection('households').doc(householdId).collection('categories')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(CloudCategory.fromSnapshot).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

  Future<void> createCloudCategory(String householdId, String name) async {
    _requireVerifiedUser();
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 40) {
      throw const FormatException('Use a category name of 1–40 characters.');
    }
    await _firestore.collection('households').doc(householdId)
      .collection('categories').add({
        'name': clean, 'archived': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
  }

  Future<void> renameCloudCategory(String householdId, String categoryId,
      String name) async {
    _requireVerifiedUser();
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 40) {
      throw const FormatException('Use a category name of 1–40 characters.');
    }
    await _firestore.collection('households').doc(householdId)
      .collection('categories').doc(categoryId).update({'name': clean});
  }

  Future<void> setCloudCategoryArchived(String householdId, String categoryId,
      bool archived) async {
    _requireVerifiedUser();
    await _firestore.collection('households').doc(householdId)
      .collection('categories').doc(categoryId).update({'archived': archived});
  }

  Stream<List<CloudBudget>> watchBudgets(String householdId) => _firestore
      .collection('households').doc(householdId).collection('budgets')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(CloudBudget.fromSnapshot).toList());

  Stream<DateTime> watchSharedResetAt(String householdId) => _firestore
      .collection('households').doc(householdId)
      .collection('settings').doc('shared').snapshots()
      .map((snapshot) => (snapshot.data()?['runningResetAt'] as Timestamp?)?.toDate()
        ?? DateTime.utc(2000));

  Future<void> resetSharedTotal(String householdId) async {
    _requireVerifiedUser();
    await _firestore.collection('households').doc(householdId)
      .collection('settings').doc('shared')
      .update({'runningResetAt': FieldValue.serverTimestamp()});
  }

  Stream<List<CloudMember>> watchMembers(String householdId) => _firestore
      .collection('households').doc(householdId).collection('members')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(CloudMember.fromSnapshot).toList());

  Stream<List<CloudJoinRequest>> watchJoinRequests(String householdId) => _firestore
      .collection('households').doc(householdId).collection('joinRequests')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(CloudJoinRequest.fromSnapshot).toList());

  Future<void> addCloudExpense({required String householdId, required String categoryId,
    required int amountCents, required String currency,
    required int rateToBaseMicros, required String description, required bool shared,
    required DateTime date}) async {
    final user = _requireVerifiedUser();
    final baseCents = convertCents(amountCents, rateToBaseMicros);
    if (amountCents <= 0 || baseCents <= 0) throw ArgumentError('Amount is too small.');
    await _firestore.collection('households').doc(householdId).collection('expenses').add({
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
    });
  }

  Future<void> updateCloudExpense({required String householdId, required String expenseId,
    required String categoryId, required int amountCents, required String currency,
    required int rateToBaseMicros, required String description, required bool shared,
    required DateTime date}) async {
    _requireVerifiedUser();
    final baseCents = convertCents(amountCents, rateToBaseMicros);
    if (amountCents <= 0 || baseCents <= 0) throw ArgumentError('Amount is too small.');
    await _firestore.collection('households').doc(householdId)
        .collection('expenses').doc(expenseId).update({
      'amountCents': amountCents,
      'baseAmountCents': baseCents,
      'rateToBaseMicros': rateToBaseMicros,
      'currency': currency,
      'categoryId': categoryId,
      'description': description.trim(),
      'isShared': shared,
      'expenseDate': Timestamp.fromDate(date),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteCloudExpense(String householdId, String expenseId) async {
    _requireVerifiedUser();
    await _firestore.collection('households').doc(householdId)
        .collection('expenses').doc(expenseId).delete();
  }

  Future<void> setCloudBudget(String householdId, String categoryId,
      String currency, int amountCents) async {
    _requireVerifiedUser();
    if (amountCents < 0) throw ArgumentError('Budget cannot be negative.');
    await _firestore.collection('households').doc(householdId)
        .collection('budgets').doc(categoryId).set({
      'categoryId': categoryId,
      'currency': currency,
      'amountCents': amountCents,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setCloudMonthlyBudget(String householdId, String currency,
      int amountCents) async {
    _requireVerifiedUser();
    if (amountCents < 0) throw ArgumentError('Budget cannot be negative.');
    await _firestore.collection('households').doc(householdId)
      .collection('budgets').doc('monthly').set({
        'categoryId': '', 'currency': currency, 'amountCents': amountCents,
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
      'expiresAt': Timestamp.fromDate(DateTime.now().toUtc().add(const Duration(hours: 24))),
      'redeemedBy': null,
      'redeemedAt': null,
    });
    return code;
  }

  /// Consumes the code and records an approval request in one transaction.
  Future<void> requestToJoin(String code) async {
    final user = _requireVerifiedUser();
    final normalized = code.trim().toUpperCase();
    final invite = _firestore.collection('invites').doc(normalized);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(invite);
      if (!snapshot.exists) throw const FirebaseJoinException('That invitation code is invalid.');
      final data = snapshot.data()!;
      final expiry = data['expiresAt'] as Timestamp?;
      if (expiry == null || expiry.toDate().isBefore(DateTime.now().toUtc())) {
        throw const FirebaseJoinException('That invitation code has expired.');
      }
      if (data['redeemedBy'] != null) {
        throw const FirebaseJoinException('That invitation code was already used.');
      }
      final householdId = data['householdId'] as String?;
      if (householdId == null) throw const FirebaseJoinException('That invitation is incomplete.');
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
      _firestore.collection('households').doc(householdId).collection('members').doc(request.uid),
      {
        'uid': request.uid,
        'displayName': request.displayName,
        'role': 'member',
        'status': 'active',
        'joinedAt': FieldValue.serverTimestamp(),
      },
    );
    batch.delete(_firestore.collection('households').doc(householdId).collection('joinRequests').doc(request.uid));
    batch.set(_firestore.collection('membershipIndex').doc(request.uid), {
      'uid': request.uid,
      'householdId': householdId,
    });
    await batch.commit();
  }

  Future<void> transferHousehold({required String householdId,
      required String newOwnerId}) async {
    final user = _requireVerifiedUser();
    if (newOwnerId == user.uid) throw ArgumentError('Choose another member.');
    final household = _firestore.collection('households').doc(householdId);
    final currentMember = household.collection('members').doc(user.uid);
    final nextMember = household.collection('members').doc(newOwnerId);
    await _firestore.runTransaction((transaction) async {
      final home = await transaction.get(household);
      final current = await transaction.get(currentMember);
      final next = await transaction.get(nextMember);
      if (home.data()?['ownerId'] != user.uid || current.data()?['role'] != 'owner') {
        throw StateError('Only the current owner can transfer this household.');
      }
      if (next.data()?['status'] != 'active' || next.data()?['role'] != 'member') {
        throw StateError('Choose an active member.');
      }
      transaction.update(household, {
        'ownerId': newOwnerId, 'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(currentMember, {'role': 'member'});
      transaction.update(nextMember, {'role': 'owner'});
    });
  }

  Future<void> leaveHousehold(String householdId) async {
    final user = _requireVerifiedUser();
    final member = _firestore.collection('households').doc(householdId)
      .collection('members').doc(user.uid);
    final snapshot = await member.get();
    if (!snapshot.exists) throw StateError('You are not a member of this household.');
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
    if (!user.emailVerified) throw FirebaseAuthException(code: 'email-not-verified');
    return user;
  }

  String _displayName(User user) =>
      user.displayName?.trim().isNotEmpty == true ? user.displayName!.trim() : 'Household member';

  String _newInviteCode() {
    final bytes = List<int>.generate(18, (_) => Random.secure().nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '').toUpperCase();
  }
}

class CloudHousehold {
  const CloudHousehold({required this.id, required this.name, required this.currency, required this.memberName, required this.ownerId});
  final String id;
  final String name;
  final String currency;
  final String memberName;
  final String ownerId;

  factory CloudHousehold.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot, {required String memberName}) {
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
  const CloudCategory({required this.id, required this.name, required this.archived});
  final String id, name;
  final bool archived;

  factory CloudCategory.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data()!;
    return CloudCategory(id: snapshot.id, name: data['name'] as String? ?? 'Other',
      archived: data['archived'] == true);
  }
}

class CloudBudget {
  const CloudBudget({required this.categoryId, required this.currency, required this.amountCents});
  final String categoryId, currency;
  final int amountCents;

  factory CloudBudget.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data()!;
    return CloudBudget(categoryId: data['categoryId'] as String? ?? '',
      currency: data['currency'] as String? ?? 'RSD', amountCents: data['amountCents'] as int? ?? 0);
  }
}

class CloudExpense {
  const CloudExpense({required this.id, required this.authorId, required this.amountCents,
    required this.baseAmountCents, this.rateToBaseMicros, required this.currency, required this.categoryId,
    required this.description, required this.isShared, required this.expenseDate});
  final String id, authorId, currency, categoryId, description;
  final int amountCents;
  final int? baseAmountCents;
  final int? rateToBaseMicros;
  final bool isShared;
  final DateTime expenseDate;

  factory CloudExpense.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data()!;
    return CloudExpense(id: snapshot.id, authorId: data['authorId'] as String? ?? '',
      amountCents: data['amountCents'] as int? ?? 0,
      baseAmountCents: data['baseAmountCents'] as int?,
      rateToBaseMicros: data['rateToBaseMicros'] as int?,
      currency: data['currency'] as String? ?? 'RSD',
      categoryId: data['categoryId'] as String? ?? '',
      description: data['description'] as String? ?? '',
      isShared: data['isShared'] == true,
      expenseDate: (data['expenseDate'] as Timestamp?)?.toDate() ?? DateTime(2000));
  }
}

class CloudMember {
  const CloudMember({required this.uid, required this.displayName, required this.role, required this.status});
  final String uid;
  final String displayName;
  final String role;
  final String status;

  factory CloudMember.fromSnapshot(QueryDocumentSnapshot<Map<String, dynamic>> snapshot) {
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
  const CloudJoinRequest({required this.uid, required this.displayName, required this.requestedAt});
  final String uid;
  final String displayName;
  final DateTime? requestedAt;

  factory CloudJoinRequest.fromSnapshot(QueryDocumentSnapshot<Map<String, dynamic>> snapshot) => CloudJoinRequest(
        uid: snapshot.data()['uid'] as String,
        displayName: snapshot.data()['displayName'] as String? ?? 'Household member',
        requestedAt: (snapshot.data()['requestedAt'] as Timestamp?)?.toDate(),
      );
}

class FirebaseJoinException implements Exception {
  const FirebaseJoinException(this.message);
  final String message;
  @override
  String toString() => message;
}

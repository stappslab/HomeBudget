const { before, beforeEach, after, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { deleteField } = require('firebase/firestore');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');

let env;
const today = new Date();
const testMonth = today.toISOString().slice(0, 7);
const futureTestMonth = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() + 1, 1)).toISOString().slice(0, 7);
const previousTestMonth = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() - 1, 1)).toISOString().slice(0, 7);
const household = 'household-one';
const root = () => `households/${household}`;
const auth = (uid) => env.authenticatedContext(uid, {
  email: `${uid}@example.com`, email_verified: true,
}).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'homebudget-rules-test',
    firestore: {
      host: '127.0.0.1', port: 8081,
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc(root()).set({
      name: 'Test household', baseCurrency: 'RSD', ownerId: 'owner',
      createdAt: new Date(), updatedAt: new Date(),
    });
    await db.doc(`${root()}/members/owner`).set({
      uid: 'owner', displayName: 'Owner', role: 'owner', status: 'active', joinedAt: new Date(),
    });
    await db.doc(`${root()}/members/member`).set({
      uid: 'member', displayName: 'Member', role: 'member', status: 'active', joinedAt: new Date(),
    });
  });
});

after(async () => { if (env) await env.cleanup(); });

const expense = (authorId) => ({
  authorId, authorName: authorId, amountCents: 1000, baseAmountCents: 1000,
  rateToBaseMicros: 1000000, currency: 'RSD', categoryId: 'food',
  description: 'Test', isShared: true, expenseDate: new Date(),
  createdAt: new Date(), updatedAt: new Date(),
});

test('unrelated account cannot access a household', async () => {
  const db = auth('outsider');
  await assertFails(db.doc(root()).get());
  await assertFails(db.collection(`${root()}/expenses`).get());
  await assertFails(db.collection(`${root()}/expenses`).add(expense('outsider')));
});

test('a member can discover only their own membership', async () => {
  const db = auth('member');
  const result = await assertSucceeds(db.collectionGroup('members')
    .where('uid', '==', 'member').get());
  assert.equal(result.docs.length, 1);
  await assertFails(db.collectionGroup('members').get());
});

test('membership index is readable only by its member', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc('membershipIndex/member').set({
      uid: 'member', householdId: household,
    });
  });
  await assertSucceeds(auth('member').doc('membershipIndex/member').get());
  await assertFails(auth('outsider').doc('membershipIndex/member').get());
  await assertFails(auth('member').collection('membershipIndex').get());
});

test('account deletion requests are private and cannot be forged or changed', async () => {
  const own = auth('member').doc('accountDeletionRequests/member');
  const other = auth('outsider').doc('accountDeletionRequests/member');
  await assertFails(other.get());
  await assertFails(own.set({ uid: 'owner', email: 'member@example.com',
    requestedAt: new Date(), status: 'pending' }));
  await assertSucceeds(own.set({ uid: 'member', email: 'member@example.com',
    householdId: household, requestedAt: new Date(), status: 'pending' }));
  await assertSucceeds(own.get());
  await assertFails(other.get());
  await assertFails(own.update({ status: 'approved' }));
  await assertFails(own.delete());
});

test('members can add only their own expenses; owner controls budgets', async () => {
  const member = auth('member');
  const owner = auth('owner');
  await assertSucceeds(member.collection(`${root()}/expenses`).add(expense('member')));
  await assertFails(member.collection(`${root()}/expenses`).add(expense('owner')));
  await assertFails(member.collection(`${root()}/expenses`).add({
    ...expense('member'), baseAmountCents: 999999,
  }));
  await assertFails(member.doc(`${root()}/budgets/food`).set({
    categoryId: 'food', currency: 'RSD', amountCents: 5000,
  }));
  await assertSucceeds(owner.doc(`${root()}/budgets/food`).set({
    categoryId: 'food', currency: 'RSD', amountCents: 5000,
  }));
  await assertSucceeds(owner.doc(`${root()}/budgets/monthly`).set({
    categoryId: '', currency: 'RSD', amountCents: 5000000,
  }));
  await assertFails(member.doc(`${root()}/budgets/monthly`).set({
    categoryId: '', currency: 'RSD', amountCents: 5000000,
  }));
});

test('only the owner can create, rename and archive categories', async () => {
  const owner = auth('owner');
  const member = auth('member');
  const ref = `${root()}/categories/custom`;
  await assertFails(member.doc(ref).set({
    name: 'Pets', archived: false, createdAt: new Date(),
  }));
  await assertFails(owner.doc(ref).set({
    name: '', archived: false, createdAt: new Date(),
  }));
  await assertFails(owner.doc(ref).set({
    name: '   ', archived: false, createdAt: new Date(),
  }));
  await assertFails(owner.doc(ref).set({
    name: 'x'.repeat(41), archived: false, createdAt: new Date(),
  }));
  await assertFails(owner.doc(ref).set({
    name: 'Pets\nOther', archived: false, createdAt: new Date(),
  }));
  await assertSucceeds(owner.doc(ref).set({
    name: 'Pets', archived: false, createdAt: new Date(),
  }));
  await assertFails(member.doc(ref).update({ name: 'Animals' }));
  await assertSucceeds(owner.doc(ref).update({ name: 'Animals' }));
  await assertSucceeds(owner.doc(ref).update({ archived: true }));
  await assertFails(owner.doc(ref).update({ createdAt: new Date() }));
  await assertFails(owner.doc(ref).delete());
  const archived = await assertSucceeds(member.doc(ref).get());
  assert.equal(archived.data().name, 'Animals');
});

test('member cannot edit or delete another author’s expense', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc(`${root()}/expenses/owned`).set(expense('owner'));
  });
  const db = auth('member');
  await assertFails(db.doc(`${root()}/expenses/owned`).update({ description: 'Changed' }));
  await assertFails(db.doc(`${root()}/expenses/owned`).delete());
  await assertSucceeds(auth('owner').doc(`${root()}/expenses/owned`).delete());
});

test('author can edit their own expense', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc(`${root()}/expenses/mine`).set(expense('member'));
  });
  await assertSucceeds(auth('member').doc(`${root()}/expenses/mine`).update({
    description: 'Updated', amountCents: 2000, baseAmountCents: 2000,
  }));
});

test('expense edits cannot corrupt fields used by the app', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc(`${root()}/expenses/validated`).set(expense('member'));
  });
  const ref = auth('member').doc(`${root()}/expenses/validated`);
  await assertFails(ref.update({ expenseDate: 'not a date' }));
  await assertFails(ref.update({ categoryId: 42 }));
  await assertFails(ref.update({ isShared: 'yes' }));
  await assertFails(ref.update({ currency: 'EURO' }));
  await assertFails(ref.update({ description: 'x'.repeat(501) }));
  await assertFails(ref.update({ description: 'Line 1\nLine 2' }));
  await assertFails(ref.update({ createdAt: new Date(0) }));
  await assertFails(ref.update({ authorName: 'Someone else' }));
  await assertFails(ref.update({ unexpectedField: true }));
  await assertSucceeds(ref.update({ description: 'Valid change' }));
});

test('historical expense may retain an amount awaiting manual conversion', async () => {
  const db = auth('owner');
  await assertSucceeds(db.doc(`${root()}/expenses/historical_1`).set({
    ...expense('owner'), currency: 'EUR', baseAmountCents: null,
    rateToBaseMicros: null,
  }));
});

test('invited account needs owner approval before reading household data', async () => {
  const code = 'SINGLEUSECODE';
  await env.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc(`invites/${code}`).set({
      householdId: household, createdBy: 'owner', createdAt: new Date(),
      expiresAt: new Date(Date.now() + 3600000), redeemedBy: null, redeemedAt: null,
    });
  });
  const applicant = auth('applicant');
  await assertFails(applicant.doc(root()).get());
  const batch = applicant.batch();
  batch.update(applicant.doc(`invites/${code}`), {
    redeemedBy: 'applicant', redeemedAt: new Date(),
  });
  batch.set(applicant.doc(`${root()}/joinRequests/applicant`), {
    uid: 'applicant', displayName: 'Applicant', inviteCode: code, requestedAt: new Date(),
  });
  await assertSucceeds(batch.commit());
  await assertFails(applicant.doc(root()).get());
  await assertFails(applicant.doc(`${root()}/members/applicant`).set({
    uid: 'applicant', displayName: 'Applicant', role: 'member',
    status: 'active', joinedAt: new Date(),
  }));
  await assertSucceeds(auth('owner').doc(`${root()}/members/applicant`).set({
    uid: 'applicant', displayName: 'Applicant', role: 'member',
    status: 'active', joinedAt: new Date(),
  }));
  await assertSucceeds(auth('owner').doc('membershipIndex/applicant').set({
    uid: 'applicant', householdId: household,
  }));
  await assertSucceeds(applicant.doc(root()).get());
  await assertFails(auth('other').doc(`invites/${code}`).get());
});

test('expired invite and code-only redemption are rejected', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc('invites/EXPIRED').set({
      householdId: household, createdBy: 'owner', createdAt: new Date(0),
      expiresAt: new Date(1000), redeemedBy: null, redeemedAt: null,
    });
    await db.doc('invites/VALID').set({
      householdId: household, createdBy: 'owner', createdAt: new Date(),
      expiresAt: new Date(Date.now() + 3600000), redeemedBy: null, redeemedAt: null,
    });
  });
  const db = auth('applicant');
  await assertFails(db.doc('invites/EXPIRED').get());
  await assertFails(db.doc('invites/EXPIRED').update({
    redeemedBy: 'applicant', redeemedAt: new Date(),
  }));
  await assertFails(db.doc('invites/VALID').update({
    redeemedBy: 'applicant', redeemedAt: new Date(),
  }));
});

test('new household foundation can be created in a single batch', async () => {
  const db = auth('newowner');
  const ref = db.doc('households/newowner');
  const batch = db.batch();
  batch.set(ref, {
    name: 'New household', baseCurrency: 'EUR', ownerId: 'newowner',
    createdAt: new Date(), updatedAt: new Date(),
  });
  batch.set(ref.collection('members').doc('newowner'), {
    uid: 'newowner', displayName: 'New owner', role: 'owner',
    status: 'active', joinedAt: new Date(),
  });
  for (const name of ['Home', 'Groceries', 'Dining', 'Transport', 'Health', 'Leisure', 'Gifts', 'Other']) {
    batch.set(ref.collection('categories').doc(name.toLowerCase()), {
      name, archived: false, createdAt: new Date(),
    });
  }
  batch.set(ref.collection('settings').doc('shared'), { runningResetAt: new Date() });
  batch.set(db.doc('membershipIndex/newowner'), {
    uid: 'newowner', householdId: 'newowner',
  });
  await assertSucceeds(batch.commit());
});

test('ownership transfer is atomic and only the owner can initiate it', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc('membershipIndex/owner').set({ uid: 'owner', householdId: household });
    await db.doc('membershipIndex/member').set({ uid: 'member', householdId: household });
  });
  const member = auth('member');
  await assertFails(member.doc(`${root()}/members/member`).update({ role: 'owner' }));
  const owner = auth('owner');
  const batch = owner.batch();
  batch.update(owner.doc(root()), { ownerId: 'member', updatedAt: new Date() });
  batch.update(owner.doc(`${root()}/members/owner`), { role: 'member' });
  batch.update(owner.doc(`${root()}/members/member`), { role: 'owner' });
  await assertSucceeds(batch.commit());
  const home = await owner.doc(root()).get();
  assert.equal(home.data().ownerId, 'member');
  await assertFails(owner.doc(`${root()}/budgets/food`).set({
    categoryId: 'food', currency: 'RSD', amountCents: 1000,
  }));
  await assertSucceeds(member.doc(`${root()}/budgets/food`).set({
    categoryId: 'food', currency: 'RSD', amountCents: 1000,
  }));
});

test('a member can leave atomically, while the owner cannot leave', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc('membershipIndex/member').set({ uid: 'member', householdId: household });
    await db.doc('membershipIndex/owner').set({ uid: 'owner', householdId: household });
  });
  const owner = auth('owner');
  const denied = owner.batch();
  denied.delete(owner.doc(`${root()}/members/owner`));
  denied.delete(owner.doc('membershipIndex/owner'));
  await assertFails(denied.commit());
  const member = auth('member');
  const leaving = member.batch();
  leaving.delete(member.doc(`${root()}/members/member`));
  leaving.delete(member.doc('membershipIndex/member'));
  await assertSucceeds(leaving.commit());
  await assertFails(member.doc(root()).get());
});

test('former owner can transfer, leave, then create another household', async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await db.doc('membershipIndex/owner').set({ uid: 'owner', householdId: household });
    await db.doc('membershipIndex/member').set({ uid: 'member', householdId: household });
  });
  const owner = auth('owner');
  const transfer = owner.batch();
  transfer.update(owner.doc(root()), { ownerId: 'member', updatedAt: new Date() });
  transfer.update(owner.doc(`${root()}/members/owner`), { role: 'member' });
  transfer.update(owner.doc(`${root()}/members/member`), { role: 'owner' });
  await assertSucceeds(transfer.commit());
  const leave = owner.batch();
  leave.delete(owner.doc(`${root()}/members/owner`));
  leave.delete(owner.doc('membershipIndex/owner'));
  await assertSucceeds(leave.commit());
  const next = owner.doc('households/another-household');
  const create = owner.batch();
  create.set(next, {
    name: 'Another household', baseCurrency: 'EUR', ownerId: 'owner',
    createdAt: new Date(), updatedAt: new Date(),
  });
  create.set(next.collection('members').doc('owner'), {
    uid: 'owner', displayName: 'Owner', role: 'owner', status: 'active', joinedAt: new Date(),
  });
  create.set(owner.doc('membershipIndex/owner'), {
    uid: 'owner', householdId: 'another-household',
  });
  await assertSucceeds(create.commit());
});

const template = () => ({
  name: 'Rent', categoryId: 'home', amountCents: 100000,
  currency: 'EUR', dueDay: 5, graceDays: 3, isShared: true,
  startMonth: testMonth, archived: false,
  createdAt: new Date(), updatedAt: new Date(),
});

test('only owner manages recurring templates and values are validated', async () => {
  const owner = auth('owner');
  const member = auth('member');
  const ref = `${root()}/recurringTemplates/rent`;
  await assertFails(member.doc(ref).set(template()));
  await assertFails(owner.doc(ref).set({ ...template(), dueDay: 31 }));
  await assertSucceeds(owner.doc(ref).set(template()));
  await assertFails(member.doc(ref).update({ amountCents: 200000 }));
  await assertSucceeds(owner.doc(ref).update({ amountCents: 110000 }));
  await assertFails(owner.doc(ref).update({ startMonth: futureTestMonth }));
});

const period = () => ({ version: 2, recurringId: 'rent', month: testMonth,
  name: 'Rent', expectedAmountCents: 100000, categoryId: 'home', currency: 'EUR',
  isShared: true, dueDay: 5, graceDays: 3, createdAt: new Date(), updatedAt: new Date() });
const linked = (author = 'member', amount = 40000) => ({ ...expense(author),
  amountCents: amount, baseAmountCents: amount, categoryId: 'home', currency: 'EUR',
  recurringId: 'rent', recurringMonth: testMonth });
async function seedRecurring() {
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await db.doc(`${root()}/recurringTemplates/rent`).set(template());
    await db.doc(`${root()}/categories/home`).set({ name: 'Home', archived: false });
    await db.doc(`${root()}/categories/dining`).set({ name: 'Dining', archived: false });
  });
}

test('several authors can record partial payments; monthly expectation is immutable', async () => {
  await seedRecurring();
  const db = auth('member');
  const plan = db.doc(`${root()}/recurringOccurrences/rent_${testMonth}`);
  await assertFails(db.doc(`${root()}/expenses/one`).set(linked()));
  await assertFails(plan.set({ ...period(), expectedAmountCents: 1 }));
  await assertSucceeds(plan.set(period()));
  await Promise.all([assertSucceeds(db.doc(`${root()}/expenses/one`).set(linked())),
    assertSucceeds(auth('owner').doc(`${root()}/expenses/two`).set(linked('owner', 60000)))]);
  await assertSucceeds(db.doc(`${root()}/expenses/three`).set(linked('member', 10000)));
  await assertFails(plan.update({ expectedAmountCents: 200000 }));
  await assertFails(auth('owner').doc(plan.path).update({ expectedAmountCents: 200000 }));
  await assertFails(plan.delete());
  await assertFails(auth('outsider').doc(plan.path).get());
});

test('link validation rejects wrong category, currency, sharing and nonexistent periods', async () => {
  await seedRecurring(); const db = auth('member');
  await db.doc(`${root()}/recurringOccurrences/rent_${testMonth}`).set(period());
  const ref = db.doc(`${root()}/expenses/bad`);
  await assertFails(ref.set({ ...linked(), categoryId: 'dining' }));
  await assertFails(ref.set({ ...linked(), currency: 'RSD' }));
  await assertFails(ref.set({ ...linked(), isShared: false }));
  await assertFails(ref.set({ ...linked(), recurringMonth: futureTestMonth }));
  await assertFails(ref.set({ ...linked(), recurringMonth: '2026-99' }));
});

test('unlink and delete payments preserve the monthly plan; authors cannot edit others', async () => {
  await seedRecurring(); const db = auth('member');
  const plan = db.doc(`${root()}/recurringOccurrences/rent_${testMonth}`); await plan.set(period());
  const one = db.doc(`${root()}/expenses/one`); const two = db.doc(`${root()}/expenses/two`);
  await one.set(linked()); await two.set(linked('member', 60000));
  await assertSucceeds(one.update({ amountCents: 30000, baseAmountCents: 30000 }));
  await assertSucceeds(two.update({ recurringId: deleteField(), recurringMonth: deleteField() }));
  await assertFails(auth('owner').doc(one.path).delete());
  await assertSucceeds(one.delete());
  assert.equal((await plan.get()).exists, true);
  const payments = await db.collection(`${root()}/expenses`).where('recurringMonth', '==', testMonth).get();
  assert.equal(payments.size, 0);
  assert.equal((await two.get()).data().amountCents, 60000);
});

test('owner correction updates current linked payments atomically but cannot touch another author', async () => {
  await seedRecurring(); const db = auth('owner');
  const plan = db.doc(`${root()}/recurringOccurrences/rent_${testMonth}`); await plan.set(period());
  const one = db.doc(`${root()}/expenses/one`); await one.set(linked('owner'));
  await assertFails(auth('member').doc(plan.path).update({ categoryId: 'dining' }));
  const batch = db.batch(); batch.update(plan, { categoryId: 'dining', updatedAt: new Date() });
  batch.update(one, { categoryId: 'dining', updatedAt: new Date() }); await assertSucceeds(batch.commit());
  assert.equal((await one.get()).data().categoryId, 'dining');
  await assertSucceeds(one.update({ description: 'Corrected' }));
  await assertFails(plan.update({ currency: 'RSD' }));
  await assertFails(plan.update({ categoryId: 'missing' }));
  await assertSucceeds(auth('member').doc(`${root()}/expenses/member`).set({ ...linked(), categoryId: 'dining' }));
  const denied = db.batch(); denied.update(plan, { categoryId: 'home' });
  denied.update(db.doc(`${root()}/expenses/member`), { categoryId: 'home' });
  await assertFails(denied.commit());
  assert.equal((await plan.get()).data().categoryId, 'dining');
});

test('template edits leave existing monthly expectations and linked expenses unchanged', async () => {
  await seedRecurring(); const db = auth('owner');
  const plan = db.doc(`${root()}/recurringOccurrences/rent_${testMonth}`); await plan.set(period());
  await db.doc(`${root()}/expenses/one`).set(linked('owner'));
  await db.doc(`${root()}/recurringTemplates/rent`).update({ amountCents: 200000, categoryId: 'dining' });
  assert.equal((await plan.get()).data().expectedAmountCents, 100000);
  await assertSucceeds(db.doc(`${root()}/expenses/one`).update({ description: 'Still editable' }));
  await assertSucceeds(db.doc(`${root()}/expenses/two`).set(linked('owner', 60000)));
  await assertFails(db.doc(`${root()}/recurringOccurrences/rent_${futureTestMonth}`).set({
    ...period(), month: futureTestMonth, expectedAmountCents: 200000, categoryId: 'dining' }));
});

test('legacy monthly record upgrades without copying or changing the existing payment', async () => {
  await seedRecurring();
  await env.withSecurityRulesDisabled(async context => { const db = context.firestore();
    await db.doc(`${root()}/expenses/old`).set({ ...linked(), categoryId: 'dining' });
    await db.doc(`${root()}/recurringOccurrences/rent_${testMonth}`).set({ recurringId: 'rent', month: testMonth,
      expenseId: 'old', authorId: 'member', createdAt: new Date(1000) });
  });
  const db = auth('member'); const plan = db.doc(`${root()}/recurringOccurrences/rent_${testMonth}`);
  await assertFails(plan.set({ ...period(), categoryId: 'dining', expectedAmountCents: 1, createdAt: new Date(1000) }));
  await assertSucceeds(plan.set({ ...period(), categoryId: 'dining', createdAt: new Date(1000) }));
  assert.equal((await db.collection(`${root()}/expenses`).get()).size, 1);
  assert.equal((await db.doc(`${root()}/expenses/old`).get()).data().categoryId, 'dining');
  await assertSucceeds(db.doc(`${root()}/expenses/old`).delete());
  assert.equal((await plan.get()).exists, true);
});

test('linked expense can be deleted when its occurrence is already missing', async () => {
  await env.withSecurityRulesDisabled(async context => {
    await context.firestore().doc(`${root()}/expenses/orphaned_payment`).set({
      ...expense('member'), recurringId: 'rent', recurringMonth: testMonth,
    });
  });
  const db = auth('member');
  const legacy = db.batch();
  legacy.delete(db.doc(`${root()}/expenses/orphaned_payment`));
  legacy.delete(db.doc(`${root()}/recurringOccurrences/rent_${testMonth}`));
  await assertFails(legacy.commit());
  await assertSucceeds(db.doc(`${root()}/expenses/orphaned_payment`).delete());
  const removed = await db.doc(`${root()}/expenses/orphaned_payment`).get();
  assert.equal(removed.exists, false);
});

test('previous single-payment client can still create its atomic legacy payment', async () => {
  await seedRecurring(); const db = auth('member'); const batch = db.batch();
  batch.set(db.doc(`${root()}/expenses/old_client`), linked());
  batch.set(db.doc(`${root()}/recurringOccurrences/rent_${testMonth}`), { recurringId: 'rent', month: testMonth,
    expenseId: 'old_client', authorId: 'member', createdAt: new Date() });
  await assertSucceeds(batch.commit());
  await assertFails(db.doc(`${root()}/expenses/unrelated`).set(linked()));
});

test('members cannot freeze future periods and owner cannot reclassify earlier monthly snapshots', async () => {
  await seedRecurring(); const db = auth('owner');
  await env.withSecurityRulesDisabled(async context => {
    await context.firestore().doc(`${root()}/recurringTemplates/rent`).update({ startMonth: previousTestMonth });
  });
  const old = db.doc(`${root()}/recurringOccurrences/rent_${previousTestMonth}`);
  await assertSucceeds(old.set({ ...period(), month: previousTestMonth }));
  await assertFails(old.update({ categoryId: 'dining' }));
  await assertFails(auth('member').doc(`${root()}/recurringOccurrences/rent_2099-01`).set({ ...period(), month: '2099-01' }));
});

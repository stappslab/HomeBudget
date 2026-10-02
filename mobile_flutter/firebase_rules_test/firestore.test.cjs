const { before, beforeEach, after, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');

let env;
const household = 'household-one';
const root = () => `households/${household}`;
const auth = (uid) => env.authenticatedContext(uid, {
  email: `${uid}@example.com`, email_verified: true,
}).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'homebudget-rules-test',
    firestore: {
      host: '127.0.0.1', port: 8080,
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

import test from 'node:test';
import assert from 'node:assert/strict';

process.env.RELAY_DB_PATH = ':memory:';
const { store } = await import('../src/db.js');

test('1 token = 1 member: second member replaces first', () => {
  store.registerDevice({ memberId: 'A', deviceToken: 'tok1', platform: 'ios' });
  store.registerDevice({ memberId: 'B', deviceToken: 'tok1', platform: 'ios' });
  assert.deepEqual(store.devicesForMember('A'), []);
  assert.equal(store.devicesForMember('B').length, 1);
  // 同一会員の再登録は重複しない / 別端末は共存
  store.registerDevice({ memberId: 'B', deviceToken: 'tok1', platform: 'ios' });
  store.registerDevice({ memberId: 'B', deviceToken: 'tok2', platform: 'android' });
  assert.equal(store.devicesForMember('B').length, 2);
});

test('unregister removes token (with and without memberId)', () => {
  store.registerDevice({ memberId: 'C', deviceToken: 'tokC', platform: 'ios' });
  assert.equal(store.unregisterDevice({ deviceToken: 'tokC', memberId: 'other' }), 0);
  assert.equal(store.devicesForMember('C').length, 1);
  assert.equal(store.unregisterDevice({ deviceToken: 'tokC', memberId: 'C' }), 1);
  store.registerDevice({ memberId: 'C', deviceToken: 'tokC', platform: 'ios' });
  assert.equal(store.unregisterDevice({ deviceToken: 'tokC' }), 1);
  assert.deepEqual(store.devicesForMember('C'), []);
});

test('processed events: not marked until markEventProcessed; retention cleanup', () => {
  assert.equal(store.isEventProcessed('ev1'), false);
  assert.equal(store.isEventProcessed('ev1'), false); // 確認だけでは記録されない
  store.markEventProcessed('ev1');
  assert.equal(store.isEventProcessed('ev1'), true);
  assert.equal(store.cleanupProcessedEvents(30), 0);
  assert.equal(store.cleanupProcessedEvents(30, Date.now() + 31 * 86400 * 1000), 1);
  assert.equal(store.isEventProcessed('ev1'), false);
});

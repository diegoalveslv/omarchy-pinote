const test = require("node:test")
const assert = require("node:assert/strict")
const Queue = require("../NotesStoreQueue.js")

function snapshot(revision) {
  return { revision, payload: `snapshot-${revision}` }
}

test("the first primary snapshot starts immediately", () => {
  const first = snapshot(1)
  const result = Queue.enqueuePrimary(Queue.emptyState(), first, false)

  assert.equal(result.writePrimary, first)
  assert.equal(result.state.activePrimary, first)
  assert.equal(result.state.queuedPrimary, null)
})

test("rapid primary commits retain only the active and latest snapshots", () => {
  let state = Queue.enqueuePrimary(Queue.emptyState(), snapshot(1), false).state
  for (let revision = 2; revision <= 10; revision++)
    state = Queue.enqueuePrimary(state, snapshot(revision), false).state

  assert.equal(state.activePrimary.revision, 1)
  assert.equal(state.queuedPrimary.revision, 10)
})

test("primary success confirms the active payload and starts the latest queued payload", () => {
  const first = snapshot(1)
  const latest = snapshot(3)
  let state = Queue.enqueuePrimary(Queue.emptyState(), first, false).state
  state = Queue.enqueuePrimary(state, snapshot(2), false).state
  state = Queue.enqueuePrimary(state, latest, false).state
  const result = Queue.primarySaved(state)

  assert.equal(result.confirmedPrimary, first)
  assert.equal(result.writePrimary, latest)
  assert.equal(result.writeBackup, first)
  assert.equal(result.state.activePrimary, latest)
  assert.equal(result.state.activeBackup, first)
})

test("primary success logically confirms a queued payload already on disk", () => {
  const first = { revision: 1, payload: "same" }
  const reverted = { revision: 3, payload: "same" }
  let state = Queue.enqueuePrimary(Queue.emptyState(), first, false).state
  state = Queue.enqueuePrimary(state, { revision: 2, payload: "different" }, false).state
  state = Queue.enqueuePrimary(state, reverted, false).state
  const result = Queue.primarySaved(state, "same")

  assert.equal(result.confirmedPrimary, reverted)
  assert.equal(result.writePrimary, null)
  assert.equal(result.state.activePrimary, null)
  assert.equal(result.state.activeBackup, first)
  assert.equal(result.state.queuedBackup, reverted)
})

test("primary failure retains the newest complete snapshot for retry", () => {
  const first = snapshot(1)
  const latest = snapshot(4)
  let state = Queue.enqueuePrimary(Queue.emptyState(), first, false).state
  state = Queue.enqueuePrimary(state, latest, false).state
  const failed = Queue.primaryFailed(state)

  assert.equal(failed.failedPrimary, first)
  assert.equal(failed.state.retryPrimary, latest)
  assert.equal(failed.state.activePrimary, null)

  const retried = Queue.retryPrimary(failed.state)
  assert.equal(retried.writePrimary, latest)
  assert.equal(retried.state.retryPrimary, null)
})

test("a commit during save-error replaces the retry snapshot without starting a write", () => {
  let state = Queue.enqueuePrimary(Queue.emptyState(), snapshot(1), false).state
  state = Queue.primaryFailed(state).state
  const latest = snapshot(2)
  const result = Queue.enqueuePrimary(state, latest, true)

  assert.equal(result.writePrimary, null)
  assert.equal(result.state.retryPrimary, latest)
})

test("backup writes receive only primary-confirmed snapshots", () => {
  const first = snapshot(1)
  let state = Queue.enqueuePrimary(Queue.emptyState(), first, false).state
  const saved = Queue.primarySaved(state)

  assert.equal(saved.writeBackup, first)
  assert.equal(saved.writeBackup.payload, saved.confirmedPrimary.payload)
})

test("backup writes coalesce to the newest confirmed snapshot", () => {
  let state = Queue.enqueuePrimary(Queue.emptyState(), snapshot(1), false).state
  let result = Queue.primarySaved(state)
  state = result.state

  state = Queue.enqueuePrimary(state, snapshot(2), false).state
  state = Queue.enqueuePrimary(state, snapshot(3), false).state
  result = Queue.primarySaved(state)
  state = result.state
  result = Queue.primarySaved(state)
  state = result.state

  assert.equal(state.activeBackup.revision, 1)
  assert.equal(state.queuedBackup.revision, 3)

  result = Queue.backupSaved(state)
  assert.equal(result.confirmedBackup.revision, 1)
  assert.equal(result.writeBackup.revision, 3)
})

test("backup success logically confirms a queued payload already on disk", () => {
  const first = { revision: 1, payload: "same" }
  const latest = { revision: 3, payload: "same" }
  let state = Queue.enqueuePrimary(Queue.emptyState(), first, false).state
  state = Queue.primarySaved(state).state
  state = Queue.enqueuePrimary(state, latest, false).state
  state = Queue.primarySaved(state).state
  const result = Queue.backupSaved(state, "same")

  assert.equal(result.confirmedBackup, latest)
  assert.equal(result.writeBackup, null)
  assert.equal(result.state.activeBackup, null)
})

test("backup failure preserves primary state and permits explicit retry", () => {
  let state = Queue.enqueuePrimary(Queue.emptyState(), snapshot(1), false).state
  state = Queue.primarySaved(state).state
  const failed = Queue.backupFailed(state)

  assert.equal(failed.failedBackup.revision, 1)
  assert.equal(failed.state.retryBackup.revision, 1)
  assert.equal(failed.state.activePrimary, null)

  const retried = Queue.retryBackup(failed.state)
  assert.equal(retried.writeBackup.revision, 1)
})

test("a newer confirmed snapshot supersedes an older failed backup", () => {
  let state = Queue.enqueuePrimary(Queue.emptyState(), snapshot(1), false).state
  state = Queue.primarySaved(state).state
  state = Queue.backupFailed(state).state
  state = Queue.enqueuePrimary(state, snapshot(2), false).state
  const result = Queue.primarySaved(state)

  assert.equal(result.writeBackup.revision, 2)
  assert.equal(result.state.retryBackup, null)
})

test("queue transitions do not mutate their input state", () => {
  const original = Queue.emptyState()
  const before = structuredClone(original)
  Queue.enqueuePrimary(original, snapshot(1), false)
  assert.deepEqual(original, before)
})

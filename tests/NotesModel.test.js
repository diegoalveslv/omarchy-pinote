const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../NotesModel.js")

const CREATED = "2026-09-09T12:00:00.000Z"
const UPDATED = "2026-09-10T12:00:00.000Z"

function note(overrides = {}) {
  return {
    id: "note-1",
    content: "Example note",
    createdAt: CREATED,
    updatedAt: CREATED,
    ...overrides
  }
}

function document(notes, overrides = {}) {
  return JSON.stringify({ version: 1, notes, ...overrides })
}

function issueCodes(result) {
  return result.issues.map(value => value.code)
}

test("missing and blank input produce an empty writable collection", () => {
  for (const input of [undefined, null, "", " \n\t "]) {
    assert.deepEqual(Model.parse(input), {
      status: "ready",
      collection: { version: 1, notes: [] },
      issues: []
    })
  }
})

test("malformed and non-object JSON are recoverable", () => {
  assert.deepEqual(issueCodes(Model.parse("{")), ["malformed-json"])
  for (const input of ["null", "[]", "true", "42", '"notes"']) {
    const result = Model.parse(input)
    assert.equal(result.status, "recoverable")
    assert.deepEqual(issueCodes(result), ["invalid-document"])
  }
})

test("missing, string, zero, and otherwise invalid versions are recoverable", () => {
  for (const value of [undefined, "1", 0, -1]) {
    const data = { notes: [] }
    if (value !== undefined) data.version = value
    const result = Model.parse(JSON.stringify(data))
    assert.equal(result.status, "recoverable")
    assert.deepEqual(issueCodes(result), ["invalid-version"])
  }
})

test("future numeric versions are unsupported regardless of their remaining shape", () => {
  for (const version of [1.5, 2, 99]) {
    const result = Model.parse(JSON.stringify({ version, notes: "unknown future shape" }))
    assert.equal(result.status, "unsupported")
    assert.equal(result.version, version)
    assert.equal(result.collection, null)
    assert.deepEqual(issueCodes(result), ["unsupported-version"])
  }
})

test("missing and non-array notes values are recoverable", () => {
  for (const notes of [undefined, null, {}, "notes", 1]) {
    const data = { version: 1 }
    if (notes !== undefined) data.notes = notes
    const result = Model.parse(JSON.stringify(data))
    assert.equal(result.status, "recoverable")
    assert.deepEqual(issueCodes(result), ["invalid-notes"])
  }
})

test("valid records are normalized and unknown fields are omitted", () => {
  const input = note({ ignored: "value" })
  const result = Model.parse(document([input], { ignoredTopLevel: true }))

  assert.equal(result.status, "ready")
  assert.deepEqual(result.collection.notes, [note()])
  assert.notEqual(result.collection.notes[0], input)
})

test("serialization is deterministic, canonical, and newline terminated", () => {
  const collection = { version: 99, notes: [note({ ignored: true })], ignored: true }
  const expected = [
    "{",
    '  "version": 1,',
    '  "notes": [',
    "    {",
    '      "id": "note-1",',
    '      "content": "Example note",',
    '      "createdAt": "2026-09-09T12:00:00.000Z",',
    '      "updatedAt": "2026-09-09T12:00:00.000Z"',
    "    }",
    "  ]",
    "}",
    ""
  ].join("\n")

  assert.equal(Model.serializeCollection(collection), expected)
  assert.deepEqual(Model.parse(expected).collection, { version: 1, notes: [note()] })
})

test("invalid record shapes and fields produce stable issue codes", () => {
  const records = [
    null,
    [],
    {},
    note({ id: "" }),
    note({ id: 1 }),
    note({ id: "wrong-content", content: 1 }),
    note({ id: "blank", content: " \n " }),
    note({ id: "created", createdAt: "not-a-date" }),
    note({ id: "updated", updatedAt: "2026-09-09T12:00:00Z" })
  ]
  const result = Model.parse(document(records))

  assert.equal(result.status, "recoverable")
  assert.deepEqual(issueCodes(result), [
    "invalid-record",
    "invalid-record",
    "invalid-id",
    "invalid-content-type",
    "invalid-created-at",
    "invalid-updated-at",
    "invalid-id",
    "invalid-id",
    "invalid-content-type",
    "empty-content",
    "invalid-created-at",
    "invalid-updated-at"
  ])
})

test("timestamps must use canonical UTC ISO-8601 form", () => {
  assert.equal(Model.isCanonicalTimestamp("2024-02-29T23:59:59.999Z"), true)
  for (const value of [
    "2023-02-29T00:00:00.000Z",
    "2026-09-09T12:00:00Z",
    "2026-09-09T12:00:00.000+00:00",
    "2026-9-9T12:00:00.000Z",
    0,
    null
  ]) assert.equal(Model.isCanonicalTimestamp(value), false)
})

test("duplicate IDs enter recovery and retain only the first valid record", () => {
  const first = note()
  const duplicate = note({ content: "Duplicate" })
  const result = Model.parse(document([first, duplicate]))

  assert.equal(result.status, "recoverable")
  assert.deepEqual(issueCodes(result), ["duplicate-id"])
  assert.deepEqual(result.collection.notes, [first])
})

test("an invalid record does not suppress a later valid note with the same ID", () => {
  const invalid = note({ content: "" })
  const valid = note({ content: "Preserved note" })
  const result = Model.parse(document([invalid, valid]))

  assert.equal(result.status, "recoverable")
  assert.deepEqual(issueCodes(result), ["empty-content", "duplicate-id"])
  assert.deepEqual(result.collection.notes, [valid])
})

test("duplicate detection handles IDs that are JavaScript object property names", () => {
  for (const id of ["__proto__", "constructor", "toString"]) {
    const first = note({ id })
    const result = Model.parse(document([first, note({ id, content: "Duplicate" })]))
    assert.equal(result.status, "recoverable")
    assert.deepEqual(issueCodes(result), ["duplicate-id"])
    assert.deepEqual(result.collection.notes, [first])
  }
})

test("a mixture of valid and invalid records exposes a recovery preview", () => {
  const valid = note()
  const invalid = note({ id: "note-2", content: "" })
  const result = Model.parse(document([valid, invalid]))

  assert.equal(result.status, "recoverable")
  assert.deepEqual(result.collection.notes, [valid])
  assert.deepEqual(issueCodes(result), ["empty-content"])
})

test("every parser outcome maps to a persistence state", () => {
  assert.equal(Model.persistenceStateForParseResult(Model.parse("")), "ready")
  assert.equal(Model.persistenceStateForParseResult(Model.parse("{")), "recovery")
  assert.equal(Model.persistenceStateForParseResult(Model.parse('{"version":2}')), "unsupported")
  assert.equal(Model.persistenceStateForParseResult(null), "recovery")
})

test("Unicode content limits count code points rather than UTF-16 units", () => {
  assert.equal(Model.unicodeLength("a😀b"), 3)
  const accepted = "😀".repeat(Model.MAX_CONTENT_CHARACTERS)
  const created = Model.createNote(Model.emptyCollection(), accepted, CREATED, () => "unicode")
  assert.equal(created.ok, true)

  const rejected = Model.createNote(Model.emptyCollection(), accepted + "a", CREATED, () => "too-long")
  assert.equal(rejected.ok, false)
  assert.deepEqual(issueCodes(rejected), ["content-too-long"])
})

test("UTF-8 byte counting handles ASCII, multibyte text, and surrogate pairs", () => {
  assert.equal(Model.utf8ByteLength("plain"), 5)
  assert.equal(Model.utf8ByteLength("café"), 5)
  assert.equal(Model.utf8ByteLength("😀"), 4)
  assert.equal(Model.utf8ByteLength("a😀é"), Buffer.byteLength("a😀é", "utf8"))
})

test("JSON string byte counting matches serialization without allocating a quoted copy", () => {
  for (const value of ["plain", 'quote"slash\\', "line\nfeed", "café", "😀", "\ud800"])
    assert.equal(Model.jsonStringByteLength(value), Buffer.byteLength(JSON.stringify(value), "utf8"))
})

test("create is immutable and assigns stable creation and update timestamps", () => {
  const originalNote = note()
  const original = { version: 1, notes: [originalNote] }
  const result = Model.createNote(original, "Second note", UPDATED, () => "note-2")

  assert.equal(result.ok, true)
  assert.deepEqual(original, { version: 1, notes: [originalNote] })
  assert.notEqual(result.collection, original)
  assert.notEqual(result.collection.notes, original.notes)
  assert.deepEqual(result.note, {
    id: "note-2",
    content: "Second note",
    createdAt: UPDATED,
    updatedAt: UPDATED
  })
})

test("create rejects blank content and invalid timestamps without mutation", () => {
  const original = { version: 1, notes: [note()] }
  assert.deepEqual(issueCodes(Model.createNote(original, " \n", UPDATED, () => "note-2")), ["empty-content"])
  assert.deepEqual(issueCodes(Model.createNote(original, "Valid", "today", () => "note-2")), ["invalid-timestamp"])
  assert.equal(original.notes.length, 1)
})

test("ID generation retries collisions and rejects missing or exhausted generators", () => {
  const collection = { version: 1, notes: [note()] }
  const candidates = ["note-1", "note-1", "note-2"]
  const generated = Model.generateUniqueId(collection, attempt => candidates[attempt])
  assert.deepEqual(generated, { ok: true, id: "note-2" })

  assert.deepEqual(issueCodes(Model.generateUniqueId(collection)), ["missing-id-generator"])
  assert.deepEqual(issueCodes(Model.generateUniqueId(collection, () => "note-1")), ["id-collision"])
  assert.deepEqual(issueCodes(Model.generateUniqueId(collection, () => { throw new Error("failed") })), ["id-generation-failed"])
})

test("update preserves identity and creation time while replacing update time", () => {
  const originalNote = note()
  const original = { version: 1, notes: [originalNote] }
  const result = Model.updateNote(original, "note-1", "Edited", UPDATED)

  assert.equal(result.ok, true)
  assert.deepEqual(result.note, {
    id: "note-1",
    content: "Edited",
    createdAt: CREATED,
    updatedAt: UPDATED
  })
  assert.deepEqual(original.notes, [originalNote])
  assert.notEqual(result.collection.notes, original.notes)
})

test("update and delete reject missing IDs without changing committed state", () => {
  const original = { version: 1, notes: [note()] }
  assert.deepEqual(issueCodes(Model.updateNote(original, "missing", "Edited", UPDATED)), ["note-not-found"])
  assert.deepEqual(issueCodes(Model.deleteNote(original, "missing")), ["note-not-found"])
  assert.deepEqual(original, { version: 1, notes: [note()] })
})

test("delete is immutable and returns the removed note", () => {
  const first = note()
  const second = note({ id: "note-2" })
  const original = { version: 1, notes: [first, second] }
  const result = Model.deleteNote(original, "note-1")

  assert.equal(result.ok, true)
  assert.deepEqual(result.note, first)
  assert.deepEqual(result.collection.notes, [second])
  assert.deepEqual(original.notes, [first, second])
})

test("newest-first sorting is separate, stable, and non-mutating", () => {
  const oldest = note({ id: "oldest", updatedAt: CREATED })
  const newest = note({ id: "newest", updatedAt: UPDATED })
  const tied = note({ id: "tied", updatedAt: UPDATED })
  const collection = { version: 1, notes: [oldest, newest, tied] }

  assert.deepEqual(Model.newestFirst(collection).map(value => value.id), ["newest", "tied", "oldest"])
  assert.deepEqual(collection.notes.map(value => value.id), ["oldest", "newest", "tied"])
})

test("the note-count boundary is accepted and the next create is rejected", () => {
  const notes = []
  for (let i = 0; i < Model.MAX_NOTES; i++) notes.push(note({ id: `note-${i}` }))
  const collection = { version: 1, notes }

  assert.equal(Model.parse(Model.serializeCollection(collection)).status, "ready")
  const result = Model.createNote(collection, "One too many", UPDATED, () => "overflow")
  assert.equal(result.ok, false)
  assert.deepEqual(issueCodes(result), ["too-many-notes"])
})

test("an over-limit persisted collection enters recovery", () => {
  const notes = []
  for (let i = 0; i <= Model.MAX_NOTES; i++) notes.push(note({ id: `note-${i}` }))
  const result = Model.parse(document(notes))

  assert.equal(result.status, "recoverable")
  assert.ok(issueCodes(result).includes("too-many-notes"))
})

test("mutations reject a snapshot whose UTF-8 serialization exceeds 10 MiB", () => {
  const notes = []
  const content = "😀".repeat(Model.MAX_CONTENT_CHARACTERS)
  for (let i = 0; i < 163; i++) notes.push(note({ id: `large-${i}`, content }))
  const collection = { version: 1, notes }
  assert.ok(Model.utf8ByteLength(Model.serializeCollection(collection)) < Model.MAX_CANONICAL_BYTES)

  const result = Model.createNote(collection, content, UPDATED, () => "large-final")
  assert.equal(result.ok, false)
  assert.deepEqual(issueCodes(result), ["file-too-large"])
  assert.equal(collection.notes.length, 163)
})

test("the total file-size limit takes precedence over the content limit", () => {
  const content = "😀".repeat(3_000_000)
  const result = Model.createNote(Model.emptyCollection(), content, CREATED, () => "oversized")

  assert.equal(result.ok, false)
  assert.deepEqual(issueCodes(result), ["file-too-large"])
})

test("persisted file-size issues precede record-level limit issues", () => {
  const content = "😀".repeat(3_000_000)
  const result = Model.parse(document([note({ content })]))

  assert.equal(result.status, "recoverable")
  assert.equal(issueCodes(result)[0], "file-too-large")
  assert.ok(issueCodes(result).includes("content-too-long"))
})

test("every successful mutation serializes to a ready collection", () => {
  const created = Model.createNote(Model.emptyCollection(), "Created", CREATED, () => "round-trip")
  assert.equal(Model.parse(Model.serializeCollection(created.collection)).status, "ready")

  const updated = Model.updateNote(created.collection, "round-trip", "Updated", UPDATED)
  assert.equal(Model.parse(Model.serializeCollection(updated.collection)).status, "ready")

  const deleted = Model.deleteNote(updated.collection, "round-trip")
  assert.equal(Model.parse(Model.serializeCollection(deleted.collection)).status, "ready")
})

test("an oversized canonical persisted snapshot enters recovery", () => {
  const notes = []
  const content = "😀".repeat(Model.MAX_CONTENT_CHARACTERS)
  for (let i = 0; i < 164; i++) notes.push(note({ id: `large-${i}`, content }))
  const serialized = Model.serializeCollection({ version: 1, notes })
  assert.ok(Model.utf8ByteLength(serialized) > Model.MAX_CANONICAL_BYTES)

  const result = Model.parse(serialized)
  assert.equal(result.status, "recoverable")
  assert.ok(issueCodes(result).includes("file-too-large"))
})

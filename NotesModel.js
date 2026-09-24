var SCHEMA_VERSION = 1
var MAX_NOTES = 500
var MAX_CONTENT_CHARACTERS = 16000
var MAX_CANONICAL_BYTES = 10 * 1024 * 1024
var MAX_ID_ATTEMPTS = 100

function emptyCollection() {
  return { version: SCHEMA_VERSION, notes: [] }
}

function issue(code, path, message) {
  return { code: code, path: path, message: message }
}

function parseResult(status, collection, issues, totalRecords, version) {
  var acceptedRecords = collection && Array.isArray(collection.notes) ? collection.notes.length : 0
  var result = {
    status: status,
    collection: collection,
    issues: issues,
    totalRecords: totalRecords || 0,
    acceptedRecords: acceptedRecords,
    rejectedRecords: Math.max(0, (totalRecords || 0) - acceptedRecords)
  }
  if (version !== undefined) result.version = version
  return result
}

function ready(collection) {
  return parseResult("ready", collection, [], collection.notes.length)
}

function recoverable(collection, issues, totalRecords) {
  return parseResult("recoverable", collection, issues, totalRecords)
}

function unsupported(version) {
  return parseResult("unsupported", null,
    [issue("unsupported-version", "version", "The schema version is newer than this Pinote version supports.")],
    0, version)
}

function persistenceStateForParseResult(result) {
  if (result && result.status === "ready") return "ready"
  if (result && result.status === "unsupported") return "unsupported"
  return "recovery"
}

function unicodeLength(value) {
  var text = String(value)
  var length = 0

  for (var i = 0; i < text.length; i++) {
    var unit = text.charCodeAt(i)
    if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < text.length) {
      var next = text.charCodeAt(i + 1)
      if (next >= 0xdc00 && next <= 0xdfff) i++
    }
    length++
  }

  return length
}

function utf8ByteLength(value) {
  var text = String(value)
  var bytes = 0

  for (var i = 0; i < text.length; i++) {
    var unit = text.charCodeAt(i)
    if (unit <= 0x7f) {
      bytes++
    } else if (unit <= 0x7ff) {
      bytes += 2
    } else if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < text.length) {
      var next = text.charCodeAt(i + 1)
      if (next >= 0xdc00 && next <= 0xdfff) {
        bytes += 4
        i++
      } else {
        bytes += 3
      }
    } else {
      bytes += 3
    }
  }

  return bytes
}

function jsonStringByteLength(value) {
  var text = String(value)
  var bytes = 2

  for (var i = 0; i < text.length; i++) {
    var unit = text.charCodeAt(i)
    if (unit === 0x22 || unit === 0x5c || unit === 0x08 || unit === 0x09
        || unit === 0x0a || unit === 0x0c || unit === 0x0d) {
      bytes += 2
    } else if (unit <= 0x1f) {
      bytes += 6
    } else if (unit <= 0x7f) {
      bytes++
    } else if (unit <= 0x7ff) {
      bytes += 2
    } else if (unit >= 0xd800 && unit <= 0xdbff && i + 1 < text.length) {
      var next = text.charCodeAt(i + 1)
      if (next >= 0xdc00 && next <= 0xdfff) {
        bytes += 4
        i++
      } else {
        bytes += 6
      }
    } else if (unit >= 0xd800 && unit <= 0xdfff) {
      bytes += 6
    } else {
      bytes += 3
    }
  }

  return bytes
}

function isCanonicalTimestamp(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)) return false
  var milliseconds = Date.parse(value)
  return !isNaN(milliseconds) && new Date(milliseconds).toISOString() === value
}

function contentIssue(content, path) {
  if (typeof content !== "string") return issue("invalid-content-type", path, "Note content must be a string.")
  if (content.trim().length === 0) return issue("empty-content", path, "Note content cannot be blank.")
  if (unicodeLength(content) > MAX_CONTENT_CHARACTERS)
    return issue("content-too-long", path, "Note content exceeds the character limit.")
  return null
}

function canonicalNote(note) {
  return {
    id: note.id,
    content: note.content,
    createdAt: note.createdAt,
    updatedAt: note.updatedAt
  }
}

function serializeCollection(collection) {
  var notes = []
  var source = collection && Array.isArray(collection.notes) ? collection.notes : []
  for (var i = 0; i < source.length; i++) notes.push(canonicalNote(source[i]))
  return JSON.stringify({ version: SCHEMA_VERSION, notes: notes }, null, 2) + "\n"
}

function parse(raw) {
  if (raw === undefined || raw === null || String(raw).trim().length === 0) return ready(emptyCollection())

  var data
  try {
    data = JSON.parse(String(raw))
  } catch (error) {
    return recoverable(emptyCollection(), [issue("malformed-json", "$", "The notes file is not valid JSON.")])
  }

  if (!data || typeof data !== "object" || Array.isArray(data))
    return recoverable(emptyCollection(), [issue("invalid-document", "$", "The notes file must contain an object.")])

  if (typeof data.version === "number" && data.version > SCHEMA_VERSION) return unsupported(data.version)
  if (data.version !== SCHEMA_VERSION)
    return recoverable(emptyCollection(), [issue("invalid-version", "version", "The notes file must use schema version 1.")])
  if (!Array.isArray(data.notes))
    return recoverable(emptyCollection(), [issue("invalid-notes", "notes", "The notes field must be an array.")])

  var notes = []
  var sizeNotes = []
  var issues = []
  var seenIds = Object.create(null)
  var acceptedIds = Object.create(null)

  for (var i = 0; i < data.notes.length; i++) {
    var value = data.notes[i]
    var path = "notes[" + i + "]"
    var valid = true

    if (!value || typeof value !== "object" || Array.isArray(value)) {
      issues.push(issue("invalid-record", path, "Each note must be an object."))
      continue
    }

    sizeNotes.push(canonicalNote(value))

    if (typeof value.id !== "string" || value.id.length === 0) {
      issues.push(issue("invalid-id", path + ".id", "A note ID must be a non-empty string."))
      valid = false
    } else if (Object.prototype.hasOwnProperty.call(seenIds, value.id)) {
      issues.push(issue("duplicate-id", path + ".id", "Note IDs must be unique."))
    } else {
      seenIds[value.id] = true
    }

    var invalidContent = contentIssue(value.content, path + ".content")
    if (invalidContent) {
      issues.push(invalidContent)
      valid = false
    }
    if (!isCanonicalTimestamp(value.createdAt)) {
      issues.push(issue("invalid-created-at", path + ".createdAt", "The creation timestamp must be canonical UTC ISO-8601."))
      valid = false
    }
    if (!isCanonicalTimestamp(value.updatedAt)) {
      issues.push(issue("invalid-updated-at", path + ".updatedAt", "The update timestamp must be canonical UTC ISO-8601."))
      valid = false
    }

    if (valid && !Object.prototype.hasOwnProperty.call(acceptedIds, value.id)) {
      notes.push(canonicalNote(value))
      acceptedIds[value.id] = true
    }
  }

  var collection = { version: SCHEMA_VERSION, notes: notes }
  if (data.notes.length > MAX_NOTES)
    issues.push(issue("too-many-notes", "notes", "The notes collection exceeds the note limit."))
  if (utf8ByteLength(serializeCollection({ version: SCHEMA_VERSION, notes: sizeNotes })) > MAX_CANONICAL_BYTES)
    issues.unshift(issue("file-too-large", "$", "The canonical notes file exceeds the size limit."))

  return issues.length > 0 ? recoverable(collection, issues, data.notes.length) : ready(collection)
}

function findNoteIndex(collection, id) {
  var notes = collection && Array.isArray(collection.notes) ? collection.notes : []
  for (var i = 0; i < notes.length; i++) {
    if (notes[i].id === id) return i
  }
  return -1
}

function generateUniqueId(collection, candidateGenerator) {
  if (typeof candidateGenerator !== "function")
    return { ok: false, issues: [issue("missing-id-generator", "id", "An ID generator is required.")] }

  for (var attempt = 0; attempt < MAX_ID_ATTEMPTS; attempt++) {
    var candidate
    try {
      candidate = candidateGenerator(attempt)
    } catch (error) {
      return { ok: false, issues: [issue("id-generation-failed", "id", "The ID generator failed.")] }
    }
    if (typeof candidate === "string" && candidate.length > 0 && findNoteIndex(collection, candidate) === -1)
      return { ok: true, id: candidate }
  }

  return { ok: false, issues: [issue("id-collision", "id", "A unique note ID could not be generated.")] }
}

function validateMutationContent(content) {
  var invalidContent = contentIssue(content, "content")
  return invalidContent ? { ok: false, issues: [invalidContent] } : null
}

function validateMutationTimestamp(timestamp) {
  if (!isCanonicalTimestamp(timestamp))
    return { ok: false, issues: [issue("invalid-timestamp", "timestamp", "A canonical UTC ISO-8601 timestamp is required.")] }
  return null
}

function validateSnapshotSize(collection) {
  if (utf8ByteLength(serializeCollection(collection)) > MAX_CANONICAL_BYTES)
    return { ok: false, issues: [issue("file-too-large", "$", "The canonical notes file exceeds the size limit.")] }
  return null
}

function prospectiveSnapshotByteLength(collection, note, index) {
  var notes = collection && Array.isArray(collection.notes) ? collection.notes.slice() : []
  var placeholder = canonicalNote(note)
  placeholder.content = ""
  if (index < 0) notes.push(placeholder)
  else notes[index] = placeholder

  return utf8ByteLength(serializeCollection({ version: SCHEMA_VERSION, notes: notes }))
    - 2 + jsonStringByteLength(note.content)
}

function createNote(collection, content, timestamp, candidateGenerator) {
  var invalidContent = validateMutationContent(content)
  if (invalidContent && invalidContent.issues[0].code !== "content-too-long") return invalidContent
  var invalidTimestamp = validateMutationTimestamp(timestamp)
  if (invalidTimestamp) return invalidTimestamp

  var notes = collection && Array.isArray(collection.notes) ? collection.notes : []
  var generated = generateUniqueId(collection, candidateGenerator)
  if (!generated.ok) return generated

  var note = { id: generated.id, content: content, createdAt: timestamp, updatedAt: timestamp }
  var nextNotes = notes.slice()
  nextNotes.push(note)
  var nextCollection = { version: SCHEMA_VERSION, notes: nextNotes }
  if (invalidContent) {
    if (prospectiveSnapshotByteLength(collection, note, -1) > MAX_CANONICAL_BYTES)
      return { ok: false, issues: [issue("file-too-large", "$", "The canonical notes file exceeds the size limit.")] }
    return invalidContent
  }
  var oversized = validateSnapshotSize(nextCollection)
  if (oversized) return oversized
  if (notes.length >= MAX_NOTES)
    return { ok: false, issues: [issue("too-many-notes", "notes", "The notes collection has reached its note limit.")] }
  return { ok: true, collection: nextCollection, note: note }
}

function updateNote(collection, id, content, timestamp) {
  var index = findNoteIndex(collection, id)
  if (index === -1)
    return { ok: false, issues: [issue("note-not-found", "id", "The note does not exist.")] }
  var invalidContent = validateMutationContent(content)
  if (invalidContent && invalidContent.issues[0].code !== "content-too-long") return invalidContent
  var invalidTimestamp = validateMutationTimestamp(timestamp)
  if (invalidTimestamp) return invalidTimestamp

  var previous = collection.notes[index]
  var note = {
    id: previous.id,
    content: content,
    createdAt: previous.createdAt,
    updatedAt: timestamp
  }
  var nextNotes = collection.notes.slice()
  nextNotes[index] = note
  var nextCollection = { version: SCHEMA_VERSION, notes: nextNotes }
  if (invalidContent) {
    if (prospectiveSnapshotByteLength(collection, note, index) > MAX_CANONICAL_BYTES)
      return { ok: false, issues: [issue("file-too-large", "$", "The canonical notes file exceeds the size limit.")] }
    return invalidContent
  }
  var oversized = validateSnapshotSize(nextCollection)
  if (oversized) return oversized
  return { ok: true, collection: nextCollection, note: note }
}

function deleteNote(collection, id) {
  var index = findNoteIndex(collection, id)
  if (index === -1)
    return { ok: false, issues: [issue("note-not-found", "id", "The note does not exist.")] }

  var nextNotes = collection.notes.slice()
  var deleted = nextNotes.splice(index, 1)[0]
  return {
    ok: true,
    collection: { version: SCHEMA_VERSION, notes: nextNotes },
    note: deleted
  }
}

function newestFirst(collection) {
  var notes = collection && Array.isArray(collection.notes) ? collection.notes : []
  var indexed = []
  for (var i = 0; i < notes.length; i++) indexed.push({ note: notes[i], index: i })
  indexed.sort(function(left, right) {
    var difference = Date.parse(right.note.updatedAt) - Date.parse(left.note.updatedAt)
    return difference === 0 ? left.index - right.index : difference
  })

  var sorted = []
  for (var j = 0; j < indexed.length; j++) sorted.push(indexed[j].note)
  return sorted
}

if (typeof module !== "undefined") {
  module.exports = {
    SCHEMA_VERSION: SCHEMA_VERSION,
    MAX_NOTES: MAX_NOTES,
    MAX_CONTENT_CHARACTERS: MAX_CONTENT_CHARACTERS,
    MAX_CANONICAL_BYTES: MAX_CANONICAL_BYTES,
    MAX_ID_ATTEMPTS: MAX_ID_ATTEMPTS,
    emptyCollection: emptyCollection,
    persistenceStateForParseResult: persistenceStateForParseResult,
    unicodeLength: unicodeLength,
    utf8ByteLength: utf8ByteLength,
    jsonStringByteLength: jsonStringByteLength,
    isCanonicalTimestamp: isCanonicalTimestamp,
    serializeCollection: serializeCollection,
    parse: parse,
    findNoteIndex: findNoteIndex,
    generateUniqueId: generateUniqueId,
    createNote: createNote,
    updateNote: updateNote,
    deleteNote: deleteNote,
    newestFirst: newestFirst
  }
}

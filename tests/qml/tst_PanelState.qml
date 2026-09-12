import QtQuick
import QtTest
import "../.." as Pinote

TestCase {
  id: testCase

  name: "PanelState"

  property QtObject fakeStore: QtObject {
    property var notes: []
    property bool canMutate: true
    property string status: "ready"
    property int nextId: 1

    function issue(message) {
      return { ok: false, issues: [{ message: message }] }
    }

    function createNote(content) {
      if (String(content).trim() === "") return issue("Note content cannot be blank.")
      var note = { id: "note-" + nextId++, content: content }
      notes = [note].concat(notes)
      return { ok: true, note: note }
    }

    function updateNote(id, content) {
      if (String(content).trim() === "") return issue("Note content cannot be blank.")
      var updated = null
      var remaining = []
      for (var i = 0; i < notes.length; i++) {
        if (notes[i].id === id) updated = { id: id, content: content }
        else remaining.push(notes[i])
      }
      if (!updated) return issue("The note does not exist.")
      notes = [updated].concat(remaining)
      return { ok: true, note: updated }
    }

    function deleteNote(id) {
      var removed = null
      var remaining = []
      for (var i = 0; i < notes.length; i++) {
        if (notes[i].id === id) removed = notes[i]
        else remaining.push(notes[i])
      }
      if (!removed) return issue("The note does not exist.")
      notes = remaining
      return { ok: true, note: removed }
    }
  }

  property Pinote.PanelState controller: Pinote.PanelState {
    store: testCase.fakeStore
  }

  SignalSpy {
    id: editorFocusSpy
    target: controller
    signalName: "editorFocusRequested"
  }

  function init() {
    fakeStore.notes = []
    fakeStore.canMutate = true
    fakeStore.status = "ready"
    fakeStore.nextId = 1
    controller.mode = "list"
    controller.selectedNoteId = ""
    controller.editingNoteId = ""
    controller.draftContent = ""
    controller.draftError = ""
    controller.draftNotice = ""
    controller.pendingDeleteId = ""
    controller.deleteConfirmOpen = false
    editorFocusSpy.clear()
  }

  function test_createSaveAndValidation() {
    verify(controller.beginCreate())
    compare(controller.mode, "editor")
    compare(editorFocusSpy.count, 1)
    compare(editorFocusSpy.signalArguments[0][0], "start")

    controller.draftContent = "First line\nSecond line"
    verify(controller.saveDraft().ok)
    compare(controller.mode, "list")
    compare(fakeStore.notes.length, 1)
    compare(fakeStore.notes[0].content, "First line\nSecond line")
    compare(controller.selectedNoteId, fakeStore.notes[0].id)

    verify(controller.beginCreate())
    controller.draftContent = "   "
    verify(!controller.saveDraft().ok)
    compare(controller.mode, "editor")
    compare(controller.draftContent, "   ")
    compare(controller.draftError, "Note content cannot be blank.")
  }

  function test_editCancelAndReorderOnSave() {
    fakeStore.notes = [
      { id: "newer", content: "Newer" },
      { id: "older", content: "Older" }
    ]

    verify(controller.beginEdit("older"))
    compare(editorFocusSpy.signalArguments[0][0], "all")
    controller.draftContent = "Canceled edit"
    verify(controller.cancelDraft())
    compare(fakeStore.notes[1].content, "Older")

    verify(controller.beginEdit("older"))
    controller.draftContent = "Updated older note"
    verify(controller.saveDraft().ok)
    compare(fakeStore.notes[0].id, "older")
    compare(fakeStore.notes[0].content, "Updated older note")
    compare(controller.selectedNoteId, "older")
  }

  function test_deleteRequiresConfirmationAndKeepsAdjacentSelection() {
    fakeStore.notes = [
      { id: "first", content: "First" },
      { id: "second", content: "Second" }
    ]
    controller.selectedNoteId = "second"

    verify(controller.requestDelete("second"))
    compare(fakeStore.notes.length, 2)
    controller.cancelDelete()
    compare(fakeStore.notes.length, 2)

    verify(controller.requestDelete("second"))
    verify(controller.confirmDelete().ok)
    compare(fakeStore.notes.length, 1)
    compare(fakeStore.notes[0].id, "first")
    compare(controller.selectedNoteId, "first")
  }

  function test_panelClosePreservesDraftButDismissesConfirmation() {
    fakeStore.notes = [{ id: "note", content: "Committed" }]
    verify(controller.beginEdit("note"))
    controller.draftContent = "Draft kept while hidden"
    verify(controller.requestDelete("note"))

    controller.panelClosed()

    compare(controller.mode, "editor")
    compare(controller.editingNoteId, "note")
    compare(controller.draftContent, "Draft kept while hidden")
    compare(controller.deleteConfirmOpen, false)
    compare(controller.pendingDeleteId, "")
  }

  function test_externalDeletionRestoresDraftAsNewNote() {
    fakeStore.notes = [{ id: "removed", content: "Original" }]
    verify(controller.beginEdit("removed"))
    controller.draftContent = "Retained draft"

    fakeStore.notes = []

    verify(controller.editingNoteMissing)
    verify(controller.draftNotice.indexOf("removed externally") >= 0)
    verify(controller.saveDraft().ok)
    compare(fakeStore.notes.length, 1)
    compare(fakeStore.notes[0].content, "Retained draft")
    verify(fakeStore.notes[0].id !== "removed")
  }

  function test_externalModificationUsesLastWriterWinsPolicy() {
    fakeStore.notes = [{ id: "shared", content: "Original" }]
    verify(controller.beginEdit("shared"))
    controller.draftContent = "Local draft"

    fakeStore.notes = [{ id: "shared", content: "External change" }]
    verify(controller.saveDraft().ok)

    compare(fakeStore.notes[0].content, "Local draft")
  }
}

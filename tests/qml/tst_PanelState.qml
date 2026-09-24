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
    property bool recoveryBusy: false
    property bool recoveryBackupAvailable: false
    property bool recoveryArchiveVerified: false
    property int recoveryGeneration: 0
    property string lastRecoveryAction: ""

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

    function restoreBackup() {
      lastRecoveryAction = "restore"
      return true
    }

    function startFresh() {
      lastRecoveryAction = "start-fresh"
      return true
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
    fakeStore.recoveryBusy = false
    fakeStore.recoveryBackupAvailable = false
    fakeStore.recoveryArchiveVerified = false
    fakeStore.recoveryGeneration = 0
    fakeStore.lastRecoveryAction = ""
    controller.mode = "list"
    controller.selectedNoteId = ""
    controller.editingNoteId = ""
    controller.draftContent = ""
    controller.draftError = ""
    controller.draftNotice = ""
    controller.pendingDeleteId = ""
    controller.deleteConfirmOpen = false
    controller.pendingRecoveryAction = ""
    controller.pendingRecoveryGeneration = -1
    controller.recoveryConfirmOpen = false
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

    controller.updateDraftContent("Corrected")
    compare(controller.draftError, "")
    compare(controller.draftContent, "Corrected")
  }

  function test_recoveryActionsRequireConfirmation() {
    fakeStore.status = "recovery"

    verify(!controller.requestRecovery("restore"))
    fakeStore.recoveryBackupAvailable = true
    verify(controller.requestRecovery("restore"))
    compare(controller.recoveryConfirmOpen, true)
    compare(fakeStore.lastRecoveryAction, "")
    controller.cancelRecovery()
    compare(fakeStore.lastRecoveryAction, "")

    verify(controller.requestRecovery("restore"))
    verify(controller.confirmRecovery())
    compare(fakeStore.lastRecoveryAction, "restore")

    verify(controller.requestRecovery("start-fresh"))
    verify(controller.confirmRecovery())
    compare(fakeStore.lastRecoveryAction, "start-fresh")
  }

  function test_recoveryConfirmationExpiresWhenSourceChanges() {
    fakeStore.status = "recovery"
    fakeStore.recoveryBackupAvailable = true
    fakeStore.recoveryGeneration = 4
    verify(controller.requestRecovery("restore"))

    fakeStore.recoveryGeneration = 5

    compare(controller.recoveryConfirmOpen, false)
    compare(controller.confirmRecovery(), false)
    compare(fakeStore.lastRecoveryAction, "")
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

  function test_deleteConfirmationClosesWhenStoreBecomesReadOnly() {
    fakeStore.notes = [{ id: "note", content: "Committed" }]
    verify(controller.requestDelete("note"))

    fakeStore.canMutate = false
    fakeStore.status = "recovery"

    compare(controller.deleteConfirmOpen, false)
    compare(controller.pendingDeleteId, "")
    compare(fakeStore.notes.length, 1)
    compare(controller.confirmDelete(), null)
    compare(fakeStore.notes.length, 1)
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

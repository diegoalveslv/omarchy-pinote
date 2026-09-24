import QtQuick

QtObject {
  id: root

  required property var store

  property string mode: "list"
  property string selectedNoteId: ""
  property string editingNoteId: ""
  property string draftContent: ""
  property string draftError: ""
  property string draftNotice: ""
  property string pendingDeleteId: ""
  property bool deleteConfirmOpen: false
  property string pendingRecoveryAction: ""
  property int pendingRecoveryGeneration: -1
  property bool recoveryConfirmOpen: false

  readonly property bool editingNoteMissing: editingNoteId !== "" && noteIndex(editingNoteId) < 0

  signal editorFocusRequested(string selectionMode)
  signal listFocusRequested()
  signal currentFocusRequested()

  property Connections storeConnections: Connections {
    target: root.store

    function onNotesChanged() {
      root.handleNotesChanged()
    }

    function onStatusChanged() {
      if (root.deleteConfirmOpen && !root.store.canMutate) root.cancelDelete()
      if (root.recoveryConfirmOpen && root.store.status !== "recovery") root.cancelRecovery()
      root.currentFocusRequested()
    }

    function onRecoveryGenerationChanged() {
      if (root.recoveryConfirmOpen) root.cancelRecovery()
    }
  }

  function noteIndex(id) {
    for (var i = 0; i < store.notes.length; i++) {
      if (store.notes[i].id === id) return i
    }
    return -1
  }

  function noteById(id) {
    var index = noteIndex(id)
    return index < 0 ? null : store.notes[index]
  }

  function issueMessage(result) {
    if (result && result.issues && result.issues.length > 0)
      return String(result.issues[0].message || "The note could not be saved.")
    return "The note could not be saved."
  }

  function updateDraftContent(content) {
    draftContent = content
    draftError = ""
  }

  function syncSelection() {
    if (store.notes.length === 0) {
      selectedNoteId = ""
      return
    }
    if (noteIndex(selectedNoteId) < 0) selectedNoteId = store.notes[0].id
  }

  function selectRelative(delta) {
    if (store.notes.length === 0) return -1
    var index = noteIndex(selectedNoteId)
    if (index < 0) index = 0
    else index = Math.max(0, Math.min(store.notes.length - 1, index + delta))
    selectedNoteId = store.notes[index].id
    listFocusRequested()
    return index
  }

  function beginCreate() {
    if (!store.canMutate) return false
    editingNoteId = ""
    draftContent = ""
    draftError = ""
    draftNotice = ""
    mode = "editor"
    editorFocusRequested("start")
    return true
  }

  function beginEdit(id) {
    if (!store.canMutate) return false
    var note = noteById(id)
    if (!note) return false
    selectedNoteId = note.id
    editingNoteId = note.id
    draftContent = note.content
    draftError = ""
    draftNotice = ""
    mode = "editor"
    editorFocusRequested("all")
    return true
  }

  function saveDraft() {
    if (!store.canMutate || mode !== "editor") return null
    var result = editingNoteId === "" || editingNoteMissing
      ? store.createNote(draftContent)
      : store.updateNote(editingNoteId, draftContent)
    if (!result.ok) {
      draftError = issueMessage(result)
      return result
    }

    selectedNoteId = result.note.id
    editingNoteId = ""
    draftContent = ""
    draftError = ""
    draftNotice = ""
    mode = "list"
    listFocusRequested()
    return result
  }

  function cancelDraft() {
    if (mode !== "editor") return false
    editingNoteId = ""
    draftContent = ""
    draftError = ""
    draftNotice = ""
    mode = "list"
    syncSelection()
    listFocusRequested()
    return true
  }

  function requestDelete(id) {
    if (!store.canMutate || noteIndex(id) < 0) return false
    pendingDeleteId = id
    deleteConfirmOpen = true
    return true
  }

  function cancelDelete() {
    deleteConfirmOpen = false
    pendingDeleteId = ""
    currentFocusRequested()
  }

  function confirmDelete() {
    var id = pendingDeleteId
    var wasSelected = selectedNoteId === id
    deleteConfirmOpen = false
    pendingDeleteId = ""
    if (id === "") return null
    if (!store.canMutate) {
      currentFocusRequested()
      return { ok: false, issues: [] }
    }

    var deletedIndex = noteIndex(id)
    var result = store.deleteNote(id)
    if (!result.ok) {
      draftError = issueMessage(result)
      currentFocusRequested()
      return result
    }

    if (editingNoteId === id) {
      editingNoteId = ""
      draftContent = ""
      draftError = ""
      draftNotice = ""
      mode = "list"
    }
    if (wasSelected) {
      var nextIndex = Math.min(deletedIndex, store.notes.length - 1)
      selectedNoteId = nextIndex >= 0 ? store.notes[nextIndex].id : ""
    }
    listFocusRequested()
    return result
  }

  function requestRecovery(action) {
    if (store.status !== "recovery" || store.recoveryBusy || store.recoveryArchiveVerified) return false
    if (action !== "restore" && action !== "start-fresh") return false
    if (action === "restore" && !store.recoveryBackupAvailable) return false
    pendingRecoveryAction = action
    pendingRecoveryGeneration = store.recoveryGeneration
    recoveryConfirmOpen = true
    return true
  }

  function cancelRecovery() {
    recoveryConfirmOpen = false
    pendingRecoveryAction = ""
    pendingRecoveryGeneration = -1
    currentFocusRequested()
  }

  function confirmRecovery() {
    var action = pendingRecoveryAction
    var generation = pendingRecoveryGeneration
    if (store.status !== "recovery" || store.recoveryBusy
        || store.recoveryArchiveVerified || generation !== store.recoveryGeneration
        || (action === "restore" && !store.recoveryBackupAvailable)) {
      recoveryConfirmOpen = false
      pendingRecoveryAction = ""
      pendingRecoveryGeneration = -1
      currentFocusRequested()
      return false
    }
    var started = action === "restore" ? store.restoreBackup()
      : action === "start-fresh" ? store.startFresh() : false
    if (started) {
      recoveryConfirmOpen = false
      pendingRecoveryAction = ""
      pendingRecoveryGeneration = -1
    }
    currentFocusRequested()
    return started
  }

  function panelClosed() {
    deleteConfirmOpen = false
    pendingDeleteId = ""
    recoveryConfirmOpen = false
    pendingRecoveryAction = ""
    pendingRecoveryGeneration = -1
  }

  function handleNotesChanged() {
    syncSelection()
    if (mode === "editor" && editingNoteId !== "") {
      draftNotice = noteIndex(editingNoteId) < 0
        ? "The original note was removed externally. Saving will restore this draft as a new note."
        : ""
    }
    if (pendingDeleteId !== "" && noteIndex(pendingDeleteId) < 0) {
      deleteConfirmOpen = false
      pendingDeleteId = ""
    }
  }
}

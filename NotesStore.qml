import QtQuick
import Quickshell
import Quickshell.Io
import "NotesModel.js" as NotesModel
import "NotesStoreQueue.js" as NotesStoreQueue

Item {
  id: root

  signal primaryVerificationPending

  property string status: "initializing"
  property var collection: NotesModel.emptyCollection()
  readonly property var notes: NotesModel.newestFirst(collection)
  property var issues: []
  property int unsupportedVersion: 0

  property int revision: 0
  property int durableRevision: 0
  readonly property bool hasPendingSave: revision !== durableRevision
    || _queueState.activePrimary !== null
    || _queueState.queuedPrimary !== null
    || _queueState.retryPrimary !== null
  readonly property bool durable: status === "ready" && !hasPendingSave
  readonly property bool canMutate: status === "ready" || status === "saving" || status === "save-error"

  property string errorOperation: ""
  property string errorCode: ""
  property string errorMessage: ""
  property string errorPath: ""
  property bool backupHealthy: true
  property string backupStatus: "idle"
  property string backupErrorCode: ""
  property string backupErrorMessage: ""
  property bool externalChangePending: false

  readonly property string stateRoot: resolvedStateRoot()
  readonly property string stateDirectory: stateRoot === "" ? "" : stateRoot + "/pinote"
  readonly property string primaryPath: stateDirectory === "" ? "" : stateDirectory + "/notes.json"
  readonly property string backupPath: stateDirectory === "" ? "" : stateDirectory + "/notes.json.bak"

  property var _queueState: NotesStoreQueue.emptyState()
  property bool _readInProgress: false
  property int _readRevision: 0
  property string _readPurpose: ""
  property bool _watchRequested: false
  property string _watchPath: ""
  property string _probePath: ""
  property string _readerPath: ""
  property string _verifierPath: ""
  property string _backupVerifierPath: ""
  property string _lastDiskPayload: ""
  property string _currentPayload: NotesModel.serializeCollection(collection)
  property var _latestCommittedSnapshot: null
  property var _verificationSnapshot: null
  property var _backupVerificationSnapshot: null
  property bool _directoryProcessStarted: false
  property bool _primaryDispatched: false
  property bool _destroying: false

  function resolvedStateRoot() {
    var xdgStateHome = String(Quickshell.env("XDG_STATE_HOME") || "")
    if (xdgStateHome.charAt(0) === "/") return xdgStateHome

    var home = String(Quickshell.env("HOME") || "")
    return home.charAt(0) === "/" ? home + "/.local/state" : ""
  }

  function storeIssue(code, path, message) {
    return { code: code, path: path, message: message }
  }

  function mutationAllowed() {
    return status === "ready" || status === "saving" || status === "save-error"
  }

  function clearPrimaryError() {
    errorOperation = ""
    errorCode = ""
    errorMessage = ""
    errorPath = ""
  }

  function fileErrorCode(error) {
    if (error === FileViewError.FileNotFound) return "file-not-found"
    if (error === FileViewError.PermissionDenied) return "permission-denied"
    if (error === FileViewError.NotAFile) return "not-a-file"
    return "unknown"
  }

  function setFileError(operation, path, error) {
    errorOperation = operation
    errorCode = fileErrorCode(error)
    errorMessage = String(FileViewError.toString(error))
    errorPath = path
  }

  function beginRead(purpose) {
    if (_readInProgress) {
      _watchRequested = true
      return false
    }

    _readInProgress = true
    _readRevision = revision
    _readPurpose = purpose
    if (_readerPath === primaryPath) primaryReader.reload()
    else _readerPath = primaryPath
    return true
  }

  function finishRead(raw) {
    var purpose = _readPurpose
    _readInProgress = false
    _readPurpose = ""

    if (purpose === "conflict" || purpose === "retry-check") {
      finishDirtyRead(raw, purpose)
      return
    }

    if (_readRevision !== revision || hasPendingSave) {
      _watchRequested = true
      if (status === "save-error") externalChangePending = true
      schedulePendingWatch()
      return
    }

    if (purpose === "external" && raw === _lastDiskPayload) {
      externalChangePending = false
      schedulePendingWatch()
      return
    }

    applyParsed(NotesModel.parse(raw), raw, purpose)
    schedulePendingWatch()
  }

  function finishMissingRead() {
    var purpose = _readPurpose
    _readInProgress = false
    _readPurpose = ""

    if (purpose === "conflict" || purpose === "retry-check") {
      finishDirtyRead("", purpose)
      return
    }

    if (_readRevision !== revision || hasPendingSave) {
      _watchRequested = true
      externalChangePending = true
      schedulePendingWatch()
      return
    }

    applyParsed(NotesModel.parse(""), "", purpose)
    schedulePendingWatch()
  }

  function failRead(error) {
    var purpose = _readPurpose
    _readInProgress = false
    _readPurpose = ""
    if (purpose === "conflict" || purpose === "retry-check") {
      externalChangePending = true
      _watchRequested = false
      console.warn("pinote: dirty-state check failed: " + fileErrorCode(error) + " path=" + primaryPath)
      return
    }
    if (_readRevision !== revision || hasPendingSave) {
      _watchRequested = true
      if (status === "save-error") externalChangePending = true
      schedulePendingWatch()
      return
    }
    setFileError("load", primaryPath, error)
    status = "load-error"
    console.warn("pinote: load failed: " + errorCode + " path=" + primaryPath)
  }

  function applyParsed(result, raw, purpose) {
    if (purpose !== "initial") revision++
    durableRevision = revision
    _lastDiskPayload = raw
    issues = result.issues || []
    unsupportedVersion = result.version || 0
    externalChangePending = false
    clearPrimaryError()

    if (result.collection) {
      collection = result.collection
      _currentPayload = NotesModel.serializeCollection(result.collection)
    }
    status = NotesModel.persistenceStateForParseResult(result)
  }

  function finishDirtyRead(raw, purpose) {
    _watchRequested = false
    externalChangePending = raw !== _lastDiskPayload
    if (purpose === "retry-check" && !externalChangePending) performRetrySave()
  }

  function schedulePendingWatch() {
    if (_watchRequested && !_readInProgress
        && (!hasPendingSave || status === "save-error")) watcherTimer.restart()
  }

  function inspectWatchedState() {
    if (!_watchRequested || _readInProgress || status === "initializing") return
    if (hasPendingSave) {
      if (status === "save-error") {
        _watchRequested = false
        beginRead("conflict")
      }
      return
    }

    _watchRequested = false
    beginRead("external")
  }

  function applyQueueTransition(next, resetPrimary, resetBackup) {
    _queueState = next.state
    if (next.writePrimary) {
      var primaryPayload = next.writePrimary.payload
      Qt.callLater(function() {
        if (root._destroying) return
        if (resetPrimary) {
          primaryWriter.path = ""
          Qt.callLater(function() {
            if (root._destroying) return
            primaryWriter.path = root.primaryPath
            Qt.callLater(function() {
              if (root._destroying) return
              root._primaryDispatched = true
              primaryWriter.setText(primaryPayload)
            })
          })
        } else {
          if (root._destroying) return
          root._primaryDispatched = true
          primaryWriter.setText(primaryPayload)
        }
      })
    }
    if (next.writeBackup) {
      backupStatus = "saving"
      var backupPayload = next.writeBackup.payload
      Qt.callLater(function() {
        if (root._destroying) return
        if (resetBackup) {
          backupWriter.path = ""
          Qt.callLater(function() {
            if (root._destroying) return
            backupWriter.path = root.backupPath
            Qt.callLater(function() {
              if (!root._destroying) backupWriter.setText(backupPayload)
            })
          })
        } else {
          if (!root._destroying) backupWriter.setText(backupPayload)
        }
      })
    }
  }

  function commitMutation(result, operation) {
    if (!result.ok) return result

    var nextRevision = revision + 1
    var payload = NotesModel.serializeCollection(result.collection)
    if (payload === _currentPayload)
      return { ok: true, note: result.note, operation: operation, revision: revision, unchanged: true }

    var snapshot = { revision: nextRevision, payload: payload }
    var paused = status === "save-error"

    collection = result.collection
    _currentPayload = payload
    _latestCommittedSnapshot = snapshot
    revision = nextRevision
    issues = []
    var queued = NotesStoreQueue.enqueuePrimary(_queueState, snapshot, paused)
    if (!paused) status = "saving"
    applyQueueTransition(queued)

    return { ok: true, note: result.note, operation: operation, revision: nextRevision }
  }

  function createNote(content) {
    if (!mutationAllowed())
      return { ok: false, issues: [storeIssue("store-not-writable", "$", "Notes cannot be changed in the current storage state.")] }

    var timestamp = new Date().toISOString()
    return commitMutation(NotesModel.createNote(collection, content, timestamp, function(attempt) {
      return timestamp.replace(/[^0-9]/g, "") + "-" + revision.toString(36) + "-"
        + attempt.toString(36) + "-" + Math.floor(Math.random() * 0x100000000).toString(36)
    }), "create")
  }

  function updateNote(id, content) {
    if (!mutationAllowed())
      return { ok: false, issues: [storeIssue("store-not-writable", "$", "Notes cannot be changed in the current storage state.")] }
    return commitMutation(NotesModel.updateNote(collection, id, content, new Date().toISOString()), "update")
  }

  function deleteNote(id) {
    if (!mutationAllowed())
      return { ok: false, issues: [storeIssue("store-not-writable", "$", "Notes cannot be changed in the current storage state.")] }
    return commitMutation(NotesModel.deleteNote(collection, id), "delete")
  }

  function retrySave() {
    if (status !== "save-error" || _readInProgress) return false
    _watchRequested = false
    return beginRead("retry-check")
  }

  function performRetrySave() {
    var retried = NotesStoreQueue.retryPrimary(_queueState)
    if (!retried.writePrimary) return false

    clearPrimaryError()
    status = "saving"
    applyQueueTransition(retried, true, false)
    return true
  }

  function retryBackup() {
    var retried = NotesStoreQueue.retryBackup(_queueState)
    if (!retried.writeBackup) return false

    backupErrorCode = ""
    backupErrorMessage = ""
    applyQueueTransition(retried, false, true)
    return true
  }

  function retryLoad() {
    if (hasPendingSave || _readInProgress) return false
    if (stateRoot === "") return false
    var failedOperation = errorOperation
    status = "initializing"
    clearPrimaryError()
    if (failedOperation === "create-directory") {
      _probePath = ""
      _directoryProcessStarted = false
      ensureDirectory.running = true
      return true
    }
    return beginRead("retry")
  }

  function finishDirectoryProbe(error) {
    if (error !== FileViewError.NotAFile) {
      errorOperation = "create-directory"
      errorCode = error === FileViewError.FileNotFound ? "directory-create-failed" : fileErrorCode(error)
      errorMessage = error === FileViewError.FileNotFound
        ? "The Pinote state directory could not be created."
        : String(FileViewError.toString(error))
      errorPath = stateDirectory
      status = "load-error"
      console.warn("pinote: state directory unavailable: " + errorCode + " path=" + stateDirectory)
      return
    }

    _watchPath = stateDirectory
    beginRead("initial")
  }

  function rejectNonDirectoryStatePath() {
    errorOperation = "create-directory"
    errorCode = "not-a-directory"
    errorMessage = "The Pinote state directory path is not a directory."
    errorPath = stateDirectory
    status = "load-error"
    console.warn("pinote: state path is not a directory: path=" + stateDirectory)
  }

  function verifyPrimaryWrite() {
    if (_destroying || _verificationSnapshot) return
    _primaryDispatched = false
    _verificationSnapshot = _queueState.activePrimary
    _verifierPath = ""
    primaryVerificationPending()
    Qt.callLater(function() { root.startPrimaryVerificationRead() })
  }

  function startPrimaryVerificationRead() {
    if (!_destroying) _verifierPath = primaryPath
  }

  function finishPrimaryVerification(raw) {
    var verified = _verificationSnapshot
    _verificationSnapshot = null
    if (!verified) return
    if (raw !== verified.payload) {
      failActivePrimary("verification-mismatch", "The saved notes could not be verified.")
      return
    }

    var saved = NotesStoreQueue.primarySaved(_queueState, raw)
    if (!saved.confirmedPrimary) return

    durableRevision = saved.confirmedPrimary.revision
    _lastDiskPayload = saved.confirmedPrimary.payload
    clearPrimaryError()
    applyQueueTransition(saved)
    status = revision === durableRevision && _queueState.activePrimary === null ? "ready" : "saving"
    schedulePendingWatch()
  }

  function failPrimaryVerification(error) {
    _verificationSnapshot = null
    failActivePrimary(fileErrorCode(error), String(FileViewError.toString(error)))
  }

  function failActivePrimary(code, message) {
    _primaryDispatched = false
    var failed = NotesStoreQueue.primaryFailed(_queueState)
    if (!failed.failedPrimary) return

    applyQueueTransition(failed)
    errorOperation = "save"
    errorCode = code
    errorMessage = message
    errorPath = primaryPath
    status = "save-error"
    if (_watchRequested) externalChangePending = true
    console.warn("pinote: save failed: " + errorCode + " path=" + primaryPath)
  }

  function handlePrimaryFailed(error) {
    failActivePrimary(fileErrorCode(error), String(FileViewError.toString(error)))
  }

  function verifyBackupWrite() {
    if (_destroying || _backupVerificationSnapshot) return
    _backupVerificationSnapshot = _queueState.activeBackup
    _backupVerifierPath = ""
    Qt.callLater(function() {
      if (!root._destroying) root._backupVerifierPath = root.backupPath
    })
  }

  function finishBackupVerification(raw) {
    var verified = _backupVerificationSnapshot
    _backupVerificationSnapshot = null
    if (!verified) return
    if (raw !== verified.payload) {
      failActiveBackup("verification-mismatch", "The backup could not be verified.")
      return
    }

    var saved = NotesStoreQueue.backupSaved(_queueState, raw)
    if (!saved.confirmedBackup) return

    backupHealthy = true
    backupErrorCode = ""
    backupErrorMessage = ""
    applyQueueTransition(saved)
    backupStatus = _queueState.activeBackup ? "saving" : "ready"
  }

  function failBackupVerification(error) {
    _backupVerificationSnapshot = null
    failActiveBackup(fileErrorCode(error), String(FileViewError.toString(error)))
  }

  function failActiveBackup(code, message) {
    var failed = NotesStoreQueue.backupFailed(_queueState)
    if (!failed.failedBackup) return

    backupHealthy = false
    backupErrorCode = code
    backupErrorMessage = message
    applyQueueTransition(failed)
    backupStatus = _queueState.activeBackup ? "saving" : "error"
    console.warn("pinote: backup save failed: " + backupErrorCode + " path=" + backupPath)
  }

  function handleBackupFailed(error) {
    failActiveBackup(fileErrorCode(error), String(FileViewError.toString(error)))
  }

  Process {
    id: ensureDirectory
    running: false
    command: ["mkdir", "-p", "--", root.stateDirectory]
    onRunningChanged: {
      if (running) root._directoryProcessStarted = true
      else if (root._directoryProcessStarted) root._probePath = root.stateDirectory
    }
  }

  FileView {
    id: directoryProbe
    path: root._probePath
    preload: root._probePath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.rejectNonDirectoryStatePath()
    onLoadFailed: function(error) { root.finishDirectoryProbe(error) }
  }

  FileView {
    id: directoryWatcher
    path: root._watchPath
    preload: root._watchPath !== ""
    blockWrites: true
    watchChanges: root._watchPath !== ""
    printErrors: false
    onFileChanged: {
      root._watchRequested = true
      watcherTimer.restart()
    }
  }

  Timer {
    id: watcherTimer
    interval: 50
    repeat: false
    onTriggered: root.inspectWatchedState()
  }

  FileView {
    id: primaryReader
    path: root._readerPath
    preload: root._readerPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.finishRead(text())
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) root.finishMissingRead()
      else root.failRead(error)
    }
  }

  FileView {
    id: primaryWriter
    path: root.primaryPath
    preload: false
    blockLoading: true
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onSaved: root.verifyPrimaryWrite()
    onSaveFailed: function(error) { root.handlePrimaryFailed(error) }
  }

  FileView {
    id: primaryVerifier
    path: root._verifierPath
    preload: root._verifierPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.finishPrimaryVerification(text())
    onLoadFailed: function(error) { root.failPrimaryVerification(error) }
  }

  FileView {
    id: backupWriter
    path: root.backupPath
    preload: false
    blockLoading: true
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onSaved: root.verifyBackupWrite()
    onSaveFailed: function(error) { root.handleBackupFailed(error) }
  }

  FileView {
    id: backupVerifier
    path: root._backupVerifierPath
    preload: root._backupVerifierPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.finishBackupVerification(text())
    onLoadFailed: function(error) { root.failBackupVerification(error) }
  }

  FileView {
    id: shutdownConflictReader
    path: root.primaryPath
    preload: false
    blockLoading: true
    blockWrites: true
    watchChanges: false
    printErrors: false
  }

  FileView {
    id: shutdownWriter
    path: root.primaryPath
    preload: false
    blockLoading: true
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: shutdownVerifier
    path: root.primaryPath
    preload: false
    blockLoading: true
    blockWrites: true
    watchChanges: false
    printErrors: false
  }

  Component.onCompleted: {
    if (stateRoot === "") {
      errorOperation = "resolve-state-directory"
      errorCode = "invalid-state-directory"
      errorMessage = "Neither XDG_STATE_HOME nor HOME resolves to an absolute path."
      status = "load-error"
      console.warn("pinote: state directory could not be resolved")
    } else {
      console.log("pinote: initializing state path=" + stateDirectory)
      ensureDirectory.running = true
    }
  }

  Component.onDestruction: {
    _destroying = true
    watcherTimer.stop()
    if (!hasPendingSave || !_latestCommittedSnapshot) return
    var activePayload = _queueState.activePrimary ? _queueState.activePrimary.payload : ""
    if (_primaryDispatched) primaryWriter.waitForJob()
    if (_verificationSnapshot) primaryVerifier.waitForJob()
    var diskPayload = shutdownConflictReader.text()
    if (diskPayload !== _lastDiskPayload && diskPayload !== activePayload) {
      console.warn("pinote: shutdown save skipped because the primary file changed externally: path=" + primaryPath)
      return
    }
    shutdownWriter.setText(_latestCommittedSnapshot.payload)
    shutdownWriter.waitForJob()
    if (shutdownVerifier.text() !== _latestCommittedSnapshot.payload)
      console.warn("pinote: shutdown save verification failed: path=" + primaryPath)
  }
}

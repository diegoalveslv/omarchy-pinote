import QtQuick
import Quickshell
import Quickshell.Io
import "NotesModel.js" as NotesModel
import "NotesStoreQueue.js" as NotesStoreQueue

// Quickshell exposes QProcess::ExitStatus without exporting that C++ enum to qmllint.
// qmllint disable signal-handler-parameters

Item {
  id: root

  signal primaryVerificationPending
  signal recoveryFinalVerificationPending

  property string stateDirectoryName: "pinote"
  property string logPrefix: "pinote:"
  property string displayName: "Pinote"
  property bool autoStart: true
  property string recoveryHandoffHook: ""
  property string recoveryCleanupHook: ""
  property int recoveryStageDelayMs: 0
  property int recoveryVerificationDelayMs: 100
  property string recoveryHelperPath: String(Qt.resolvedUrl("recovery-handoff")).replace(/^file:\/\//, "")
  property string status: "initializing"
  property var collection: NotesModel.emptyCollection()
  readonly property var notes: NotesModel.newestFirst(collection)
  property var issues: []
  property string issueSummary: ""
  property var unsupportedVersion: 0
  property int recoveryAcceptedRecords: 0
  property int recoveryRejectedRecords: 0
  property int recoveryGeneration: 0

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
  property string recoveryBackupStatus: "idle"
  property string recoveryBackupMessage: ""
  property string recoveryOperation: "idle"
  property string recoveryErrorCode: ""
  property string recoveryErrorMessage: ""
  property string recoveryArchivePath: ""
  property bool recoveryArchiveVerified: false
  readonly property bool recoveryBusy: recoveryOperation === "checking"
    || recoveryOperation === "checking-backup"
    || recoveryOperation === "archiving" || recoveryOperation === "verifying-archive"
    || recoveryOperation === "staging" || recoveryOperation === "verifying-stage"
    || recoveryOperation === "writing-marker" || recoveryOperation === "verifying-marker"
    || recoveryOperation === "securing-files" || recoveryOperation === "handoff"
    || recoveryOperation === "verifying-write" || recoveryOperation === "verifying-identity"
    || (status === "recovery" && _readInProgress)
  readonly property bool recoveryBackupAvailable: recoveryBackupStatus === "valid"
  readonly property bool hasActiveRecoveryFileWork: _recoveryWriteDispatched
    || recoveryOperation === "verifying-stage" || recoveryOperation === "writing-marker"
    || recoveryOperation === "verifying-marker" || recoveryOperation === "verifying-write"

  readonly property string stateRoot: resolvedStateRoot()
  readonly property string stateDirectory: stateRoot === "" ? "" : stateRoot + "/" + stateDirectoryName
  readonly property string primaryPath: stateDirectory === "" ? "" : stateDirectory + "/notes.json"
  readonly property string backupPath: stateDirectory === "" ? "" : stateDirectory + "/notes.json.bak"
  readonly property string recoveryMarkerPath: stateDirectory === ""
    ? "" : stateDirectory + "/.pinote-recovery-transaction.json"

  property var _queueState: NotesStoreQueue.emptyState()
  property bool _readInProgress: false
  property int _readRevision: 0
  property string _readPurpose: ""
  property bool _watchRequested: false
  property int _watchGeneration: 0
  property string _watchPath: ""
  property string _probePath: ""
  property string _readerPath: ""
  property string _verifierPath: ""
  property string _backupVerifierPath: ""
  property string _recoveryBackupReaderPath: ""
  property string _recoveryActionBackupReaderPath: ""
  property string _recoveryArchiveReaderPath: ""
  property string _recoveryVerifierPath: ""
  property string _recoveryStageWriterPath: ""
  property string _recoveryStageVerifierPath: ""
  property string _recoveryMarkerWriterPath: ""
  property string _recoveryMarkerVerifierPath: ""
  property string _transactionMarkerReaderPath: ""
  property string _transactionStageReaderPath: ""
  property string _lastDiskPayload: ""
  property string _currentPayload: NotesModel.serializeCollection(collection)
  property var _latestCommittedSnapshot: null
  property var _verificationSnapshot: null
  property var _backupVerificationSnapshot: null
  property bool _directoryProcessStarted: false
  property bool _directoryLaunchPending: false
  property bool _initialized: false
  property bool _primaryDispatched: false
  property bool _destroying: false
  property string _recoveryBackupPayload: ""
  property string _recoveryBackupRaw: ""
  property string _recoveryExpectedPrimary: ""
  property string _recoveryReplacementPayload: ""
  property string _recoveryAction: ""
  property string _recoveryArchiveCandidate: ""
  property string _recoveryCurrentArchivePath: ""
  property string _recoveryStagePath: ""
  property string _recoveryMarkerPayload: ""
  property bool _archiveProcessStarted: false
  property bool _archiveLaunchPending: false
  property bool _handoffProcessStarted: false
  property bool _handoffLaunchPending: false
  property int _handoffExitCode: 0
  property bool _permissionProcessStarted: false
  property bool _permissionLaunchPending: false
  property bool _identityProcessStarted: false
  property bool _identityLaunchPending: false
  property bool _cleanupProcessStarted: false
  property bool _cleanupLaunchPending: false
  property string _cleanupPurpose: ""
  property string _handoffPurpose: ""
  property bool _interruptedRecoveryActive: false
  property bool _recoveryWriteDispatched: false
  property int _backupInspectionGeneration: 0
  property int _activeBackupInspectionGeneration: 0
  property int _recoveryVerificationWatchGeneration: 0
  property string _recoveryVerificationRaw: ""
  property int _recoveryVerificationPasses: 0

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
    if (purpose === "recovery-check") {
      finishRecoveryCheck(raw, true)
      return
    }
    if (purpose === "interrupted" || purpose === "interrupted-result") {
      finishInterruptedPrimary(raw, purpose)
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
      if (status === "recovery") {
        recoveryGeneration++
        inspectRecoveryBackup()
      }
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
    if (purpose === "recovery-check") {
      finishRecoveryCheck("", false)
      return
    }
    if (purpose === "interrupted") {
      resumeInterruptedRecovery()
      return
    }
    if (purpose === "interrupted-result") {
      failInterruptedRecovery("The interrupted recovery did not restore the primary file.")
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
      console.warn(logPrefix + " dirty-state check failed: " + fileErrorCode(error) + " path=" + primaryPath)
      return
    }
    if (purpose === "recovery-check") {
      recoveryFailure(fileErrorCode(error), "The damaged notes file could not be revalidated.")
      return
    }
    if (purpose === "interrupted" || purpose === "interrupted-result") {
      failInterruptedRecovery("The interrupted recovery primary could not be read.")
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
    console.warn(logPrefix + " load failed: " + errorCode + " path=" + primaryPath)
  }

  function applyParsed(result, raw, purpose) {
    if (purpose !== "initial") revision++
    durableRevision = revision
    _lastDiskPayload = raw
    issues = result.issues || []
    issueSummary = issues.length > 0 && issues[0]
      ? String(issues[0].message || "The notes file is invalid.") : ""
    unsupportedVersion = result.version || 0
    recoveryAcceptedRecords = result.acceptedRecords || 0
    recoveryRejectedRecords = result.rejectedRecords || 0
    externalChangePending = false
    clearPrimaryError()

    if (result.collection) {
      collection = result.collection
      _currentPayload = NotesModel.serializeCollection(result.collection)
    }
    status = NotesModel.persistenceStateForParseResult(result)
    if (status === "recovery") {
      recoveryGeneration++
      if (!recoveryBusy && recoveryOperation !== "error") {
        resetRecoveryOperation()
        recoveryArchivePath = ""
      }
      console.warn(logPrefix + " notes file requires recovery: issue="
        + (issues.length > 0 ? issues[0].code : "unknown") + " path=" + primaryPath)
      inspectRecoveryBackup()
    } else {
      resetBackupInspection()
      if (status === "unsupported")
        console.warn(logPrefix + " unsupported schema version=" + String(unsupportedVersion)
          + " path=" + primaryPath)
      if (purpose !== "recovery-complete") resetRecoveryOperation()
    }
  }

  function resetBackupInspection() {
    _backupInspectionGeneration++
    _activeBackupInspectionGeneration = 0
    _recoveryBackupReaderPath = ""
    _recoveryBackupPayload = ""
    _recoveryBackupRaw = ""
    recoveryBackupStatus = "idle"
    recoveryBackupMessage = ""
  }

  function inspectRecoveryBackup() {
    _backupInspectionGeneration++
    _activeBackupInspectionGeneration = _backupInspectionGeneration
    _recoveryBackupPayload = ""
    _recoveryBackupRaw = ""
    recoveryBackupStatus = "checking"
    recoveryBackupMessage = ""
    _recoveryBackupReaderPath = ""
    Qt.callLater(function() {
      if (!root._destroying && root.status === "recovery")
        root._recoveryBackupReaderPath = root.backupPath
    })
  }

  function finishRecoveryBackupRead(raw) {
    if (_activeBackupInspectionGeneration !== _backupInspectionGeneration || status !== "recovery") return
    _recoveryBackupReaderPath = ""
    if (String(raw).trim() === "") {
      recoveryBackupStatus = "invalid"
      recoveryBackupMessage = "The backup is blank and cannot be restored."
      console.warn(logPrefix + " recovery backup rejected: category=blank path=" + backupPath)
      return
    }
    var result = NotesModel.parse(raw)
    if (result.status === "ready") {
      _recoveryBackupRaw = raw
      _recoveryBackupPayload = NotesModel.serializeCollection(result.collection)
      recoveryBackupStatus = "valid"
      recoveryBackupMessage = "A valid last-known-good backup is available."
      console.log(logPrefix + " valid recovery backup found: path=" + backupPath)
    } else {
      recoveryBackupStatus = "invalid"
      recoveryBackupMessage = result.status === "unsupported"
        ? "The backup uses an unsupported schema version."
        : "The backup is not a complete valid notes file."
      console.warn(logPrefix + " recovery backup rejected: category=" + result.status
        + " path=" + backupPath)
    }
  }

  function failRecoveryBackupRead(error) {
    if (_activeBackupInspectionGeneration !== _backupInspectionGeneration || status !== "recovery") return
    _recoveryBackupReaderPath = ""
    if (error === FileViewError.FileNotFound) {
      recoveryBackupStatus = "missing"
      recoveryBackupMessage = "No last-known-good backup is available."
      return
    }
    recoveryBackupStatus = "unreadable"
    recoveryBackupMessage = "The backup could not be read."
    console.warn(logPrefix + " recovery backup read failed: " + fileErrorCode(error)
      + " path=" + backupPath)
  }

  function resetRecoveryOperation() {
    recoveryOperation = "idle"
    recoveryErrorCode = ""
    recoveryErrorMessage = ""
    _recoveryExpectedPrimary = ""
    _recoveryReplacementPayload = ""
    _recoveryAction = ""
    _recoveryArchiveCandidate = ""
    _recoveryCurrentArchivePath = ""
    _recoveryStagePath = ""
    _recoveryMarkerPayload = ""
    recoveryArchiveVerified = false
    _recoveryArchiveReaderPath = ""
    _recoveryActionBackupReaderPath = ""
    _recoveryVerifierPath = ""
    _recoveryStageWriterPath = ""
    _recoveryStageVerifierPath = ""
    _recoveryMarkerWriterPath = ""
    _recoveryMarkerVerifierPath = ""
    _recoveryWriteDispatched = false
  }

  function recoveryFailure(code, message) {
    if (_interruptedRecoveryActive) {
      failInterruptedRecovery(message)
      return
    }
    recoveryErrorCode = code
    recoveryErrorMessage = message
    recoveryOperation = "error"
    console.warn(logPrefix + " recovery operation failed: operation=" + _recoveryAction
      + " code=" + code + " path=" + primaryPath)
  }

  function retryRecovery() {
    if (status !== "recovery" || recoveryBusy || hasPendingSave) return false
    if (recoveryOperation === "error" && recoveryArchivePath !== "") return false
    resetRecoveryOperation()
    recoveryArchivePath = ""
    return beginRead("retry")
  }

  function restoreBackup() {
    if (recoveryBackupStatus !== "valid") return false
    return beginRecoveryOperation("restore", "")
  }

  function startFresh() {
    return beginRecoveryOperation("start-fresh", NotesModel.serializeCollection(NotesModel.emptyCollection()))
  }

  function beginRecoveryOperation(action, replacementPayload) {
    if (status !== "recovery" || recoveryBusy || hasPendingSave
        || (action !== "restore" && replacementPayload === "")
        || recoveryArchiveVerified || _readInProgress) return false
    _recoveryAction = action
    _recoveryExpectedPrimary = _lastDiskPayload
    _recoveryReplacementPayload = replacementPayload
    recoveryArchivePath = ""
    recoveryErrorCode = ""
    recoveryErrorMessage = ""
    if (action === "restore") {
      recoveryOperation = "checking-backup"
      _recoveryActionBackupReaderPath = ""
      Qt.callLater(function() {
        if (!root._destroying && root.recoveryOperation === "checking-backup")
          root._recoveryActionBackupReaderPath = root.backupPath
      })
      return true
    }
    beginRecoveryPrimaryCheck()
    return true
  }

  function beginRecoveryPrimaryCheck() {
    if (_destroying || !beginRead("recovery-check")) return false
    recoveryOperation = "checking"
    return true
  }

  function finishRecoveryActionBackupRead(raw) {
    _recoveryActionBackupReaderPath = ""
    if (_destroying || recoveryOperation !== "checking-backup") return
    var result = NotesModel.parse(raw)
    if (raw !== _recoveryBackupRaw || String(raw).trim() === "" || result.status !== "ready") {
      console.warn(logPrefix + " recovery operation aborted because the backup changed: path=" + backupPath)
      resetRecoveryOperation()
      recoveryGeneration++
      inspectRecoveryBackup()
      return
    }
    _recoveryReplacementPayload = NotesModel.serializeCollection(result.collection)
    beginRecoveryPrimaryCheck()
  }

  function failRecoveryActionBackupRead() {
    _recoveryActionBackupReaderPath = ""
    if (_destroying || recoveryOperation !== "checking-backup") return
    console.warn(logPrefix + " recovery operation aborted because the backup could not be revalidated: path=" + backupPath)
    resetRecoveryOperation()
    recoveryGeneration++
    inspectRecoveryBackup()
  }

  function finishRecoveryCheck(raw, exists) {
    if (status !== "recovery" || recoveryOperation !== "checking") return
    if (!exists || raw !== _recoveryExpectedPrimary) {
      console.warn(logPrefix + " recovery operation aborted because the primary changed: path=" + primaryPath)
      resetRecoveryOperation()
      applyParsed(NotesModel.parse(raw), raw, "external")
      return
    }

    var timestamp = new Date().toISOString().replace(/[-:.TZ]/g, "")
    var suffix = Math.floor(Math.random() * 0x100000000).toString(36)
    _recoveryArchiveCandidate = stateDirectory + "/notes.json.recovery-" + timestamp + "-" + suffix
    _recoveryCurrentArchivePath = stateDirectory + "/notes.json.recovery-current-" + timestamp + "-" + suffix
      + "/notes.json"
    _recoveryStagePath = stateDirectory + "/.pinote-recovery-stage-" + timestamp + "-" + suffix
    recoveryOperation = "archiving"
    _archiveProcessStarted = false
    _archiveLaunchPending = true
    var backupToCheck = _recoveryAction === "restore" ? backupPath : ""
    archiveProcess.command = [recoveryHelperPath, "archive", primaryPath,
      _recoveryArchiveCandidate, backupToCheck]
    console.log(logPrefix + " archiving damaged primary: operation=" + _recoveryAction
      + " path=" + _recoveryArchiveCandidate)
    archiveProcess.running = true
  }

  function finishArchiveProcess() {
    if (_destroying || recoveryOperation !== "archiving") return
    recoveryOperation = "verifying-archive"
    _recoveryArchiveReaderPath = _recoveryArchiveCandidate
  }

  function finishArchiveRead(raw) {
    _recoveryArchiveReaderPath = ""
    if (recoveryOperation !== "verifying-archive") return
    if (raw !== _recoveryExpectedPrimary) {
      recoveryFailure("archive-verification-mismatch", "The recovery archive could not be verified.")
      return
    }
    recoveryArchivePath = _recoveryArchiveCandidate
    recoveryArchiveVerified = true
    stageRecoveryReplacement()
  }

  function failArchiveRead(error) {
    _recoveryArchiveReaderPath = ""
    recoveryFailure("archive-failed", "The damaged notes file could not be archived and verified.")
  }

  function stageRecoveryReplacement() {
    if (_destroying || !recoveryArchiveVerified) return false
    recoveryOperation = "staging"
    _recoveryWriteDispatched = false
    _recoveryStageWriterPath = ""
    recoveryStageDispatchTimer.interval = Math.max(1, recoveryStageDelayMs)
    recoveryStageDispatchTimer.restart()
    return true
  }

  function dispatchRecoveryStageWrite() {
    Qt.callLater(function() {
      if (root._destroying || root.recoveryOperation !== "staging") return
      root._recoveryStageWriterPath = root._recoveryStagePath
      Qt.callLater(function() {
        if (root._destroying || root.recoveryOperation !== "staging") return
        root._recoveryWriteDispatched = true
        recoveryStageWriter.setText(root._recoveryReplacementPayload)
      })
    })
  }

  function verifyRecoveryStage() {
    if (_destroying || recoveryOperation !== "staging") return
    _recoveryWriteDispatched = false
    recoveryOperation = "verifying-stage"
    _recoveryStageVerifierPath = ""
    Qt.callLater(function() {
      if (!root._destroying) root._recoveryStageVerifierPath = root._recoveryStagePath
    })
  }

  function finishRecoveryStageVerification(raw) {
    _recoveryStageVerifierPath = ""
    if (recoveryOperation !== "verifying-stage") return
    if (raw !== _recoveryReplacementPayload) {
      recoveryFailure("stage-verification-mismatch", "The staged recovery payload could not be verified.")
      return
    }

    _recoveryMarkerPayload = JSON.stringify({
      version: 1,
      action: _recoveryAction,
      expectedArchive: recoveryArchivePath,
      currentArchive: _recoveryCurrentArchivePath,
      staged: _recoveryStagePath
    }, null, 2) + "\n"
    recoveryOperation = "writing-marker"
    _recoveryMarkerWriterPath = ""
    Qt.callLater(function() {
      if (root._destroying || root.recoveryOperation !== "writing-marker") return
      root._recoveryMarkerWriterPath = root.recoveryMarkerPath
      Qt.callLater(function() {
        if (!root._destroying && root.recoveryOperation === "writing-marker")
          recoveryMarkerWriter.setText(root._recoveryMarkerPayload)
      })
    })
  }

  function failRecoveryStage(error) {
    _recoveryWriteDispatched = false
    recoveryFailure(fileErrorCode(error), "The recovery payload could not be staged.")
  }

  function verifyRecoveryMarker() {
    if (_destroying || recoveryOperation !== "writing-marker") return
    recoveryOperation = "verifying-marker"
    _recoveryMarkerVerifierPath = ""
    Qt.callLater(function() {
      if (!root._destroying) root._recoveryMarkerVerifierPath = root.recoveryMarkerPath
    })
  }

  function finishRecoveryMarkerVerification(raw) {
    _recoveryMarkerVerifierPath = ""
    if (_destroying || recoveryOperation !== "verifying-marker") return
    if (raw !== _recoveryMarkerPayload) {
      recoveryFailure("marker-verification-mismatch", "The recovery transaction marker could not be verified.")
      return
    }
    secureRecoveryFiles()
  }

  function secureRecoveryFiles() {
    if (_destroying) return
    recoveryOperation = "securing-files"
    _permissionProcessStarted = false
    _permissionLaunchPending = true
    recoveryPermissionProcess.command = [recoveryHelperPath, "secure", recoveryArchivePath,
      _recoveryStagePath, recoveryMarkerPath]
    recoveryPermissionProcess.running = true
  }

  function failRecoveryMarker(error) {
    recoveryFailure(fileErrorCode(error), "The recovery transaction marker could not be written.")
  }

  function startRecoveryHandoff(purpose) {
    if (_destroying) return false
    recoveryOperation = "handoff"
    _handoffPurpose = purpose
    _handoffProcessStarted = false
    _handoffLaunchPending = true
    _handoffExitCode = 0
    var command = purpose === "resume"
      ? [recoveryHelperPath, "resume", recoveryArchivePath, _recoveryCurrentArchivePath,
          _recoveryStagePath, primaryPath, recoveryMarkerPath]
      : [recoveryHelperPath, "install", recoveryArchivePath, _recoveryCurrentArchivePath,
          _recoveryStagePath, primaryPath, recoveryMarkerPath]
    if (purpose !== "resume" && recoveryHandoffHook !== "")
      command.push(recoveryHandoffHook)
    handoffProcess.command = command
    handoffProcess.running = true
    return true
  }

  function finishRecoveryHandoff() {
    if (_destroying || recoveryOperation !== "handoff") return
    if (_handoffPurpose === "resume" && _handoffExitCode !== 0) {
      failInterruptedRecovery("The interrupted recovery filesystem handoff failed.")
      return
    }
    if (_handoffExitCode === 75) {
      recoveryFailure("unsafe-link", "Recovery files must not have hard-link aliases.")
      return
    }
    startRecoveryFinalVerification(true)
  }

  function startRecoveryFinalVerification(resetPasses) {
    if (_destroying) return
    if (resetPasses) _recoveryVerificationPasses = 0
    recoveryOperation = "verifying-write"
    _watchRequested = false
    _recoveryVerificationWatchGeneration = _watchGeneration
    _recoveryVerifierPath = ""
    Qt.callLater(function() {
      if (!root._destroying) root._recoveryVerifierPath = root.primaryPath
    })
  }

  function captureRecoveryVerification(raw) {
    _recoveryVerifierPath = ""
    if (_destroying || recoveryOperation !== "verifying-write") return
    _recoveryVerificationRaw = raw
    recoveryFinalVerificationPending()
    recoveryVerificationTimer.interval = Math.max(1, recoveryVerificationDelayMs)
    recoveryVerificationTimer.restart()
  }

  function finishRecoveryVerification() {
    if (recoveryOperation !== "verifying-write") return
    var raw = _recoveryVerificationRaw
    if (_handoffExitCode !== 0) {
      console.warn(logPrefix + " recovery handoff exited without installing the staged file: path=" + primaryPath)
      cleanupRecoveryTransaction(true, "external")
      return
    }
    if (raw === _recoveryExpectedPrimary) {
      recoveryFailure("handoff-failed", "The recovery filesystem handoff did not run.")
      return
    }
    if (raw !== _recoveryReplacementPayload) {
      var retainedArchivePath = recoveryArchivePath
      console.warn(logPrefix + " recovery handoff preserved a conflicting primary: path=" + primaryPath)
      recoveryArchivePath = retainedArchivePath
      cleanupRecoveryTransaction(true, "external")
      return
    }
    if (_watchRequested || _watchGeneration !== _recoveryVerificationWatchGeneration) {
      startRecoveryFinalVerification(true)
      return
    }
    if (_recoveryVerificationPasses < 1) {
      _recoveryVerificationPasses++
      startRecoveryFinalVerification(false)
      return
    }
    startRecoveryIdentityCheck()
  }

  function startRecoveryIdentityCheck() {
    if (_destroying) return
    recoveryOperation = "verifying-identity"
    _identityProcessStarted = false
    _identityLaunchPending = true
    recoveryIdentityProcess.command = ["/usr/bin/test", primaryPath, "-ef", _recoveryStagePath]
    recoveryIdentityProcess.running = true
  }

  function finishRecoveryIdentityCheck(matches) {
    if (_destroying || recoveryOperation !== "verifying-identity") return
    if (_watchRequested || _watchGeneration !== _recoveryVerificationWatchGeneration) {
      startRecoveryFinalVerification(true)
      return
    }
    if (!matches) {
      console.warn(logPrefix + " recovered notes identity changed before completion: path=" + primaryPath)
      cleanupRecoveryTransaction(true, "external")
      return
    }
    recoveryArchivePath = _recoveryCurrentArchivePath
    cleanupRecoveryTransaction(true, "completed")
  }

  function failRecoveryWrite(error) {
    _recoveryWriteDispatched = false
    recoveryFailure(fileErrorCode(error), "The replacement notes file could not be written.")
  }

  function failRecoveryVerification(error) {
    recoveryVerificationTimer.stop()
    _recoveryVerifierPath = ""
    recoveryFailure(fileErrorCode(error), "The replacement notes file could not be read back.")
  }

  function retryRecoveryWrite() {
    if (status !== "recovery" || recoveryOperation !== "error"
        || !recoveryArchiveVerified || recoveryArchivePath === ""
        || _recoveryReplacementPayload === "") return false
    recoveryErrorCode = ""
    recoveryErrorMessage = ""
    return stageRecoveryReplacement()
  }

  function cleanupRecoveryTransaction(removeStage, purpose) {
    var stage = removeStage ? _recoveryStagePath : ""
    _cleanupPurpose = purpose || ""
    recoveryCleanup.command = [
      "/bin/sh", "-c",
      "if [ -n \"$3\" ]; then : > \"$3.ready\"; "
        + "i=0; while [ ! -e \"$3.continue\" ] && [ $i -lt 500 ]; do sleep 0.01; i=$((i + 1)); done; "
        + "[ -e \"$3.continue\" ] || exit 76; fi; "
        + "if [ -n \"$1\" ]; then /usr/bin/rm -f -- \"$1\" || exit $?; fi; /usr/bin/rm -f -- \"$2\"",
      "pinote-recovery-cleanup", stage, recoveryMarkerPath, recoveryCleanupHook
    ]
    _cleanupProcessStarted = false
    _cleanupLaunchPending = true
    recoveryCleanup.running = true
  }

  function finishRecoveryCleanup(success) {
    var purpose = _cleanupPurpose
    _cleanupPurpose = ""
    if (_destroying || purpose === "") return
    if (!success) {
      if (_interruptedRecoveryActive) {
        failInterruptedRecovery("Recovery finished, but its transaction files could not be removed.")
        return
      }
      recoveryFailure("cleanup-failed", "Recovery finished, but its transaction files could not be removed.")
      return
    }
    _interruptedRecoveryActive = false
    if (purpose === "completed") {
      var completedAction = _recoveryAction
      recoveryOperation = "done"
      recoveryErrorCode = ""
      recoveryErrorMessage = ""
      console.log(logPrefix + " recovery operation completed: operation=" + completedAction
        + " archive=" + recoveryArchivePath)
    } else {
      resetRecoveryOperation()
    }
    errorOperation = "post-recovery-check"
    errorCode = "recovery-reload-required"
    errorMessage = purpose === "external"
      ? "The notes file changed during recovery. Check it again before editing."
      : "Recovery finished. Check the notes file again before editing."
    errorPath = primaryPath
    status = "load-error"
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
    if (recoveryBusy) return
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
    issueSummary = ""
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
      _directoryLaunchPending = true
      ensureDirectory.running = true
      return true
    }
    if (failedOperation === "recovery") {
      inspectRecoveryMarker()
      return true
    }
    return beginRead("retry")
  }

  function recoveryMetadataPath(value, prefix) {
    var path = String(value || "")
    var expectedPrefix = stateDirectory + "/" + prefix
    return path.indexOf(expectedPrefix) === 0 && path.indexOf("/", stateDirectory.length + 1) === -1
  }

  function recoveryCurrentArchiveMetadataPath(value) {
    var path = String(value || "")
    var prefix = stateDirectory + "/notes.json.recovery-current-"
    if (path.indexOf(prefix) !== 0) return false
    var suffix = path.slice(prefix.length)
    return /^[A-Za-z0-9-]+\/notes\.json$/.test(suffix)
  }

  function inspectRecoveryMarker() {
    _transactionMarkerReaderPath = ""
    Qt.callLater(function() {
      if (!root._destroying) root._transactionMarkerReaderPath = root.recoveryMarkerPath
    })
  }

  function finishTransactionMarkerRead(raw) {
    _transactionMarkerReaderPath = ""
    if (_destroying) return
    var marker
    try {
      marker = JSON.parse(String(raw))
    } catch (error) {
      failInterruptedRecovery("The recovery transaction marker is invalid.")
      return
    }
    if (!marker || marker.version !== 1
        || (marker.action !== "restore" && marker.action !== "start-fresh")
        || !recoveryMetadataPath(marker.expectedArchive, "notes.json.recovery-")
        || !recoveryCurrentArchiveMetadataPath(marker.currentArchive)
        || !recoveryMetadataPath(marker.staged, ".pinote-recovery-stage-")) {
      failInterruptedRecovery("The recovery transaction marker contains unsafe paths.")
      return
    }

    _recoveryAction = marker.action
    recoveryArchivePath = marker.expectedArchive
    _recoveryArchiveCandidate = marker.expectedArchive
    _recoveryCurrentArchivePath = marker.currentArchive
    _recoveryStagePath = marker.staged
    _interruptedRecoveryActive = true
    recoveryOperation = "interrupted"
    _transactionStageReaderPath = marker.staged
  }

  function finishTransactionStageRead(raw) {
    _transactionStageReaderPath = ""
    if (_destroying) return
    var result = NotesModel.parse(raw)
    var canonical = result.status === "ready" ? NotesModel.serializeCollection(result.collection) : ""
    if (canonical === "" || canonical !== raw
        || (_recoveryAction === "start-fresh"
          && canonical !== NotesModel.serializeCollection(NotesModel.emptyCollection()))) {
      failInterruptedRecovery("The staged recovery payload is invalid.")
      return
    }
    _recoveryReplacementPayload = canonical
    beginRead("interrupted")
  }

  function failTransactionStageRead(error) {
    _transactionStageReaderPath = ""
    if (error !== FileViewError.FileNotFound) {
      failInterruptedRecovery("The staged recovery payload could not be read.")
      return
    }
    _recoveryReplacementPayload = ""
    beginRead("interrupted")
  }

  function finishInterruptedPrimary(raw, purpose) {
    if (_destroying) return
    if (purpose === "interrupted-result") {
      captureRecoveryVerification(raw)
      return
    }

    cleanupRecoveryTransaction(true, "interrupted")
  }

  function resumeInterruptedRecovery() {
    if (_destroying) return
    if (_recoveryReplacementPayload === "" || _recoveryStagePath === "") {
      failInterruptedRecovery("Recovery was interrupted and no staged replacement is available.")
      return
    }
    startRecoveryHandoff("resume")
  }

  function failInterruptedRecovery(message) {
    recoveryOperation = "error"
    errorOperation = "recovery"
    errorCode = "interrupted-recovery"
    errorMessage = message
    errorPath = recoveryMarkerPath
    status = "load-error"
    console.warn(logPrefix + " interrupted recovery requires attention: path=" + recoveryMarkerPath)
  }

  function finishMissingTransactionMarker(error) {
    _transactionMarkerReaderPath = ""
    if (error === FileViewError.FileNotFound) {
      _interruptedRecoveryActive = false
      beginRead("initial")
      return
    }
    failInterruptedRecovery("The recovery transaction marker could not be read.")
  }

  function initialize() {
    if (_initialized || !autoStart) return
    _initialized = true
    if (stateRoot === "") {
      errorOperation = "resolve-state-directory"
      errorCode = "invalid-state-directory"
      errorMessage = "Neither XDG_STATE_HOME nor HOME resolves to an absolute path."
      status = "load-error"
      console.warn(logPrefix + " state directory could not be resolved")
    } else {
      console.log(logPrefix + " initializing state path=" + stateDirectory)
      ensureDirectory.command = ["/usr/bin/install", "-d", "-m", "700", "--", stateDirectory]
      _directoryLaunchPending = true
      ensureDirectory.running = true
    }
  }

  function finishDirectoryProbe(error) {
    if (error !== FileViewError.NotAFile) {
      errorOperation = "create-directory"
      errorCode = error === FileViewError.FileNotFound ? "directory-create-failed" : fileErrorCode(error)
      errorMessage = error === FileViewError.FileNotFound
        ? "The " + displayName + " state directory could not be created."
        : String(FileViewError.toString(error))
      errorPath = stateDirectory
      status = "load-error"
      console.warn(logPrefix + " state directory unavailable: " + errorCode + " path=" + stateDirectory)
      return
    }

    _watchPath = stateDirectory
    inspectRecoveryMarker()
  }

  function rejectNonDirectoryStatePath() {
    errorOperation = "create-directory"
    errorCode = "not-a-directory"
    errorMessage = "The " + displayName + " state directory path is not a directory."
    errorPath = stateDirectory
    status = "load-error"
    console.warn(logPrefix + " state path is not a directory: path=" + stateDirectory)
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
    console.warn(logPrefix + " save failed: " + errorCode + " path=" + primaryPath)
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
    console.warn(logPrefix + " backup save failed: " + backupErrorCode + " path=" + backupPath)
  }

  function handleBackupFailed(error) {
    failActiveBackup(fileErrorCode(error), String(FileViewError.toString(error)))
  }

  Process {
    id: ensureDirectory
    running: false
    onStarted: root._directoryProcessStarted = true
    onExited: function(exitCode) {
      var exitStatus = arguments[1]
      root._directoryLaunchPending = false
      root._directoryProcessStarted = false
      if (root._destroying) return
      if (exitCode !== 0 || exitStatus !== 0) {
        root.errorOperation = "create-directory"
        root.errorCode = "directory-create-failed"
        root.errorMessage = "The " + root.displayName + " state directory could not be created."
        root.errorPath = root.stateDirectory
        root.status = "load-error"
        return
      }
      root._probePath = root.stateDirectory
    }
    onRunningChanged: {
      if (!running && root._directoryLaunchPending && !root._directoryProcessStarted) {
        root._directoryLaunchPending = false
        if (!root._destroying) {
          root.errorOperation = "create-directory"
          root.errorCode = "directory-create-failed"
          root.errorMessage = "The " + root.displayName + " state directory could not be created."
          root.errorPath = root.stateDirectory
          root.status = "load-error"
        }
      }
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
    id: transactionMarkerReader
    path: root._transactionMarkerReaderPath
    preload: root._transactionMarkerReaderPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.finishTransactionMarkerRead(text())
    onLoadFailed: function(error) { root.finishMissingTransactionMarker(error) }
  }

  FileView {
    id: transactionStageReader
    path: root._transactionStageReaderPath
    preload: root._transactionStageReaderPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.finishTransactionStageRead(text())
    onLoadFailed: function(error) { root.failTransactionStageRead(error) }
  }

  FileView {
    id: recoveryBackupReader
    path: root._recoveryBackupReaderPath
    preload: root._recoveryBackupReaderPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.finishRecoveryBackupRead(text())
    onLoadFailed: function(error) { root.failRecoveryBackupRead(error) }
  }

  FileView {
    id: directoryWatcher
    path: root._watchPath
    preload: root._watchPath !== ""
    blockWrites: true
    watchChanges: root._watchPath !== ""
    printErrors: false
    onFileChanged: {
      root._watchGeneration++
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

  Timer {
    id: recoveryStageDispatchTimer
    interval: 1
    repeat: false
    onTriggered: root.dispatchRecoveryStageWrite()
  }

  Timer {
    id: recoveryVerificationTimer
    interval: 1
    repeat: false
    onTriggered: root.finishRecoveryVerification()
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

  Process {
    id: archiveProcess
    running: false
    onStarted: root._archiveProcessStarted = true
    onExited: function(exitCode) {
      var exitStatus = arguments[1]
      root._archiveLaunchPending = false
      root._archiveProcessStarted = false
      if (root._destroying || root.recoveryOperation !== "archiving") return
      if (exitCode !== 0 || exitStatus !== 0) {
        if (exitStatus === 0 && exitCode === 75)
          root.recoveryFailure("unsafe-link", "Recovery files must not have hard-link aliases.")
        else if (exitStatus === 0 && (exitCode === 73 || exitCode === 74))
          root.recoveryFailure("unsafe-symlink", "Recovery requires regular note and backup files inside the state directory.")
        else
          root.recoveryFailure("archive-failed", "The archive process failed.")
        return
      }
      root.finishArchiveProcess()
    }
    onRunningChanged: {
      if (!running && root._archiveLaunchPending && !root._archiveProcessStarted) {
        root._archiveLaunchPending = false
        if (!root._destroying && root.recoveryOperation === "archiving")
          root.recoveryFailure("archive-start-failed", "The archive process could not be started.")
      }
    }
  }

  FileView {
    id: recoveryArchiveReader
    path: root._recoveryArchiveReaderPath
    preload: root._recoveryArchiveReaderPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.finishArchiveRead(text())
    onLoadFailed: function(error) { root.failArchiveRead(error) }
  }

  FileView {
    id: recoveryActionBackupReader
    path: root._recoveryActionBackupReaderPath
    preload: root._recoveryActionBackupReaderPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.finishRecoveryActionBackupRead(text())
    onLoadFailed: root.failRecoveryActionBackupRead()
  }

  FileView {
    id: recoveryStageWriter
    path: root._recoveryStageWriterPath
    preload: false
    blockLoading: true
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onSaved: root.verifyRecoveryStage()
    onSaveFailed: function(error) { root.failRecoveryStage(error) }
  }

  FileView {
    id: recoveryStageVerifier
    path: root._recoveryStageVerifierPath
    preload: root._recoveryStageVerifierPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.finishRecoveryStageVerification(text())
    onLoadFailed: function(error) { root.failRecoveryStage(error) }
  }

  FileView {
    id: recoveryMarkerWriter
    path: root._recoveryMarkerWriterPath
    preload: false
    blockLoading: true
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onSaved: root.verifyRecoveryMarker()
    onSaveFailed: function(error) { root.failRecoveryMarker(error) }
  }

  FileView {
    id: recoveryMarkerVerifier
    path: root._recoveryMarkerVerifierPath
    preload: root._recoveryMarkerVerifierPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.finishRecoveryMarkerVerification(text())
    onLoadFailed: function(error) { root.failRecoveryMarker(error) }
  }

  Process {
    id: recoveryPermissionProcess
    running: false
    onStarted: root._permissionProcessStarted = true
    onExited: function(exitCode) {
      var exitStatus = arguments[1]
      root._permissionLaunchPending = false
      root._permissionProcessStarted = false
      if (root._destroying || root.recoveryOperation !== "securing-files") return
      if (exitCode !== 0 || exitStatus !== 0) {
        if (exitStatus === 0 && exitCode === 75)
          root.recoveryFailure("unsafe-link", "Recovery files must not have hard-link aliases.")
        else
          root.recoveryFailure("permission-failed", "Recovery files could not be secured.")
        return
      }
      root.startRecoveryHandoff("install")
    }
    onRunningChanged: {
      if (!running && root._permissionLaunchPending && !root._permissionProcessStarted) {
        root._permissionLaunchPending = false
        if (!root._destroying && root.recoveryOperation === "securing-files")
          root.recoveryFailure("permission-start-failed", "Recovery file permissions could not be secured.")
      }
    }
  }

  Process {
    id: handoffProcess
    running: false
    onStarted: root._handoffProcessStarted = true
    onExited: function(exitCode) {
      var exitStatus = arguments[1]
      root._handoffLaunchPending = false
      root._handoffProcessStarted = false
      root._handoffExitCode = exitStatus === 0 ? exitCode : -1
      root.finishRecoveryHandoff()
    }
    onRunningChanged: {
      if (!running && root._handoffLaunchPending && !root._handoffProcessStarted) {
        root._handoffLaunchPending = false
        if (!root._destroying && root.recoveryOperation === "handoff") {
          if (root._handoffPurpose === "resume")
            root.failInterruptedRecovery("The interrupted recovery filesystem helper could not be started.")
          else
            root.recoveryFailure("handoff-start-failed", "The recovery filesystem helper could not be started.")
        }
      }
    }
  }

  Process {
    id: recoveryIdentityProcess
    running: false
    onStarted: root._identityProcessStarted = true
    onExited: function(exitCode) {
      var exitStatus = arguments[1]
      root._identityLaunchPending = false
      root._identityProcessStarted = false
      root.finishRecoveryIdentityCheck(exitCode === 0 && exitStatus === 0)
    }
    onRunningChanged: {
      if (!running && root._identityLaunchPending && !root._identityProcessStarted) {
        root._identityLaunchPending = false
        if (!root._destroying && root.recoveryOperation === "verifying-identity")
          root.recoveryFailure("identity-start-failed", "The recovered notes file identity could not be verified.")
      }
    }
  }

  Process {
    id: recoveryCleanup
    running: false
    onStarted: root._cleanupProcessStarted = true
    onExited: function(exitCode) {
      var exitStatus = arguments[1]
      root._cleanupLaunchPending = false
      root._cleanupProcessStarted = false
      root.finishRecoveryCleanup(exitCode === 0 && exitStatus === 0)
    }
    onRunningChanged: {
      if (!running && root._cleanupLaunchPending && !root._cleanupProcessStarted) {
        root._cleanupLaunchPending = false
        root.finishRecoveryCleanup(false)
      }
    }
  }

  FileView {
    id: recoveryVerifier
    path: root._recoveryVerifierPath
    preload: root._recoveryVerifierPath !== ""
    blockWrites: true
    watchChanges: false
    printErrors: false
    onLoaded: root.captureRecoveryVerification(text())
    onLoadFailed: function(error) { root.failRecoveryVerification(error) }
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

  onAutoStartChanged: initialize()
  Component.onCompleted: initialize()

  Component.onDestruction: {
    _destroying = true
    watcherTimer.stop()
    recoveryStageDispatchTimer.stop()
    recoveryVerificationTimer.stop()
    _backupInspectionGeneration++
    if (archiveProcess.running) archiveProcess.running = false
    if (recoveryPermissionProcess.running) recoveryPermissionProcess.running = false
    if (recoveryIdentityProcess.running) recoveryIdentityProcess.running = false
    if (_recoveryWriteDispatched) recoveryStageWriter.waitForJob()
    if (recoveryOperation === "verifying-stage") recoveryStageVerifier.waitForJob()
    if (recoveryOperation === "writing-marker") recoveryMarkerWriter.waitForJob()
    if (recoveryOperation === "verifying-marker") recoveryMarkerVerifier.waitForJob()
    if (recoveryOperation === "verifying-write") recoveryVerifier.waitForJob()
    if (!hasPendingSave || !_latestCommittedSnapshot) return
    var activePayload = _queueState.activePrimary ? _queueState.activePrimary.payload : ""
    if (_primaryDispatched) primaryWriter.waitForJob()
    if (_verificationSnapshot) primaryVerifier.waitForJob()
    var diskPayload = shutdownConflictReader.text()
    if (diskPayload !== _lastDiskPayload && diskPayload !== activePayload) {
      console.warn(logPrefix + " shutdown save skipped because the primary file changed externally: path=" + primaryPath)
      return
    }
    shutdownWriter.setText(_latestCommittedSnapshot.payload)
    shutdownWriter.waitForJob()
    if (shutdownVerifier.text() !== _latestCommittedSnapshot.payload)
      console.warn(logPrefix + " shutdown save verification failed: path=" + primaryPath)
  }
}

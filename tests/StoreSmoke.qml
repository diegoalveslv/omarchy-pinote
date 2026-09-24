import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
  id: testRoot

  property bool mutationsSubmitted: false
  property string retainedId: ""
  property string processStage: ""
  property bool processStarted: false
  property bool externalSubmitted: false
  property bool recoveryReloadSubmitted: false
  property int recoveryCount: 0
  readonly property string mode: String(Quickshell.env("PINOTE_STORE_SMOKE_MODE") || "write")

  function externalPayload(content, id) {
    return JSON.stringify({
      version: 1,
      notes: [{
        id: id,
        content: content,
        createdAt: "2026-09-10T12:00:00.000Z",
        updatedAt: "2026-09-10T12:00:00.000Z"
      }]
    }, null, 2) + "\n"
  }

  function advance() {
    if (store.status === "load-error" && store.errorCode === "recovery-reload-required"
        && !recoveryReloadSubmitted) {
      recoveryReloadSubmitted = true
      if (!store.retryLoad()) {
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-reload-rejected")
        Qt.quit()
      }
      return
    }

    if (mode === "interrupted-abandon" && store.status === "recovery"
        && !mutationsSubmitted) {
      mutationsSubmitted = true
      recoveryAbandonTimer.restart()
      return
    }

    if (mode === "interrupted-resume" && store.status === "ready") {
      if (store.collection.notes.length === 1
          && store.collection.notes[0].content === "Interrupted replacement")
        console.log("PINOTE_STORE_INTERRUPTED_RESUME_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED interrupted-resume")
      Qt.quit()
      return
    }

    if (mode === "interrupted-resume-helper-failure" && store.status === "load-error"
        && processStage === "") {
      if (store.errorOperation !== "recovery" || store.errorCode !== "interrupted-recovery") {
        console.error("PINOTE_STORE_SMOKE_FAILED interrupted-helper-error=" + store.errorCode)
        Qt.quit()
        return
      }
      processStage = "retrying"
      store.recoveryHelperPath = String(Quickshell.env("PINOTE_RECOVERY_RETRY_HELPER_PATH"))
      store.recoveryCleanupHook = String(Quickshell.env("PINOTE_RECOVERY_RETRY_CLEANUP_HOOK") || "")
      if (!store.retryLoad()) {
        console.error("PINOTE_STORE_SMOKE_FAILED interrupted-helper-retry")
        Qt.quit()
      }
      return
    }

    if (mode === "interrupted-resume-helper-failure" && processStage === "retrying"
        && store.status === "ready") {
      if (store.collection.notes.length === 1
          && store.collection.notes[0].content === "Interrupted replacement")
        console.log("PINOTE_STORE_INTERRUPTED_HELPER_RETRY_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED interrupted-helper-result")
      Qt.quit()
      return
    }

    if (mode === "interrupted-special-file" && store.status === "load-error") {
      if (store.errorOperation === "recovery" && store.errorCode === "interrupted-recovery")
        console.log("PINOTE_STORE_INTERRUPTED_SPECIAL_FILE_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED interrupted-special-file=" + store.errorCode)
      Qt.quit()
      return
    }

    if (mode === "recovery-restore" && store.status === "recovery"
        && store.recoveryBackupStatus === "valid" && !mutationsSubmitted) {
      mutationsSubmitted = true
      if (store.recoveryAcceptedRecords !== 1 || store.recoveryRejectedRecords !== 1
          || !store.restoreBackup()) {
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-restore-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-backup-change" && store.status === "recovery"
        && store.recoveryBackupStatus === "valid" && !mutationsSubmitted) {
      mutationsSubmitted = true
      processStage = "changing-backup"
      backupExternalWriter.setText(externalPayload("Changed backup note", "changed-backup"))
      return
    }

    if (mode === "recovery-backup-change" && processStage === "backup-revalidating"
        && store.status === "recovery" && store.recoveryOperation === "idle"
        && store.recoveryBackupStatus === "valid") {
      console.log("PINOTE_STORE_RECOVERY_BACKUP_CHANGE_OK")
      Qt.quit()
      return
    }

    if (mode === "recovery-conflict" && store.status === "recovery"
        && store.recoveryBackupStatus === "valid" && !mutationsSubmitted) {
      mutationsSubmitted = true
      if (!store.restoreBackup()) {
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-conflict-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-conflict" && mutationsSubmitted && store.status === "ready"
        && store.collection.notes.length === 1
        && store.collection.notes[0].content === "External cleanup note") {
      conflictResultTimer.restart()
      return
    }

    if (mode === "recovery-inplace-change" && store.status === "recovery"
        && store.recoveryBackupStatus === "missing" && !mutationsSubmitted) {
      mutationsSubmitted = true
      if (!store.startFresh()) {
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-inplace-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-inplace-change" && mutationsSubmitted && store.status === "ready"
        && store.collection.notes.length === 1
        && store.collection.notes[0].content === "External in-place note") {
      console.log("PINOTE_STORE_RECOVERY_INPLACE_OK")
      Qt.quit()
      return
    }

    if (mode === "recovery-identical-postinstall-race" && store.status === "recovery"
        && store.recoveryBackupStatus === "missing" && !mutationsSubmitted) {
      mutationsSubmitted = true
      if (!store.startFresh()) {
        console.error("PINOTE_STORE_SMOKE_FAILED identical-postinstall-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-identical-postinstall-race" && mutationsSubmitted
        && store.status === "ready" && store.recoveryOperation === "idle"
        && store.collection.notes.length === 0) {
      if (store.recoveryArchivePath.indexOf("notes.json.recovery-") !== -1
          && store.recoveryArchivePath.indexOf("notes.json.recovery-current-") === -1)
        console.log("PINOTE_STORE_RECOVERY_IDENTICAL_POSTINSTALL_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED identical-postinstall-cleanup")
      Qt.quit()
      return
    }

    if (mode === "recovery-identical-handoff-failure" && store.status === "recovery"
        && store.recoveryBackupStatus === "missing" && !mutationsSubmitted) {
      mutationsSubmitted = true
      if (!store.startFresh()) {
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-identical-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-identical-handoff-failure" && mutationsSubmitted
        && store.status === "ready" && store.collection.notes.length === 0
        && store.recoveryOperation === "idle") {
      console.log("PINOTE_STORE_RECOVERY_IDENTICAL_FAILURE_OK")
      Qt.quit()
      return
    }

    if ((mode === "recovery-symlink-primary" || mode === "recovery-symlink-backup")
        && store.status === "recovery" && !mutationsSubmitted
        && (store.recoveryBackupStatus === "missing" || store.recoveryBackupStatus === "valid")) {
      mutationsSubmitted = true
      var started = mode === "recovery-symlink-primary" ? store.startFresh() : store.restoreBackup()
      if (!started) {
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-symlink-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-hardlink-primary" && store.status === "recovery"
        && store.recoveryBackupStatus === "missing" && !mutationsSubmitted) {
      mutationsSubmitted = true
      if (!store.startFresh()) {
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-hardlink-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-hardlink-primary" && store.recoveryOperation === "error") {
      if (store.recoveryErrorCode === "unsafe-link")
        console.log("PINOTE_STORE_RECOVERY_HARDLINK_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-hardlink-error=" + store.recoveryErrorCode)
      Qt.quit()
      return
    }

    if ((mode === "recovery-symlink-primary" || mode === "recovery-symlink-backup")
        && store.recoveryOperation === "error") {
      if (store.recoveryErrorCode === "unsafe-symlink")
        console.log("PINOTE_STORE_RECOVERY_SYMLINK_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-symlink-error=" + store.recoveryErrorCode)
      Qt.quit()
      return
    }

    if (mode === "recovery-restore" && mutationsSubmitted && store.status === "ready"
        && store.recoveryOperation === "done") {
      if (store.collection.notes.length === 1
          && store.collection.notes[0].content === "Backup recovery note"
          && store.recoveryArchivePath !== "")
        console.log("PINOTE_STORE_RECOVERY_RESTORE_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-restore-result")
      Qt.quit()
      return
    }

    if (mode === "recovery-reset" && store.status === "recovery"
        && store.recoveryBackupStatus === "valid" && !mutationsSubmitted) {
      mutationsSubmitted = true
      if (!store.startFresh()) {
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-reset-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-write-retry" && store.status === "recovery"
        && store.recoveryBackupStatus === "valid" && !mutationsSubmitted) {
      mutationsSubmitted = true
      processStage = "waiting-archive"
      if (!store.startFresh()) {
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-write-retry-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-repeat" && store.status === "recovery"
        && store.recoveryBackupStatus === "missing" && !store.recoveryBusy) {
      if (processStage === "" || processStage === "waiting-second-recovery") {
        processStage = recoveryCount === 0 ? "first-recovery" : "second-recovery"
        if (!store.startFresh()) {
          console.error("PINOTE_STORE_SMOKE_FAILED repeated-recovery-start")
          Qt.quit()
        }
      }
      return
    }

    if (mode === "recovery-repeat" && store.status === "ready") {
      if (processStage === "first-recovery") {
        recoveryCount = 1
        processStage = "writing-second-damage"
        externalWriter.setText("{second-damaged-primary")
      } else if (processStage === "second-recovery") {
        console.log("PINOTE_STORE_RECOVERY_REPEAT_OK")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-helper-failure" && store.status === "recovery"
        && store.recoveryBackupStatus === "missing" && !mutationsSubmitted) {
      mutationsSubmitted = true
      store.startFresh()
      return
    }

    if ((mode === "recovery-handoff-retry" || mode === "recovery-shutdown-marker")
        && store.status === "recovery" && store.recoveryBackupStatus === "missing"
        && !mutationsSubmitted) {
      mutationsSubmitted = true
      if (!store.startFresh()) {
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-lifecycle-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-verification-race" && store.status === "recovery"
        && store.recoveryBackupStatus === "missing" && !mutationsSubmitted) {
      mutationsSubmitted = true
      if (!store.startFresh()) {
        console.error("PINOTE_STORE_SMOKE_FAILED verification-race-start")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-verification-race" && processStage === "race-write"
        && store.status === "ready" && store.collection.notes.length === 1
        && store.collection.notes[0].content === "External verification note") {
      console.log("PINOTE_STORE_RECOVERY_VERIFICATION_RACE_OK")
      Qt.quit()
      return
    }

    if (mode === "recovery-handoff-retry" && store.recoveryOperation === "error"
        && processStage === "") {
      processStage = "retried"
      if (!store.retryRecoveryWrite()) {
        console.error("PINOTE_STORE_SMOKE_FAILED handoff-retry-dispatch")
        Qt.quit()
      }
      return
    }

    if (mode === "recovery-handoff-retry" && processStage === "retried"
        && store.status === "ready" && store.collection.notes.length === 0) {
      console.log("PINOTE_STORE_RECOVERY_HANDOFF_RETRY_OK")
      Qt.quit()
      return
    }

    if (mode === "recovery-shutdown-marker" && store.recoveryOperation === "handoff") {
      console.log("PINOTE_STORE_RECOVERY_SHUTDOWN_MARKER_OK")
      Qt.quit()
      return
    }

    if (mode === "recovery-helper-failure" && store.recoveryOperation === "error") {
      if (store.recoveryErrorCode === "archive-start-failed"
          || store.recoveryErrorCode === "handoff-failed"
          || store.recoveryErrorCode === "handoff-start-failed")
        console.log("PINOTE_STORE_RECOVERY_HELPER_FAILURE_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED helper-error=" + store.recoveryErrorCode)
      Qt.quit()
      return
    }

    if (mode === "recovery-write-retry" && processStage === "stage-locked"
        && store.recoveryOperation === "error") {
      processStage = "stage-unlocking"
      pathProcess.command = ["chmod", "700", store.stateDirectory]
      pathProcess.running = true
      return
    }

    if (mode === "recovery-write-retry" && processStage === "stage-retried"
        && store.status === "ready" && store.collection.notes.length === 0) {
      console.log("PINOTE_STORE_RECOVERY_WRITE_RETRY_OK")
      Qt.quit()
      return
    }

    if (mode === "recovery-reset" && mutationsSubmitted && store.status === "ready"
        && store.recoveryOperation === "done") {
      if (store.collection.notes.length === 0 && store.recoveryArchivePath !== "")
        console.log("PINOTE_STORE_RECOVERY_RESET_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-reset-result")
      Qt.quit()
      return
    }

    if (mode === "recovery-missing-backup" && store.status === "recovery"
        && store.recoveryBackupStatus === "missing") {
      if (!store.recoveryBackupAvailable)
        console.log("PINOTE_STORE_RECOVERY_MISSING_BACKUP_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-missing-backup")
      Qt.quit()
      return
    }

    if (mode === "recovery-invalid-backup" && store.status === "recovery"
        && store.recoveryBackupStatus === "invalid") {
      if (!store.recoveryBackupAvailable)
        console.log("PINOTE_STORE_RECOVERY_INVALID_BACKUP_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED recovery-invalid-backup")
      Qt.quit()
      return
    }

    if (mode === "recovery-archive-failure" && store.status === "recovery"
        && store.recoveryBackupStatus === "missing" && !mutationsSubmitted) {
      mutationsSubmitted = true
      processStage = "archive-locking"
      pathProcess.command = ["chmod", "500", store.stateDirectory]
      pathProcess.running = true
      return
    }

    if (mode === "recovery-archive-failure" && processStage === "archive-started"
        && store.recoveryOperation === "error") {
      if (store.recoveryErrorCode !== "archive-failed") {
        console.error("PINOTE_STORE_SMOKE_FAILED archive-error=" + store.recoveryErrorCode)
        Qt.quit()
        return
      }
      processStage = "archive-unlocking"
      pathProcess.command = ["chmod", "700", store.stateDirectory]
      pathProcess.running = true
      return
    }

    if (mode === "unsupported" && store.status === "unsupported") {
      if (store.unsupportedVersion === 1.5)
        console.log("PINOTE_STORE_UNSUPPORTED_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED unsupported-version=" + store.unsupportedVersion)
      Qt.quit()
      return
    }

    if (mode === "expect-load-error" && store.status === "load-error") {
      if (store.errorCode === "not-a-file") console.log("PINOTE_STORE_LOAD_ERROR_OK")
      else console.error("PINOTE_STORE_SMOKE_FAILED load-error-code=" + store.errorCode)
      Qt.quit()
      return
    }

    if (mode === "expect-permission-load" && store.status === "load-error") {
      if (store.errorCode === "permission-denied") console.log("PINOTE_STORE_PERMISSION_OK")
      else console.error("PINOTE_STORE_SMOKE_FAILED permission-code=" + store.errorCode)
      Qt.quit()
      return
    }

    if (mode === "reload" && !mutationsSubmitted && store.status === "ready") {
      mutationsSubmitted = true
      if (store.collection.notes.length === 1
          && store.collection.notes[0].content === "Updated note\nwith two lines")
        console.log("PINOTE_STORE_RELOAD_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED reload-model")
      Qt.quit()
      return
    }

    if (mode === "external" && store.status === "ready") {
      if (!externalSubmitted) {
        externalSubmitted = true
        externalWriter.setText(externalPayload("External change", "external-note"))
      } else if (store.collection.notes.length === 1
          && store.collection.notes[0].content === "External change") {
        console.log("PINOTE_STORE_EXTERNAL_OK")
        Qt.quit()
      }
      return
    }

    if (mode === "save-retry" && !mutationsSubmitted && store.status === "ready") {
      mutationsSubmitted = true
      processStage = "blocking"
      pathProcess.command = ["mkdir", store.primaryPath]
      pathProcess.running = true
      return
    }

    if (mode === "backup-retry" && !mutationsSubmitted && store.status === "ready") {
      mutationsSubmitted = true
      processStage = "backup-blocking"
      pathProcess.command = ["mkdir", store.backupPath]
      pathProcess.running = true
      return
    }

    if (mode === "dirty-external" && !mutationsSubmitted && store.status === "ready") {
      mutationsSubmitted = true
      processStage = "dirty-blocking"
      pathProcess.command = ["mkdir", store.primaryPath]
      pathProcess.running = true
      return
    }

    if (mode === "verify-mismatch" && !mutationsSubmitted && store.status === "ready") {
      mutationsSubmitted = true
      store.createNote("Local verification candidate")
      return
    }

    if (mode === "shutdown" && !mutationsSubmitted && store.status === "ready") {
      mutationsSubmitted = true
      var kept = store.createNote("Before shutdown")
      var removed = store.createNote("Remove before shutdown")
      store.updateNote(kept.note.id, "Latest shutdown snapshot")
      store.deleteNote(removed.note.id)
      console.log("PINOTE_STORE_SHUTDOWN_STARTED")
      Qt.quit()
      return
    }

    if (mode === "save-retry" && processStage === "blocked" && store.status === "save-error") {
      processStage = "removing"
      pathProcess.command = ["rmdir", store.primaryPath]
      pathProcess.running = true
      return
    }

    if (mode === "save-retry" && processStage === "retried" && store.status === "ready"
        && store.durable && store.backupStatus === "ready") {
      console.log("PINOTE_STORE_RETRY_OK")
      Qt.quit()
      return
    }

    if (mode === "backup-retry" && processStage === "backup-blocked"
        && store.backupStatus === "error") {
      processStage = "backup-removing"
      pathProcess.command = ["rmdir", store.backupPath]
      pathProcess.running = true
      return
    }

    if (mode === "backup-retry" && processStage === "backup-retried"
        && store.status === "ready" && store.backupStatus === "ready") {
      console.log("PINOTE_STORE_BACKUP_RETRY_OK")
      Qt.quit()
      return
    }

    if (mode === "dirty-external" && processStage === "dirty-blocked"
        && store.status === "save-error") {
      processStage = "dirty-removing"
      pathProcess.command = ["rmdir", store.primaryPath]
      pathProcess.running = true
      return
    }

    if (mode === "verify-mismatch" && store.status === "save-error") {
      if (store.errorCode === "verification-mismatch")
        console.log("PINOTE_STORE_VERIFY_MISMATCH_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED verification-code=" + store.errorCode)
      Qt.quit()
      return
    }

    if (!mutationsSubmitted && store.status === "ready") {
      mutationsSubmitted = true
      var first = store.createNote("First note")
      var second = store.createNote("Temporary note")
      if (!first.ok || !second.ok) {
        console.error("PINOTE_STORE_SMOKE_FAILED mutation first="
          + JSON.stringify(first.issues || []) + " second=" + JSON.stringify(second.issues || []))
        Qt.quit()
        return
      }

      retainedId = first.note.id
      store.updateNote(first.note.id, "Updated note\nwith two lines")
      store.deleteNote(second.note.id)
      return
    }

    if (mode === "write" && mutationsSubmitted && store.status === "ready" && store.durable
        && store.backupStatus === "ready") {
      if (store.collection.notes.length !== 1
          || store.collection.notes[0].id !== retainedId
          || store.collection.notes[0].content !== "Updated note\nwith two lines") {
        console.error("PINOTE_STORE_SMOKE_FAILED final-model")
      } else {
        console.log("PINOTE_STORE_SMOKE_OK")
      }
      Qt.quit()
    }
  }

  NotesStore {
    id: store
    recoveryHandoffHook: String(Quickshell.env("PINOTE_RECOVERY_HANDOFF_HOOK") || "")
    recoveryCleanupHook: String(Quickshell.env("PINOTE_RECOVERY_CLEANUP_HOOK") || "")
    recoveryStageDelayMs: Number(Quickshell.env("PINOTE_RECOVERY_STAGE_DELAY_MS") || 0)
    recoveryHelperPath: String(Quickshell.env("PINOTE_RECOVERY_HELPER_PATH") || "") !== ""
      ? String(Quickshell.env("PINOTE_RECOVERY_HELPER_PATH"))
      : String(Qt.resolvedUrl("recovery-handoff")).replace(/^file:\/\//, "")
    onStatusChanged: testRoot.advance()
    onBackupStatusChanged: testRoot.advance()
    onCollectionChanged: testRoot.advance()
    onExternalChangePendingChanged: testRoot.advance()
    onRecoveryBackupStatusChanged: testRoot.advance()
    onRecoveryOperationChanged: testRoot.advance()
    onRecoveryArchiveVerifiedChanged: {
      if (testRoot.mode === "recovery-write-retry" && recoveryArchiveVerified
          && testRoot.processStage === "waiting-archive") {
        testRoot.processStage = "stage-locking"
        pathProcess.command = ["chmod", "500", store.stateDirectory]
        pathProcess.running = true
      }
    }
    onPrimaryVerificationPending: {
      if (testRoot.mode === "verify-mismatch")
        externalWriter.setText(testRoot.externalPayload("Verification mismatch", "external-mismatch"))
    }
    onRecoveryFinalVerificationPending: {
      if (testRoot.mode === "recovery-verification-race" && !testRoot.externalSubmitted) {
        testRoot.externalSubmitted = true
        var mutation = store.createNote("Mutation must remain blocked")
        if (mutation.ok) {
          console.error("PINOTE_STORE_SMOKE_FAILED recovery-mutation-was-allowed")
          Qt.quit()
          return
        }
        testRoot.processStage = "race-write"
        externalWriter.setText(testRoot.externalPayload("External verification note", "verification-race"))
      } else if (testRoot.mode === "recovery-identical-postinstall-race"
          && !testRoot.externalSubmitted) {
        testRoot.externalSubmitted = true
        externalWriter.setText(JSON.stringify({ version: 1, notes: [] }, null, 2) + "\n")
      }
    }
  }

  Process {
    id: pathProcess
    running: false
    onRunningChanged: {
      if (running) {
        testRoot.processStarted = true
      } else if (testRoot.processStarted) {
        testRoot.processStarted = false
        if (testRoot.processStage === "blocking") {
          testRoot.processStage = "blocked"
          store.createNote("Recovered save")
        } else if (testRoot.processStage === "removing") {
          testRoot.processStage = "retried"
          if (!store.retrySave()) {
            console.error("PINOTE_STORE_SMOKE_FAILED retry-rejected")
            Qt.quit()
          }
        } else if (testRoot.processStage === "backup-blocking") {
          testRoot.processStage = "backup-blocked"
          store.createNote("Backup retry")
        } else if (testRoot.processStage === "backup-removing") {
          testRoot.processStage = "backup-retried"
          if (!store.retryBackup()) {
            console.error("PINOTE_STORE_SMOKE_FAILED backup-retry-rejected")
            Qt.quit()
          }
        } else if (testRoot.processStage === "dirty-blocking") {
          testRoot.processStage = "dirty-blocked"
          store.createNote("Unsaved local note")
        } else if (testRoot.processStage === "archive-locking") {
          testRoot.processStage = "archive-started"
          if (!store.startFresh()) {
            console.error("PINOTE_STORE_SMOKE_FAILED archive-start-rejected")
            Qt.quit()
          }
        } else if (testRoot.processStage === "archive-unlocking") {
          testRoot.processStage = "archive-finished"
          console.log("PINOTE_STORE_RECOVERY_ARCHIVE_FAILURE_OK")
          Qt.quit()
        } else if (testRoot.processStage === "stage-locking") {
          testRoot.processStage = "stage-locked"
        } else if (testRoot.processStage === "stage-unlocking") {
          if (!store.retryRecoveryWrite()) {
            console.error("PINOTE_STORE_SMOKE_FAILED recovery-write-retry-rejected")
            Qt.quit()
          } else {
            testRoot.processStage = "stage-retried"
          }
        } else if (testRoot.processStage === "dirty-removing") {
          testRoot.processStage = "dirty-writing"
          externalWriter.setText(testRoot.externalPayload("Preserved external note", "external-conflict"))
        }
      }
    }
  }

  FileView {
    id: externalWriter
    path: store.primaryPath
    preload: false
    blockLoading: true
    blockWrites: true
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onSaved: {
      if (testRoot.processStage === "dirty-writing") {
        testRoot.processStage = "dirty-checking"
        dirtyRetryTimer.restart()
      } else if (testRoot.processStage === "writing-second-damage") {
        testRoot.processStage = "waiting-second-recovery"
      }
    }
  }

  FileView {
    id: backupExternalWriter
    path: store.backupPath
    preload: false
    blockLoading: true
    blockWrites: true
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onSaved: {
      if (testRoot.processStage === "changing-backup") {
        testRoot.processStage = "backup-revalidating"
        if (!store.restoreBackup()) {
          console.error("PINOTE_STORE_SMOKE_FAILED changed-backup-restore-start")
          Qt.quit()
        }
      }
    }
  }

  Timer {
    id: dirtyRetryTimer
    interval: 100
    repeat: false
    onTriggered: {
      store.retrySave()
      dirtyResultTimer.restart()
    }
  }

  Timer {
    id: dirtyResultTimer
    interval: 300
    repeat: false
    onTriggered: {
      if (store.status === "save-error" && store.externalChangePending)
        console.log("PINOTE_STORE_DIRTY_EXTERNAL_OK")
      else
        console.error("PINOTE_STORE_SMOKE_FAILED dirty-external status=" + store.status)
      Qt.quit()
    }
  }

  Timer {
    id: conflictResultTimer
    interval: 200
    repeat: false
    onTriggered: {
      console.log("PINOTE_STORE_RECOVERY_CONFLICT_OK")
      Qt.quit()
    }
  }

  Timer {
    id: recoveryAbandonTimer
    interval: 200
    repeat: false
    onTriggered: {
      console.log("PINOTE_STORE_INTERRUPTED_ABANDON_OK")
      Qt.quit()
    }
  }

  Timer {
    interval: Number(Quickshell.env("PINOTE_STORE_SMOKE_TIMEOUT_MS") || 5000)
    running: true
    onTriggered: {
      console.error("PINOTE_STORE_SMOKE_FAILED timeout status=" + store.status
        + " path=" + store.stateDirectory + " error=" + store.errorCode)
      Qt.quit()
    }
  }
}

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
    onStatusChanged: testRoot.advance()
    onBackupStatusChanged: testRoot.advance()
    onCollectionChanged: testRoot.advance()
    onExternalChangePendingChanged: testRoot.advance()
    onPrimaryVerificationPending: {
      if (testRoot.mode === "verify-mismatch")
        externalWriter.setText(testRoot.externalPayload("Verification mismatch", "external-mismatch"))
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
    interval: 5000
    running: true
    onTriggered: {
      console.error("PINOTE_STORE_SMOKE_FAILED timeout status=" + store.status
        + " path=" + store.stateDirectory + " error=" + store.errorCode)
      Qt.quit()
    }
  }
}

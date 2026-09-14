pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "RuntimeIdentity.js" as RuntimeIdentity

Item {
  id: root

  property bool opened: false
  property var shell: null
  property var manifest: null

  property alias mode: panelState.mode
  property alias selectedNoteId: panelState.selectedNoteId
  property alias editingNoteId: panelState.editingNoteId
  property alias draftContent: panelState.draftContent
  property alias draftError: panelState.draftError
  property alias draftNotice: panelState.draftNotice
  property alias pendingDeleteId: panelState.pendingDeleteId
  property alias deleteConfirmOpen: panelState.deleteConfirmOpen
  property bool focusPrimed: false
  readonly property var runtime: RuntimeIdentity.fromManifest(manifest)

  readonly property bool collectionVisible: notesStore.status === "ready"
    || notesStore.status === "saving"
    || notesStore.status === "save-error"
    || notesStore.status === "recovery"
  readonly property bool editorVisible: collectionVisible && notesStore.canMutate && mode === "editor"
  readonly property bool editingNoteMissing: panelState.editingNoteMissing

  NotesStore {
    id: notesStore
    stateDirectoryName: root.runtime.stateDirectoryName
    logPrefix: root.runtime.logPrefix
    displayName: root.runtime.displayName
    autoStart: {
      if (root.manifest === null) return false
      var expected = RuntimeIdentity.fromManifest(root.manifest)
      return stateDirectoryName === expected.stateDirectoryName
        && logPrefix === expected.logPrefix
        && displayName === expected.displayName
    }
  }

  PanelState {
    id: panelState
    store: notesStore

    onEditorFocusRequested: function(selectionMode) { root.focusEditor(selectionMode) }
    onListFocusRequested: root.restoreListFocus()
    onCurrentFocusRequested: if (root.opened) root.restoreCurrentFocus()
  }

  function popupColor(name) {
    return Color.popups[name]
  }

  function fontToken(name) {
    return Style.font[name]
  }

  function spacingToken(name) {
    return Style.spacing[name]
  }

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var monitorName = monitor ? String(monitor.name || "") : ""
    var screens = Quickshell.screens || []

    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === monitorName) return screens[i]
    }

    return screens.length > 0 ? screens[0] : null
  }

  function open(payloadJson) {
    panel.screen = focusedScreen()
    focusPrimed = false
    opened = true
    focusPrimeTimer.restart()
    restoreCurrentFocus()
  }

  function close() {
    opened = false
    panelState.panelClosed()
    focusPrimeTimer.stop()
    focusPrimed = false
  }

  function toggle() {
    if (opened) close()
    else open("{}")
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(runtime.pluginId)
    else close()
  }

  function noteIndex(id) {
    return panelState.noteIndex(id)
  }

  function previewFor(content) {
    var lines = String(content || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var candidate = lines[i].trim()
      if (candidate !== "") return candidate
    }
    return "Untitled note"
  }

  function syncSelection() {
    panelState.syncSelection()
  }

  function selectRelative(delta) {
    var index = panelState.selectRelative(delta)
    if (index >= 0) notesList.positionViewAtIndex(index, ListView.Contain)
  }

  function beginCreate() {
    panelState.beginCreate()
  }

  function beginEdit(id) {
    panelState.beginEdit(id)
  }

  function saveDraft() {
    panelState.saveDraft()
  }

  function cancelDraft() {
    panelState.cancelDraft()
  }

  function requestDelete(id) {
    deleteConfirm.selectedIndex = 1
    panelState.requestDelete(id)
  }

  function cancelDelete() {
    panelState.cancelDelete()
  }

  function confirmDelete() {
    panelState.confirmDelete()
  }

  function focusEditor(selectionMode) {
    Qt.callLater(function() {
      if (!root.opened || !root.editorVisible) return
      editor.forceActiveFocus()
      if (selectionMode === "start") editor.cursorPosition = 0
      else if (selectionMode === "all") editor.selectAll()
    })
  }

  function restoreListFocus() {
    Qt.callLater(function() {
      if (root.opened && !root.editorVisible) keyCatcher.forceActiveFocus()
    })
  }

  function restoreCurrentFocus() {
    if (editorVisible) focusEditor("preserve")
    else restoreListFocus()
  }

  onOpenedChanged: {
    if (opened) restoreCurrentFocus()
  }

  Timer {
    id: focusPrimeTimer
    interval: 75
    onTriggered: if (root.opened) root.focusPrimed = true
  }

  PanelWindow { // qmllint disable uncreatable-type
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: root.runtime.layerNamespace
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? (root.focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
      : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)

      MouseArea {
        anchors.fill: parent
        onClicked: root.requestClose()
      }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(560), Math.max(0, parent.width - Style.gapsOut * 2))
      height: Math.min(Style.space(620), parent.height * 0.75)
      radius: Style.cornerRadius
      color: root.popupColor("background")
      borderSpec: Border.surfaceSpec(
        "popups", "border", root.popupColor("border"), Math.max(1, Style.space(2)))

      MouseArea {
        anchors.fill: parent
        onClicked: function(mouse) { mouse.accepted = true }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        anchors.margins: root.spacingToken("panelPadding")
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            if (deleteKeyRouter.handleKey(event)) event.accepted = true
            return
          }
          if (root.editorVisible) {
            if (event.key === Qt.Key_Escape) {
              root.cancelDraft()
              event.accepted = true
            } else if ((event.modifiers & Qt.ControlModifier)
                && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_S)) {
              root.saveDraft()
              event.accepted = true
            }
            return
          }
          if (event.key === Qt.Key_Escape) {
            root.requestClose()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectRelative(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectRelative(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (keyCatcher.activeFocus) {
              if (root.selectedNoteId !== "") root.beginEdit(root.selectedNoteId)
              event.accepted = true
            }
          } else if (event.key === Qt.Key_Delete || event.text === "x" || event.text === "X") {
            if (root.selectedNoteId !== "") root.requestDelete(root.selectedNoteId)
            event.accepted = true
          } else if (event.text === "n" || event.text === "N") {
            root.beginCreate()
            event.accepted = true
          }
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: root.spacingToken("panelGap")

          RowLayout {
            Layout.fillWidth: true
            spacing: root.spacingToken("controlGap")

            Text {
              Layout.fillWidth: true
              text: root.editorVisible
                ? (root.editingNoteId === "" ? "New note" : (root.editingNoteMissing ? "Restore note" : "Edit note"))
                : root.runtime.displayName
              textFormat: Text.PlainText
              color: root.popupColor("text")
              font.family: root.fontToken("family")
              font.pixelSize: root.fontToken("title")
              font.bold: true
              elide: Text.ElideRight
            }

            Button {
              visible: root.collectionVisible && !root.editorVisible && notesStore.canMutate
              text: "New"
              iconText: "+"
              foreground: root.popupColor("text")
              focusable: true
              bordered: true
              onClicked: root.beginCreate()
            }

            Button {
              text: "Close"
              foreground: root.popupColor("text")
              focusable: true
              bordered: true
              onClicked: root.requestClose()
            }
          }

          RowLayout {
            Layout.fillWidth: true
            visible: notesStore.status === "saving" || notesStore.status === "save-error"
              || !notesStore.backupHealthy
            spacing: root.spacingToken("controlGap")

            Text {
              Layout.fillWidth: true
              text: notesStore.status === "saving"
                ? "Saving changes..."
                : notesStore.status === "save-error"
                  ? (notesStore.externalChangePending
                    ? "The notes file changed externally, so " + root.runtime.displayName + " will not overwrite it. Keep this panel open, restore the file to the version it last loaded, then check again."
                    : "Changes are not saved. Correct the storage problem and retry.")
                  : "The latest backup could not be updated."
              textFormat: Text.PlainText
              color: notesStore.status === "saving" ? root.popupColor("text") : Color.urgent
              opacity: notesStore.status === "saving" ? 0.72 : 1
              font.family: root.fontToken("family")
              font.pixelSize: root.fontToken("bodySmall")
              wrapMode: Text.WordWrap
            }

            Button {
              visible: notesStore.status === "save-error"
              text: notesStore.externalChangePending ? "Check again" : "Retry save"
              foreground: root.popupColor("text")
              focusable: true
              bordered: true
              onClicked: notesStore.retrySave()
            }

            Button {
              visible: notesStore.status !== "save-error" && !notesStore.backupHealthy
              text: "Retry backup"
              foreground: root.popupColor("text")
              focusable: true
              bordered: true
              onClicked: notesStore.retryBackup()
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.collectionVisible
            spacing: root.spacingToken("panelGap")

            Item { Layout.fillHeight: true }

            Text {
              Layout.fillWidth: true
              text: notesStore.status === "initializing" ? "Loading notes..."
                : notesStore.status === "unsupported"
                  ? "This notes file uses unsupported schema version " + notesStore.unsupportedVersion + "."
                  : root.runtime.displayName + " could not access its notes file."
              textFormat: Text.PlainText
              color: root.popupColor("text")
              horizontalAlignment: Text.AlignHCenter
              font.family: root.fontToken("family")
              font.pixelSize: root.fontToken("heading")
              wrapMode: Text.WordWrap
            }

            Text {
              Layout.fillWidth: true
              visible: notesStore.status !== "initializing"
              text: notesStore.status === "unsupported"
                ? "The file is read-only and will not be changed by this version of " + root.runtime.displayName + "."
                : (notesStore.errorMessage || "Check the state path and its permissions, then retry.")
              textFormat: Text.PlainText
              color: root.popupColor("text")
              opacity: 0.72
              horizontalAlignment: Text.AlignHCenter
              font.family: root.fontToken("family")
              font.pixelSize: root.fontToken("body")
              wrapMode: Text.WordWrap
            }

            Button {
              Layout.alignment: Qt.AlignHCenter
              visible: notesStore.status === "load-error"
              text: "Retry load"
              foreground: root.popupColor("text")
              focusable: true
              bordered: true
              onClicked: notesStore.retryLoad()
            }

            Item { Layout.fillHeight: true }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.collectionVisible && !root.editorVisible
            spacing: root.spacingToken("panelGap")

            Text {
              Layout.fillWidth: true
              visible: notesStore.status === "recovery"
              text: "The notes file is damaged. Valid notes are shown read-only; recovery actions will not alter the original file."
              textFormat: Text.PlainText
              color: Color.urgent
              font.family: root.fontToken("family")
              font.pixelSize: root.fontToken("bodySmall")
              wrapMode: Text.WordWrap
            }

            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              ColumnLayout {
                anchors.centerIn: parent
                width: parent.width
                visible: notesStore.notes.length === 0
                spacing: root.spacingToken("panelGap")

                Text {
                  Layout.fillWidth: true
                  text: notesStore.status === "recovery" ? "No valid notes could be previewed." : "No notes yet"
                  textFormat: Text.PlainText
                  color: root.popupColor("text")
                  horizontalAlignment: Text.AlignHCenter
                  font.family: root.fontToken("family")
                  font.pixelSize: root.fontToken("heading")
                }

                Text {
                  Layout.fillWidth: true
                  visible: notesStore.status !== "recovery"
                  text: "Create a plain-text note to get started."
                  textFormat: Text.PlainText
                  color: root.popupColor("text")
                  opacity: 0.68
                  horizontalAlignment: Text.AlignHCenter
                  font.family: root.fontToken("family")
                  font.pixelSize: root.fontToken("body")
                }

                Button {
                  Layout.alignment: Qt.AlignHCenter
                  visible: notesStore.canMutate
                  text: "Create note"
                  foreground: root.popupColor("text")
                  focusable: true
                  bordered: true
                  onClicked: root.beginCreate()
                }
              }

              ListView {
                id: notesList
                anchors.fill: parent
                visible: notesStore.notes.length > 0
                model: notesStore.notes
                clip: true
                spacing: Style.space(6)
                boundsBehavior: Flickable.StopAtBounds

                delegate: BorderSurface {
                  id: noteRow
                  required property int index
                  required property var modelData

                  readonly property bool selected: root.selectedNoteId === modelData.id

                  width: notesList.width
                  height: Style.space(72)
                  radius: Style.cornerRadius
                  color: selected ? Util.alpha(Color.accent, 0.14) : "transparent"
                  borderSpec: selected
                    ? Border.flat(Color.accent, Math.max(1, Style.normalBorderWidth))
                    : Border.none()

                  Column {
                    anchors.fill: parent
                    anchors.margins: Style.space(12)
                    spacing: Style.space(4)

                    Text {
                      width: parent.width
                      text: root.previewFor(noteRow.modelData.content)
                      textFormat: Text.PlainText
                      color: root.popupColor("text")
                      font.family: root.fontToken("family")
                      font.pixelSize: root.fontToken("body")
                      font.bold: noteRow.selected
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }

                    Text {
                      width: parent.width
                      text: String(noteRow.modelData.content).replace(/\s+/g, " ").trim()
                      textFormat: Text.PlainText
                      color: root.popupColor("text")
                      opacity: 0.62
                      font.family: root.fontToken("family")
                      font.pixelSize: root.fontToken("bodySmall")
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: notesStore.canMutate ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: root.selectedNoteId = noteRow.modelData.id
                    onClicked: {
                      root.selectedNoteId = noteRow.modelData.id
                      if (notesStore.canMutate) root.beginEdit(noteRow.modelData.id)
                    }
                  }
                }
              }
            }

            Text {
              Layout.fillWidth: true
              visible: notesStore.status !== "recovery" && notesStore.notes.length > 0
              text: "Up/Down select  Enter edit  N new  Delete remove"
              textFormat: Text.PlainText
              color: root.popupColor("text")
              opacity: 0.52
              horizontalAlignment: Text.AlignHCenter
              font.family: root.fontToken("family")
              font.pixelSize: root.fontToken("caption")
              elide: Text.ElideRight
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.editorVisible
            spacing: root.spacingToken("panelGap")

            QQC.ScrollView {
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff
              QQC.ScrollBar.vertical.policy: QQC.ScrollBar.AsNeeded

              QQC.TextArea {
                id: editor
                text: root.draftContent
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                persistentSelection: true
                placeholderText: "Write a note..."
                color: root.popupColor("text")
                selectionColor: Util.alpha(Color.accent, 0.42)
                selectedTextColor: root.popupColor("text")
                placeholderTextColor: Util.alpha(root.popupColor("text"), 0.5)
                font.family: root.fontToken("family")
                font.pixelSize: root.fontToken("body")
                leftPadding: Style.space(14)
                rightPadding: Style.space(14)
                topPadding: Style.space(12)
                bottomPadding: Style.space(12)
                background: BorderSurface {
                  color: Util.alpha(root.popupColor("text"), 0.035)
                  radius: Style.cornerRadius
                  borderSpec: Border.flat(Util.alpha(root.popupColor("text"), 0.28),
                    Math.max(1, Style.normalBorderWidth))
                }

                onTextChanged: if (root.draftContent !== text) root.draftContent = text

              }
            }

            Text {
              Layout.fillWidth: true
              visible: root.draftError !== ""
              text: root.draftError
              textFormat: Text.PlainText
              color: Color.urgent
              font.family: root.fontToken("family")
              font.pixelSize: root.fontToken("bodySmall")
              wrapMode: Text.WordWrap
            }

            Text {
              Layout.fillWidth: true
              visible: root.draftNotice !== ""
              text: root.draftNotice
              textFormat: Text.PlainText
              color: root.popupColor("text")
              opacity: 0.72
              font.family: root.fontToken("family")
              font.pixelSize: root.fontToken("bodySmall")
              wrapMode: Text.WordWrap
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: root.spacingToken("controlGap")

              Button {
                visible: root.editingNoteId !== "" && !root.editingNoteMissing
                text: "Delete"
                foreground: Color.urgent
                focusable: true
                bordered: true
                onClicked: root.requestDelete(root.editingNoteId)
              }

              Item { Layout.fillWidth: true }

              Text {
                text: "Esc cancel  Ctrl+Enter save"
                textFormat: Text.PlainText
                color: root.popupColor("text")
                opacity: 0.52
                font.family: root.fontToken("family")
                font.pixelSize: root.fontToken("caption")
              }

              Button {
                text: "Cancel"
                foreground: root.popupColor("text")
                focusable: true
                bordered: true
                onClicked: root.cancelDraft()
              }

              Button {
                text: "Save"
                foreground: root.popupColor("text")
                focusable: true
                bordered: true
                onClicked: root.saveDraft()
              }
            }
          }
        }

        ModalKeyRouter {
          id: deleteKeyRouter
          opened: root.deleteConfirmOpen
          focusTarget: keyCatcher
          dialog: deleteConfirm
        }

        ConfirmDialog {
          id: deleteConfirm
          anchors.fill: parent
          z: 20
          opened: root.deleteConfirmOpen
          message: "Delete this note? This cannot be undone."
          confirmText: "Delete"
          background: root.popupColor("background")
          foreground: root.popupColor("text")
          scrim: Qt.rgba(0, 0, 0, 0.68)
          selectedText: Color.accent
          fontFamily: root.fontToken("family")
          cornerRadius: Style.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }
    }
  }
}

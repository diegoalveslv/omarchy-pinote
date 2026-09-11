import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property bool opened: false
  property var shell: null

  NotesStore {
    id: notesStore
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
    opened = true
  }

  function close() {
    opened = false
  }

  function toggle() {
    if (opened) close()
    else open("{}")
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("diegoalveslv.pinote")
    else close()
  }

  PanelWindow { // qmllint disable uncreatable-type
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "pinote"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened
      ? WlrKeyboardFocus.OnDemand
      : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.45)

      MouseArea {
        anchors.fill: parent
        onClicked: root.requestClose()
      }
    }

    Item {
      anchors.fill: parent
      focus: root.opened

      Keys.onEscapePressed: root.requestClose()

      BorderSurface {
        anchors.centerIn: parent
        width: Math.min(Style.space(560), parent.width - Style.gapsOut * 2)
        height: Math.min(Style.space(240), parent.height * 0.75)
        radius: Style.cornerRadius
        color: root.popupColor("background")
        borderSpec: Border.surfaceSpec(
          "popups", "border", root.popupColor("border"), Math.max(1, Style.space(2)))

        MouseArea {
          anchors.fill: parent
          onClicked: function(mouse) { mouse.accepted = true }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: root.spacingToken("panelPadding")
          spacing: root.spacingToken("panelGap")

          Text {
            Layout.fillWidth: true
            text: "Pinote"
            textFormat: Text.PlainText
            color: root.popupColor("text")
            font.family: root.fontToken("family")
            font.pixelSize: root.fontToken("title")
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: "Your notes will appear here."
            textFormat: Text.PlainText
            color: root.popupColor("text")
            font.family: root.fontToken("family")
            font.pixelSize: root.fontToken("body")
            wrapMode: Text.WordWrap
          }

          Button {
            Layout.alignment: Qt.AlignRight
            text: "Close"
            foreground: root.popupColor("text")
            focusable: true
            bordered: true
            onClicked: root.requestClose()
          }
        }
      }
    }
  }
}

import QtQuick

QtObject {
  id: root

  required property Item focusTarget
  required property var dialog
  property bool opened: false

  function handleKey(event) {
    return opened && dialog.handleKey(event)
  }

  onOpenedChanged: {
    if (!opened) return
    Qt.callLater(function() {
      if (root.opened) root.focusTarget.forceActiveFocus()
    })
  }
}

import QtQuick
import QtQuick.Controls as QQC
import QtTest
import "../.." as Pinote

TestCase {
  id: testCase

  name: "ModalKeyRouter"
  width: 400
  height: 300
  when: windowShown

  Item {
    id: keyTarget
    anchors.fill: parent
    focus: true

    property bool dialogOpen: false
    property bool confirmed: false

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (router.handleKey(event)) event.accepted = true
    }

    QQC.Button {
      id: deleteButton
      text: "Delete"
      onClicked: keyTarget.dialogOpen = true
    }

    Item {
      id: fakeDialog

      function handleKey(event) {
        if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) return false
        keyTarget.confirmed = true
        keyTarget.dialogOpen = false
        return true
      }
    }

    Pinote.ModalKeyRouter {
      id: router
      opened: keyTarget.dialogOpen
      focusTarget: keyTarget
      dialog: fakeDialog
    }
  }

  function init() {
    keyTarget.dialogOpen = false
    keyTarget.confirmed = false
    deleteButton.forceActiveFocus()
    verify(deleteButton.activeFocus)
  }

  function test_enterRoutesAfterOpeningFromFocusedButton() {
    keyClick(Qt.Key_Return)
    compare(keyTarget.dialogOpen, true)
    tryVerify(function() { return keyTarget.activeFocus })

    keyClick(Qt.Key_Return)

    compare(keyTarget.dialogOpen, false)
    compare(keyTarget.confirmed, true)
  }
}

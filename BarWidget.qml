import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "diegoalveslv.pinote"

  function runBarCommand(command) {
    var method = "run"
    if (root.bar && typeof root.bar[method] === "function")
      root.bar[method](command)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰎚"
    tooltipText: "Pinote"

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton)
        root.runBarCommand("omarchy-shell shell toggle diegoalveslv.pinote '{}'")
    }
  }
}

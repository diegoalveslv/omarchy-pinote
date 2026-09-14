import QtQuick
import qs.Ui
import "RuntimeIdentity.js" as RuntimeIdentity

BarWidget {
  id: root
  moduleName: "diegoalveslv.pinote"
  readonly property var runtime: RuntimeIdentity.forPlugin(moduleName, "")

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
    tooltipText: root.runtime.displayName

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton)
        root.runBarCommand("omarchy-shell shell toggle " + root.runtime.pluginId + " '{}'")
    }
  }
}

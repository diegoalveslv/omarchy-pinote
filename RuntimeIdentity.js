var PRODUCTION_ID = "pinote.notes"
var LIVE_TEST_ID = "pinote.notes.live-test"

function safeSegment(value) {
  var normalized = String(value || "").replace(/[^A-Za-z0-9._-]/g, "-")
  return normalized === "" ? "unknown" : normalized
}

function forPlugin(pluginId, displayName) {
  var id = String(pluginId || PRODUCTION_ID)
  var name = String(displayName || (id === LIVE_TEST_ID ? "Pinote (Live Test)" : "Pinote"))

  if (id === PRODUCTION_ID) {
    return {
      pluginId: id,
      displayName: name,
      stateDirectoryName: "pinote",
      layerNamespace: "pinote",
      logPrefix: "pinote:"
    }
  }

  if (id === LIVE_TEST_ID) {
    return {
      pluginId: id,
      displayName: name,
      stateDirectoryName: "pinote-live-test",
      layerNamespace: "pinote-live-test",
      logPrefix: "pinote-live-test:"
    }
  }

  var isolated = safeSegment(id)
  return {
    pluginId: id,
    displayName: name,
    stateDirectoryName: "pinote-" + isolated,
    layerNamespace: isolated,
    logPrefix: isolated + ":"
  }
}

function fromManifest(manifest) {
  return forPlugin(manifest && manifest.id, manifest && manifest.name)
}

if (typeof module !== "undefined") {
  module.exports = {
    PRODUCTION_ID: PRODUCTION_ID,
    LIVE_TEST_ID: LIVE_TEST_ID,
    safeSegment: safeSegment,
    forPlugin: forPlugin,
    fromManifest: fromManifest
  }
}

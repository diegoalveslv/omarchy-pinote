const test = require("node:test")
const assert = require("node:assert/strict")
const RuntimeIdentity = require("../RuntimeIdentity.js")

test("production identity preserves public runtime paths", () => {
  assert.deepEqual(RuntimeIdentity.forPlugin("diegoalveslv.pinote", "Pinote"), {
    pluginId: "diegoalveslv.pinote",
    displayName: "Pinote",
    stateDirectoryName: "pinote",
    layerNamespace: "pinote",
    logPrefix: "pinote:"
  })
})

test("live-test identity is isolated and visibly named", () => {
  assert.deepEqual(RuntimeIdentity.forPlugin("diegoalveslv.pinote.live-test", "Pinote (Live Test)"), {
    pluginId: "diegoalveslv.pinote.live-test",
    displayName: "Pinote (Live Test)",
    stateDirectoryName: "pinote-live-test",
    layerNamespace: "pinote-live-test",
    logPrefix: "pinote-live-test:"
  })
})

test("unknown clones never fall back to production state", () => {
  const identity = RuntimeIdentity.forPlugin("example/pinote clone", "Clone")
  assert.equal(identity.stateDirectoryName, "pinote-example-pinote-clone")
  assert.equal(identity.layerNamespace, "example-pinote-clone")
  assert.equal(identity.logPrefix, "example-pinote-clone:")
})

test("a missing manifest safely uses production defaults", () => {
  assert.equal(RuntimeIdentity.fromManifest(null).pluginId, RuntimeIdentity.PRODUCTION_ID)
})

function emptyState() {
  return {
    activePrimary: null,
    queuedPrimary: null,
    retryPrimary: null,
    activeBackup: null,
    queuedBackup: null,
    retryBackup: null
  }
}

function copyState(state) {
  return {
    activePrimary: state.activePrimary,
    queuedPrimary: state.queuedPrimary,
    retryPrimary: state.retryPrimary,
    activeBackup: state.activeBackup,
    queuedBackup: state.queuedBackup,
    retryBackup: state.retryBackup
  }
}

function transition(state) {
  return {
    state: state,
    writePrimary: null,
    writeBackup: null,
    confirmedPrimary: null,
    failedPrimary: null,
    confirmedBackup: null,
    failedBackup: null
  }
}

function enqueuePrimary(state, snapshot, paused) {
  var next = copyState(state)
  var result = transition(next)

  if (paused) {
    next.retryPrimary = snapshot
    next.queuedPrimary = null
  } else if (next.activePrimary) {
    next.queuedPrimary = snapshot
  } else {
    next.activePrimary = snapshot
    next.retryPrimary = null
    result.writePrimary = snapshot
  }

  return result
}

function primarySaved(state, durablePayload) {
  var next = copyState(state)
  var result = transition(next)
  if (!next.activePrimary) return result

  var confirmed = next.activePrimary
  result.confirmedPrimary = confirmed
  next.activePrimary = next.queuedPrimary
  next.queuedPrimary = null
  next.retryPrimary = null
  if (next.activePrimary) result.writePrimary = next.activePrimary

  if (next.activeBackup) {
    next.queuedBackup = confirmed
  } else {
    next.activeBackup = confirmed
    next.retryBackup = null
    result.writeBackup = confirmed
  }

  while (result.writePrimary && durablePayload !== undefined
      && result.writePrimary.payload === durablePayload) {
    var continued = primarySaved(result.state)
    result.state = continued.state
    result.writePrimary = continued.writePrimary
    result.confirmedPrimary = continued.confirmedPrimary
    if (!result.writeBackup) result.writeBackup = continued.writeBackup
  }

  return result
}

function primaryFailed(state) {
  var next = copyState(state)
  var result = transition(next)
  if (!next.activePrimary) return result

  result.failedPrimary = next.activePrimary
  next.retryPrimary = next.queuedPrimary || next.activePrimary
  next.activePrimary = null
  next.queuedPrimary = null
  return result
}

function retryPrimary(state) {
  var next = copyState(state)
  var result = transition(next)
  if (next.activePrimary || !next.retryPrimary) return result

  next.activePrimary = next.retryPrimary
  next.retryPrimary = null
  result.writePrimary = next.activePrimary
  return result
}

function backupSaved(state, durablePayload) {
  var next = copyState(state)
  var result = transition(next)
  if (!next.activeBackup) return result

  result.confirmedBackup = next.activeBackup
  next.activeBackup = next.queuedBackup
  next.queuedBackup = null
  next.retryBackup = null
  if (next.activeBackup) result.writeBackup = next.activeBackup
  while (result.writeBackup && durablePayload !== undefined
      && result.writeBackup.payload === durablePayload) {
    var continued = backupSaved(result.state)
    result.state = continued.state
    result.writeBackup = continued.writeBackup
    result.confirmedBackup = continued.confirmedBackup
  }

  return result
}

function backupFailed(state) {
  var next = copyState(state)
  var result = transition(next)
  if (!next.activeBackup) return result

  result.failedBackup = next.activeBackup
  if (next.queuedBackup) {
    next.activeBackup = next.queuedBackup
    next.queuedBackup = null
    next.retryBackup = null
    result.writeBackup = next.activeBackup
  } else {
    next.retryBackup = next.activeBackup
    next.activeBackup = null
  }
  return result
}

function retryBackup(state) {
  var next = copyState(state)
  var result = transition(next)
  if (next.activeBackup || !next.retryBackup) return result

  next.activeBackup = next.retryBackup
  next.retryBackup = null
  result.writeBackup = next.activeBackup
  return result
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyState: emptyState,
    enqueuePrimary: enqueuePrimary,
    primarySaved: primarySaved,
    primaryFailed: primaryFailed,
    retryPrimary: retryPrimary,
    backupSaved: backupSaved,
    backupFailed: backupFailed,
    retryBackup: retryBackup
  }
}

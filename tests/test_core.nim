## Tests for the example `ini` extension core.
##
## The adapter runs as a real child process through the backend runtime, so
## its handshake is checked against the routed operations (§17.2), and every
## result against the registry (§12, §16.3).
import std/[json, options, os, osproc, posix, sequtils, strutils, tables, times, unittest]
import jumpstart/cores/backends/[adapter_runtime, backend_runtime],
  jumpstart/cores/manifest/[manifest, modes]
import jumpstartcore/[environment, errors, reaper, spawn]

const CoreDir = currentSourcePath().parentDir.parentDir

proc adapterPath(): string = CoreDir / "bin" / "ini-adapter"

proc rawAdapter(lines: seq[JsonNode]): tuple[output: string, exitCode: int] =
  ## Feed lines on descriptor 3 and collect descriptor 4, for handshake edge
  ## cases that the runtime itself would never produce.
  var payload = ""
  for line in lines: payload.add $line & "\n"
  let script = "printf %s " & quoteShell(payload) & " | python3 " &
    quoteShell(adapterPath()) & " 3<&0 4>&1 2>/dev/null"
  execCmdEx("/bin/sh -c " & quoteShell(script))

let testMode = if getuid() == 0: cmSystem else: cmUser

proc newRuntime(): BackendRuntime =
  var config = RuntimeConfig(mode: testMode, jumpstartVersion: "2.0.0",
    trustedUid: getuid(), runnerTrustedUid: getuid())
  if testMode == cmUser: config.identity = userIdentityFor(getuid())
  newBackendRuntime(config, initAdapterRuntime(modeName(testMode), "2.0.0", newReaper()))

proc withEnvironment(m: CoreManifest; env: openArray[(string, string)]): CoreManifest =
  result = m
  for op in result.operations.mitems:
    for (key, value) in env: op.common.environment[key] = value

suite "example ini core":
  let base = getTempDir() / ("jumpstart-ini-" & $getpid())
  if dirExists(base): removeDir(base)
  let units = base / "units"
  let dirs = CoreDirectories(root: CoreDir, stateDir: base / "state", runtimeDir: base / "run")
  for dir in [base, units, dirs.stateDir, dirs.runtimeDir]:
    createDir(dir); discard chmod(dir.cstring, Mode(0o755))
  writeFile(units / "example.service", "[Unit]\ndescription = Example\n\n[Service]\nexec = /bin/sleep 1000\n")
  writeFile(units / "stubborn.service",
    "[Service]\nexec = /bin/sh -c \"trap '' TERM; touch " & base / "trapped" &
    "; sleep 1000\"\n")
  let loaded = loadManifest(CoreDir / "init.kg", "ini", "2.0.0")
  let runtime = newRuntime()
  runtime.registerManifest(loaded.withEnvironment({"INI_CORE_CONFIG_DIR": units}), dirs, "")

  test "manifest validates and is complete":
    check loaded.name == "ini"
    check "service" in loaded.subsystems
    let verify = loaded.operations.filterIt(it.name == "core.verify")[0]
    check verify.common.sandbox
    check verify.common.workingDirectory == "/tmp"

  test "handshake matches the routed operations and unit.list follows §12.2":
    runtime.startPersistent("ini", monotonicMs())
    let listed = runtime.run("ini", "unit.list", "", newJObject())
    check listed["units"].mapIt(it["name"].getStr) == @["example", "stubborn"]
    for unit in listed["units"]:
      check not unit.hasKey("state")
    check runtime.run("ini", "unit.list", "", %*{"subsystem": "mount"})["units"].len == 0
    let resolved = runtime.run("ini", "unit.resolve", "", %*{"name": "example.service"})
    check resolved == %*{"owned": true, "name": "example", "subsystem": "service"}

  test "service operations return exactly the registry results":
    check runtime.run("ini", "service.start", "example", newJObject()) == %*{"state": "active"}
    let status = runtime.run("ini", "service.status", "example", newJObject())
    check status["state"].getStr == "active"
    check status["main_pid"].getInt > 1
    check runtime.run("ini", "service.kill", "example", %*{"signal": "0"}) == newJObject()
    check runtime.run("ini", "service.enable", "example", newJObject()) == newJObject()
    check runtime.run("ini", "unit.list", "", newJObject())["units"][0]["enablement"].getStr == "enabled"
    check runtime.run("ini", "service.stop", "example", newJObject()) == %*{"state": "inactive"}
    check runtime.run("ini", "service.disable", "example", newJObject()) == newJObject()
    expect CoreError:
      discard runtime.run("ini", "service.reload", "example", newJObject())
    try:
      discard runtime.run("ini", "service.kill", "example", newJObject())
      check false
    except CoreError as e:
      check e.code == ecUsage
    try:
      discard runtime.run("ini", "service.start", "missing", newJObject())
      check false
    except CoreError as e:
      check e.code == ecNotFound

  test "cancel answers a running request with E_CANCELLED; others proceed":
    removeFile(base / "trapped")
    check runtime.run("ini", "service.start", "stubborn", newJObject()) == %*{"state": "active"}
    # Wait until the service ignores SIGTERM, so only a cancel can end the stop.
    while not fileExists(base / "trapped"): sleep(10)
    let started = epochTime()
    let stopping = runtime.dispatch("ini", "service.stop", "stubborn", newJObject(), monotonicMs())
    for _ in 0 ..< 20: runtime.pump(monotonicMs()); sleep(10)
    # Requests run concurrently: status answers while the stop is waiting.
    check runtime.run("ini", "service.status", "example", newJObject())["state"].getStr == "inactive"
    runtime.cancel(stopping, monotonicMs())
    let stopDone = runtime.waitFor(stopping)
    check stopDone.code == ecCancelled
    check epochTime() - started < 5
    # The adapter killed the service when the stop was cancelled.
    check runtime.run("ini", "service.status", "stubborn", newJObject())["state"].getStr == "inactive"

  test "requests run concurrently: status and stop answer while unit.deactivate runs (§11.6)":
    removeFile(base / "trapped")
    check runtime.run("ini", "service.start", "stubborn", newJObject()) == %*{"state": "active"}
    check runtime.run("ini", "service.start", "example", newJObject()) == %*{"state": "active"}
    while not fileExists(base / "trapped"): sleep(10)
    let started = epochTime()
    # unit.deactivate waits for `stubborn`, which ignores SIGTERM.
    let deactivate = runtime.dispatch("ini", "unit.deactivate", "", newJObject(), monotonicMs())
    for _ in 0 ..< 30: runtime.pump(monotonicMs()); sleep(10)
    check runtime.run("ini", "service.status", "example", newJObject())["state"].getStr in
      ["active", "inactive"]
    check runtime.run("ini", "service.stop", "example", newJObject()) == %*{"state": "inactive"}
    check epochTime() - started < 5
    runtime.cancel(deactivate, monotonicMs())
    check runtime.waitFor(deactivate).code == ecCancelled
    check runtime.run("ini", "service.status", "stubborn", newJObject())["state"].getStr == "inactive"

  test "sandboxed core.verify runs in /tmp or fails closed":
    try:
      let verified = runtime.run("ini", "core.verify", "", newJObject())
      check verified == %*{"installed": true, "version": "1"}
    except CoreError as e:
      check e.code == ecSandbox

  test "protocol mismatch and a missing mode get no reply (§17.2)":
    let offer = %*{"type": "hello", "protocols": ["jumpstart-core/1"],
      "role": "adapter", "core": "ini", "mode": "user", "jumpstart": "2.0.0"}
    var wrongProtocol = offer.copy
    wrongProtocol["protocols"] = %*["jumpstart-core/2"]
    var noMode = offer.copy
    noMode.delete("mode")
    var runner = offer.copy
    runner["role"] = %"runner"
    for bad in [wrongProtocol, noMode, runner]:
      let (output, code) = rawAdapter(@[bad])
      check output == ""
      check code == 2
    let (output, code) = rawAdapter(@[offer, %*{"type": "request", "id": "1",
      "op": "core.verify", "unit": "", "args": {}, "deadline": "x"}])
    let replies = output.strip.splitLines.mapIt(parseJson(it))
    check code == 0
    check replies.len == 2
    check replies[1]["error"]["code"].getStr == "E_PROTOCOL"

  runtime.unloadCore("ini", monotonicMs())
  runtime.driver.waitIdle()
  removeDir(base)

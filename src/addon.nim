import std/algorithm
import std/asyncdispatch
import std/enumerate
import std/httpclient
import std/[json, jsonutils]
import std/locks
import std/options
import std/os
import std/re
import std/sequtils
import std/[strformat, strutils]
import std/sugar
import std/terminal
import std/times

import zippy/ziparchives
import webdriver/chromedriver

import config
import types
import term

proc `==`*(a, b: Addon): bool {.inline.} =
  a.project == b.project

proc newAddon*(project: string, kind: AddonKind, branch: Option[string] = none(string), name: string = ""): Addon =
  result = new(Addon)
  result.project = project
  result.kind = kind
  result.branch = branch

proc prettyVersion(addon: Addon): string =
  if addon.version.isEmptyOrWhitespace: return ""
  case addon.kind
  of GithubRepo: return addon.version[0 ..< 7]
  else: return addon.version

proc prettyOldVersion(addon: Addon): string =
  if addon.oldVersion.isEmptyOrWhitespace: return ""
  case addon.kind
  of GithubRepo: return addon.oldVersion[0 ..< 7]
  else: return addon.oldVersion

proc getName*(addon: Addon): string =
  result = if not addon.name.isEmptyOrWhitespace: addon.name 
  else: $addon.kind & ':' & addon.project

proc stateMessage*(addon: Addon, nameSpace: int) = 
  let 
    t = configData.term
    indent = 2
    arrow = if addon.old_version.isEmptyOrWhitespace: "" else: "->"
  acquire(stdoutLock)
  case addon.state
  of Checking, Parsing:
    t.write(indent, addon.line, true,
      fgCyan, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyOldVersion()}", resetStyle)
  of Downloading, Installing, Restoring:
    t.write(indent, addon.line, true,
      fgCyan, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyOldVersion()}", fgWhite, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of FinishedUpdated, FinishedInstalled:
    t.write(indent, addon.line, true,
      fgGreen, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyOldVersion()}", fgWhite, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of FinishedAlreadyCurrent:
    t.write(indent, addon.line, true,
      fgGreen, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyVersion()}", resetStyle)
  of FinishedPinned:
    t.write(indent, addon.line, true,
      fgYellow, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      styleBright, fgRed, &"{addon.prettyOldVersion()}", fgWhite, &"{arrow}", 
      if addon.version != addon.oldVersion: fgGreen else: fgYellow,
      &"{addon.prettyVersion()}", resetStyle)
  of Removed, Pinned:
    t.write(indent, addon.line, true,
      fgYellow, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Unpinned:
    t.write(indent, addon.line, true,
      fgGreen, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Restored:
    t.write(indent, addon.line, true,
      fgGreen, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyOldVersion()}", fgWhite, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Failed, NoBackup:
    t.write(indent, addon.line, true,
      fgRed, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyOldVersion()}", fgWhite, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Done, DoneFailed:
    discard
  release(stdoutLock)

proc setAddonState(addon: Addon, state: AddonState, err: string = "") =
  if addon.state != Failed:
    addon.state = state
    addon.errorMsg = err
  chan.send(addon)

proc setName(addon: Addon, json: JsonNode, name: string = "none") =
  if addon.state == Failed: return
  case addon.kind
  of Curse:
    addon.name = json["fileName"].getStr().split('-')[0]
    if addon.name.endsWith(".zip"):
      addon.name = json["fileName"].getStr().split('_')[0]
    if addon.name.endsWith(".zip"):
      addon.name = json["fileName"].getStr().split('.')[0]
  of Github, GithubRepo, Gitlab:
    addon.name = addon.project.split('/')[^1]
  of Tukui:
    addon.name = json["name"].getStr()
  of Wowint:
    addon.name = json[0]["UIName"].getStr()
  if addon.name.len > 34:
    addon.name = addon.name[0 .. 33]

proc setVersion(addon: Addon, json: JsonNode) =
  if addon.state == Failed: return
  addon.old_version = addon.version
  case addon.kind
  of Curse:
    try:
      # Some addons seem to use this as a version string while others exclude it
      addon.version = json["displayName"].getStr()
    except KeyError:
      addon.version = json["dateModified"].getStr()
  of Github:
    let v = json["tag_name"].getStr()
    addon.version = if v != "": v else: json["name"].getStr()
  of GithubRepo:
    addon.version = json["sha"].getStr()
  of Gitlab:
    let v = json[0]["tag_name"].getStr()
    addon.version = if v != "": v else: json[0]["name"].getStr()
  of Tukui:
    addon.version = json["version"].getStr()
  of Wowint:
    addon.version = json[0]["UIVersion"].getStr()

proc getInvalidModeStrings(addon: Addon): seq[string] {.gcsafe.} =
  case addon.config.mode
  of Retail:
    result = @["bcc", "tbc", "wotlk", "wotlkc", "Classic", "classic"]
  of Vanilla:
    result = @["mainline", "bcc", "tbc", "wotlk", "wotlkc", "Classic"]
  of Classic:
    result = @["mainline", "bcc", "tbc", "classic"]
  of None:
    discard

proc setDownloadUrl(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  case addon.kind
  of Curse:
    let id = $json["id"].getInt()
    addon.downloadUrl = &"https://www.curseforge.com/api/v1/mods/{addon.project}/files/{id}/download"
  of Github:
    let assets = json["assets"]
    if len(assets) != 0:
      let invalid = getInvalidModeStrings(addon)
      for asset in assets:
        if asset["content_type"].getStr() == "application/json":
          continue
        let lc = asset["name"].getStr().toLower()
        let ignore = invalid.filter(s => lc.contains(s))
        if len(ignore) == 0:
          addon.downloadUrl = asset["browser_download_url"].getStr()
    else:
      addon.downloadUrl = json["zipball_url"].getStr()
  of GithubRepo:
    addon.downloadUrl = &"https://www.github.com/{addon.project}/archive/refs/heads/{addon.branch.get()}.zip"
  of Gitlab:
    for s in json[0]["assets"]["sources"]:
      if s["format"].getStr() == "zip":
        addon.downloadUrl = s["url"].getStr()
  of Tukui:
    addon.downloadUrl = json["url"].getStr()
  of Wowint:
    addon.downloadUrl = json[0]["UIDownload"].getStr()


proc getLatestUrl(addon: Addon): string =
  case addon.kind
  of Curse:
    return &"https://www.curseforge.com/api/v1/mods/{addon.project}/files"
  of Github:
    return &"https://api.github.com/repos/{addon.project}/releases/latest"
  of Gitlab:
    let urlEncodedProject = addon.project.replace("/", "%2F")
    return &"https://gitlab.com/api/v4/projects/{urlEncodedProject}/releases"
  of Tukui:
    return "https://api.tukui.org/v1/addons/"
  of Wowint:
    return &"https://api.mmoui.com/v3/game/WOW/filedetails/{addon.project}.json"
  of GithubRepo:
    return &"https://api.github.com/repos/{addon.project}/commits/{addon.branch.get()}"


proc getLatest(addon: Addon): Response =
  let url = addon.getLatestUrl()
  var headers = newHttpHeaders()
  case addon.kind
  of Github, GithubRepo:
    if addon.config.githubToken != "":
      headers["Authorization"] = &"token {addon.config.githubToken}"
  else:
    discard
  let client = newHttpClient(headers = headers)
  return client.get(url)

proc download(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  var headers = newHttpHeaders()
  case addon.kind
  of Github, GithubRepo:
    if addon.config.githubToken != "":
      headers["Authorization"] = &"token {addon.config.githubToken}"
  else:
    discard
  let client = newHttpClient(headers = headers)
  let response = client.get(addon.downloadUrl)
  if not response.status.contains("200"):
    addon.setAddonState(Failed, err = &"While downloading got response {response.status}: {addon.getLatestUrl()}")
    return
  var downloadName: string
  case addon.kind:
  of Curse:
    downloadName = json["fileName"].getStr()
  else:
    try:
      downloadName = response.headers["content-disposition"].split('=')[1].strip(chars = {'\'', '"'})
    except KeyError:
      downloadName = addon.downloadUrl.split('/')[^1]
  addon.filename = addon.config.tempDir / downloadName
  var file: File
  try:
    file = open(addon.filename, fmWrite)
  except CatchableError as e:
    addon.setAddonState(Failed, e.msg)
    return
  try:
    system.write(file, response.body)
  except:
    addon.setAddonState(Failed, &"Encountered a problem while downloading.")
  close(file)

proc processTocs(path: string): bool =
  for kind, file in walkDir(path):
    if kind == pcFile:
      var (dir, name, ext) = splitFile(file)
      if ext == ".toc":
        if name != lastPathPart(dir):
          let p = re("(.+?)(?:$|[-_](?i:mainline|Classic|tbc|vanilla|wotlkc?|bcc|classic))", flags = {reIgnoreCase})
          var m: array[2, string]
          discard find(cstring(name), p, m, 0, len(name))
          name = m[0]
          moveDir(dir, parentDir(dir) / name)
        return true
  return false

proc getAddonDirs(addon: Addon): seq[string] =
  var current = addon.extractDir
  var firstPass = true
  while true:
    let toc = processTocs(current)
    if not toc:
      let subdirs = collect(for kind, dir in walkDir(current): (if kind == pcDir: dir))
      assert len(subdirs) != 0 
      current = subdirs[0]
    else:
      if firstPass: return @[current]
      else: return collect(for kind, dir in walkDir(parentDir(current)): (if kind == pcDir: dir))
    firstPass = false

proc getBackupFiles(addon: Addon): seq[string] {.gcsafe.} = 
  var name = $addon.kind & addon.project
  for c in invalidFilenameChars:
    name = name.replace(c, '-')
  var backups = collect(
    for kind, path in walkDir(addon.config.backupDir): 
      if kind == pcFile and lastPathPart(path).contains(name):
        path
  )
  # oldest to newest
  backups.sort((a, b) => int(getCreationTime(a).toUnix() - getCreationTime(b).toUnix()))
  return backups

proc removeAddonFiles(addon: Addon, removeAllBackups: bool) =
  for dir in addon.dirs:
    removeDir(addon.config.installDir / dir)
  var backups = getBackupFiles(addon)
  if removeAllBackups:
    for file in backups:
      removeFile(file)

proc setIdAndCleanup(addon: Addon) =
  for a in addon.config.addons:
    if a == addon:
      addon.id = a.id
      a.removeAddonFiles(removeAllBackups = false)
      break

proc moveDirs(addon: Addon) {.gcsafe.} =
  if addon.state == Failed: return
  var source = addon.getAddonDirs()
  source.sort()
  addon.setIdAndCleanup()
  addon.dirs = @[]
  for dir in source:
    let name = lastPathPart(dir)
    addon.dirs.add(name)
    let destination = addon.config.installDir / name
    try:
      moveDir(dir, destination)
    except CatchableError as e:
      addon.setAddonState(Failed, e.msg)

proc createBackup(addon: Addon) {.gcsafe.} =
  if addon.state == Failed: return
  let backups = getBackupFiles(addon)
  var name = $addon.kind & addon.project & "&V=" & addon.version & ".zip"
  for c in invalidFilenameChars:
    name = name.replace(c, '-')
  createDir(addon.config.backupDir)
  if len(backups) > 1:
    removeFile(backups[0])
  try:
    moveFile(addon.filename, addon.config.backupDir / name)
  except CatchableError as e:
    addon.setAddonState(Failed, e.msg)
    discard

proc unzip(addon: Addon) {.gcsafe.} =
  if addon.state == Failed: return
  let (_, name, _) = splitFile(addon.filename)
  addon.extractDir = addon.config.tempDir / name
  removeDir(addon.extractDir)
  try:
    extractAll(addon.filename, addon.extractDir)
  except CatchableError as e:
    addon.setAddonState(Failed, e.msg)
    discard

proc curseGetProject(addon: Addon) {.gcsafe.} =
  try:
    var driver = newChromeDriver()
    let agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3683.86 Safari/537.36"
    var options = %*{
      "excludeSwitches": ["enable-automation", "enable-logging"],
      "args": ["--window-size=1024,800", "--log-level=3", &"--user-agent={agent}"]
    }
    waitFor driver.startSession(options, headless = true)
    waitFor driver.setUrl(addon.project & "/download")

    var element = waitFor driver.waitElement(xPath, "/html/body/div/main/div[3]/div[1]/p/a")
    let href = waitFor driver.getElementAttribute(element, "href")
    var match: array[1, string]
    let pattern = re"\/mods\/(\d+)\/"
    discard find(cstring(href), pattern, match, 0, len(href))
    addon.project = match[0]

    waitFor driver.deleteSession()
    waitFor driver.close()
  except CatchableError as e:
    addon.setAddonState(Failed, &"{e.name}\n{e.msg}")
    if e.name == $OSError and e.msg.startsWith("The parameter is incorrect"):
      addon.setAddonState(Failed, &"Unable to launch chromedriver. This must be installed in order to use addons from curseforge.\n    For more details: lycan --help webdriver")
    else:
      addon.setAddonState(Failed, &"{e.name}: {e.msg}")
  except:
    addon.setAddonState(Failed, &"Unknown error. Try again and if the problem persists open an issue at https://github.com/inverimus/lycan")

proc getLatestJson(addon: Addon): JsonNode {.gcsafe.} =
  var json: JsonNode
  let response = addon.getLatest()
  if not response.status.contains("200"):
    addon.setAddonState(Failed, err = &"Response while retrieving latest addon info {response.status}: {addon.getLatestUrl()}")
    return
  json = parseJson(response.body)
  case addon.kind:
  of Curse:
    var gameVersions: seq[string]
    var gameVersionNumber = case addon.config.mode
      of Retail: "10."
      of Vanilla: "1."
      of Classic: "3."
      of None: ""
    for i, data in enumerate(json["data"]):
      gameVersions.fromJson(data["gameVersions"])
      for num in gameVersions:
        if num.startsWith(gameVersionNumber):
          return json["data"][i]
    addon.setAddonState(Failed, &"JSON Error: No game version matches current mode of {addon.config.mode}.")
  of Tukui:
    for data in json:
      if data["slug"].getStr() == addon.project:
        return data
    addon.setAddonState(Failed, "JSON Error: Addon not found.")
    return
  else:
    discard
  return json

proc install*(addon: Addon) {.gcsafe.} =
  addon.setAddonState(Checking)
  if addon.kind == Curse and addon.project.startsWith("https://"):
    addon.curseGetProject()
  let json = addon.getLatestJson()
  addon.setAddonState(Parsing)
  addon.setVersion(json)
  if addon.pinned:
    addon.setAddonState(FinishedPinned)
    return
  if addon.version != addon.oldVersion:
    addon.time = now()
    addon.setDownloadUrl(json)
    addon.setName(json)
    addon.setAddonState(Downloading)
    addon.download(json)
    addon.setAddonState(Installing)
    addon.unzip()
    addon.createBackup()
    addon.moveDirs()
    if addon.oldVersion.isEmptyOrWhitespace:
      addon.setAddonState(FinishedInstalled)
    else:
      addon.setAddonState(FinishedUpdated)
  else:
    addon.setAddonState(FinishedAlreadyCurrent)

proc uninstall*(addon: Addon) =
  addon.removeAddonFiles(removeAllBackups = true)
  addon.setAddonState(Removed)

proc pin*(addon: Addon) =
  addon.pinned = true
  addon.setAddonState(Pinned)

proc unpin*(addon: Addon) =
  addon.pinned = false
  addon.setAddonState(Unpinned)

proc list*(addons: var seq[Addon], sortByTime: bool = false) =
  if sortByTime:
    addons.sort((a, z) => int(a.time < z.time))
  for line, addon in enumerate(addons):
    addon.line = line
  if addons.len == 0:
    echo "No addons installed"
    quit()
  let
    t = configData.term
    nameSpace = addons[addons.map(a => a.name.len).maxIndex()].name.len + 2
    versionSpace = addons[addons.map(a => a.version.len).maxIndex()].version.len + 2
  for addon in addons:
    let
      kind = case addon.kind 
        of GithubRepo: "Github"
        else: $addon.kind      
      pin = if addon.pinned: "!" else: ""
      branch = if addon.branch.isSome: addon.branch.get() else: ""
      time = addon.time.format("MM/dd h:mm")
    t.write(1, addon.line, true,
      fgBlue, &"{addon.id:<3}",
      fgWhite, &"{addon.name.alignLeft(nameSpace)}",
      fgRed, pin,
      fgGreen, &"{addon.prettyVersion().alignLeft(versionSpace)}",
      fgCyan, &"{kind:<6}",
      fgWhite, if addon.branch.isSome: "@" else: "",
      fgBlue, if addon.branch.isSome: &"{branch:<11}" else: &"{branch:<12}",
      fgWhite, &"{time}",
      resetStyle)
  t.write(0, t.yMax, false, "\n")
  quit()

proc restore*(addon: Addon) =
  addon.setAddonState(Restoring)
  var backups = getBackupFiles(addon)
  if len(backups) < 2:
    addon.setAddonState(NoBackup)
    return
  let filename = backups[0]
  let start = filename.find("&V=") + 3
  addon.filename = filename
  addon.oldVersion = addon.version
  addon.version = filename[start .. ^5] #exclude .zip
  addon.time = getFileInfo(filename).creationTime.local()
  addon.unzip()
  addon.moveDirs()
  addon.setAddonState(Restored)
  if addon.state != Failed:
    removeFile(backups[1])

proc workQueue*(addon: Addon) {.thread.} =
  case addon.action:
  of Install: addon.install()
  of Remove:  addon.uninstall()
  of Pin:     addon.pin()
  of Unpin:   addon.unpin()
  of Restore: addon.restore()
  else: discard
  if addon.state == Failed:
    addon.state = DoneFailed
  else:
    addon.state = Done
  chan.send(addon)
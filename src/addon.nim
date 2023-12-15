import std/algorithm
import std/colors
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

import config
import types
import term
import logger

proc `==`*(a, b: Addon): bool {.inline.} =
  a.project == b.project

proc newAddon*(project: string, kind: AddonKind, branch: Option[string] = none(string), name: string = ""): Addon =
  result = new(Addon)
  result.project = project
  result.kind = kind
  result.branch = branch

proc assignIds*(addons: seq[Addon]) =
  var ids: set[int16]
  addons.apply((a: Addon) => ids.incl(a.id))
  var id: int16 = 1
  for a in addons:
    if a.id == 0:
      while id in ids: id += 1
      a.id = id
      incl(ids, id)

proc toJsonHook*(a: Addon): JsonNode =
  result = newJObject()
  result["project"] = %a.project
  if a.branch.isSome: result["branch"] = %a.branch.get
  result["name"] = %a.name
  if a.overrideName.isSome: result["overrideName"] = %a.overrideName.get
  result["kind"] = %a.kind
  result["version"] = %a.version
  result["id"] = %a.id
  result["pinned"] = %a.pinned
  result["dirs"] = %a.dirs
  result["time"] = %a.time.format("yyyy-MM-dd'T'HH:mm")

proc writeAddons*(addons: var seq[Addon]) =
  if configData.addonJsonFile != "":
    addons.sort((a, z) => int(a.name.toLower() > z.name.toLower()))
    let addonsJson = addons.toJson(ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef))
    try:
      writeFile(configData.addonJsonFile, pretty(addonsJson))
      log(&"Installed addons file saved: {configData.addonJsonFile}", Info)
    except Exception as e:
      log(&"Fatal error writing installed addons file: {configData.addonJsonFile}", Fatal, e)

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

const DARK_GREY: Color = Color(0x20_20_20)
const LIGHT_GREY: Color = Color(0x34_34_34)

proc getName*(addon: Addon): string =
  if addon.overrideName.isSome: return addon.overrideName.get
  result = if not addon.name.isEmptyOrWhitespace: addon.name 
  else: $addon.kind & ':' & addon.project

proc stateMessage*(addon: Addon, nameSpace: int) = 
  let 
    t = configData.term
    indent = 2
    even = addon.line mod 2 == 0
    arrow = if addon.old_version.isEmptyOrWhitespace: "" else: "->"
    colors = if even: (fgDefault, DARK_GREY) else: (fgDefault, LIGHT_GREY)
    style = if not t.trueColor: (if even: styleBright else: styleReverse) else: styleBright
  acquire(stdoutLock)
  case addon.state
  of Checking, Parsing:
    t.write(indent, addon.line, true, colors, style,
      fgCyan, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyOldVersion()}", resetStyle)
  of Downloading, Installing, Restoring:
    t.write(indent, addon.line, true, colors, style,
      fgCyan, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyOldVersion()}", fgWhite, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of FinishedUpdated, FinishedInstalled:
    t.write(indent, addon.line, true, colors, style,
      fgGreen, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyOldVersion()}", fgWhite, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of FinishedAlreadyCurrent:
    t.write(indent, addon.line, true, colors, style,
      fgGreen, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyVersion()}", resetStyle)
  of FinishedPinned:
    t.write(indent, addon.line, true, colors, style,
      fgYellow, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      styleBright, fgRed, &"{addon.prettyOldVersion()}", fgWhite, &"{arrow}", 
      if addon.version != addon.oldVersion: fgGreen else: fgYellow,
      &"{addon.prettyVersion()}", resetStyle)
  of Removed, Pinned:
    t.write(indent, addon.line, true, colors, style,
      fgYellow, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Unpinned, Renamed:
    t.write(indent, addon.line, true, colors, style,
      fgGreen, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Restored:
    t.write(indent, addon.line, true, colors, style,
      fgGreen, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyOldVersion()}", fgWhite, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Failed, NoBackup:
    t.write(indent, addon.line, true, colors, style,
      fgRed, &"{$addon.state:<12}", fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgYellow, &"{addon.prettyOldVersion()}", fgWhite, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Done, DoneFailed:
    discard
  release(stdoutLock)

proc setAddonState(addon: Addon, state: AddonState, loggedMsg: string, level: LogLevel = Info) {.gcsafe.} =
  if addon.state != Failed:
    addon.state = state
  logChannel.send(LogMessage(level: level, msg: loggedMsg, e: nil))
  addonChannel.send(addon.deepCopy())

proc setAddonState(addon: Addon, state: AddonState, errorMsg: string, loggedMsg: string, e: ref Exception = nil, level: LogLevel = Fatal) {.gcsafe.} =
  addon.state = state
  addon.errorMsg = errorMsg
  logChannel.send(LogMessage(level: level, msg: loggedMsg, e: e))
  addonChannel.send(addon.deepCopy())

proc setName(addon: Addon, json: JsonNode, name: string = "none") {.gcsafe.} =
  if addon.state == Failed: return
  if addon.overrideName.isSome: addon.name = addon.overrideName.get
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

proc setVersion(addon: Addon, json: JsonNode) {.gcsafe.} =
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

proc getLatestUrl(addon: Addon): string {.gcsafe.} =
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
    return &"https://api.github.com/repos/{addon.project}/commits/{addon.branch.get}"

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

proc download(addon: Addon, json: JsonNode) {.gcsafe.} =
  if addon.state == Failed: return
  var headers = newHttpHeaders()
  case addon.kind
  of Github, GithubRepo:
    if addon.config.githubToken != "":
      headers["Authorization"] = &"Bearer {addon.config.githubToken}"
  else:
    discard
  let client = newHttpClient(headers = headers)
  let response = client.get(addon.downloadUrl)
  if not response.status.contains("200"):
    addon.setAddonState(Failed, &"Bad response downloading {response.status}: {addon.getLatestUrl()}",
    &"{addon.name} download failed. Response code {response.status} from {addon.getLatestUrl()}")
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
  except Exception as e:
    addon.setAddonState(Failed, &"Problem opening file {addon.filename}", &"download failed, error opening file {addon.filename}", e)
    return
  try:
    system.write(file, response.body)
  except Exception as e:
    addon.setAddonState(Failed, &"Problem encountered while downloading.", &"download failed, error writing {addon.filename}", e)
  close(file)

proc tocDir(path: string): bool {.gcsafe.} =
  for kind, file in walkDir(path):
    if kind == pcFile:
      var (dir, name, ext) = splitFile(file)
      if ext == ".toc":
        if name != lastPathPart(dir):
          let p = re("(.+?)(?:$|[-_](?i:mainline|classic|wrath|tbc|bcc))", flags = {reIgnoreCase})
          var m: array[2, string]
          discard find(cstring(name), p, m, 0, len(name))
          name = m[0]
          moveDir(dir, dir.parentDir() / name)
        return true
  return false

proc getAddonDirs(addon: Addon): seq[string] {.gcsafe.} =
  var current = addon.extractDir
  var firstPass = true
  while true:
    if not tocDir(current):
      log(&"{addon.name}: extractDir contains no toc files, collecting subdirectories")
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

proc removeAddonFiles(addon: Addon, installDir: string, removeAllBackups: bool) {.gcsafe.} =
  for dir in addon.dirs:
    removeDir(installDir / dir)
  if removeAllBackups:
    var backups = addon.getBackupFiles()
    for file in backups:
      removeFile(file)

proc setIdAndCleanup(addon: Addon) {.gcsafe.} =
  for a in addon.config.addons:
    if a == addon:
      addon.id = a.id
      a.removeAddonFiles(addon.config.installDir, removeAllBackups = false)
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
    except Exception as e:
      addon.setAddonState(Failed, "Problem moving Addon directories.", &"{addon.name} move directories error", e)
  log(&"{addon.name}: Files moved to install directory.", Info)

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
    log(&"{addon.name}: Backup created {addon.config.backupDir / name}", Info)
  except Exception as e:
    addon.setAddonState(Failed, "Problem creating backup files.", &"{addon.name}: create backup error", e)
    discard

proc unzip(addon: Addon) {.gcsafe.} =
  if addon.state == Failed: return
  let (_, name, _) = splitFile(addon.filename)
  addon.extractDir = addon.config.tempDir / name
  removeDir(addon.extractDir)
  try:
    extractAll(addon.filename, addon.extractDir)
    log(&"{addon.name}: Extracted {addon.filename}", Info)
  except Exception as e:
    addon.setAddonState(Failed, "Problem unzipping files.", &"{addon.name}: unzip error", e)
    discard

proc getLatest(addon: Addon): Response {.gcsafe.} =
  addon.setAddonState(Checking, &"Checking: {addon.getName()} getting latest version information")
  let url = addon.getLatestUrl()
  var headers = newHttpHeaders()
  case addon.kind
  of Github, GithubRepo:
    if addon.config.githubToken != "":
      headers["Authorization"] = &"Bearer {addon.config.githubToken}"
  else:
    discard
  var retryCount = 0
  let client = newHttpClient(headers = headers)
  var response: Response
  while true:
    try:
      response = client.get(url)
      if response.status.contains("200"):
        return response
      else:
        retryCount += 1
    except:
      retryCount += 1
    if retryCount > 4:
      if addon.kind == Github and response.status.contains("404"):
        log(&"{addon.name}: Got {response.status}: {addon.getLatestUrl()} - This usually means no releases are available so switching to trying main/master branch", Warning)
        let resp = client.get(&"https://api.github.com/repos/{addon.project}/branches")
        let branches = parseJson(resp.body)
        let names = collect(for item in branches: item["name"].getStr())
        if names.contains("master"):
          addon.branch = some("master")
        elif names.contains("main"):
          addon.branch = some("main")
        else:
          log(&"{addon.name}: No branch named master or main avaialable", Warning)
          addon.setAddonState(Failed, &"Bad response retrieving latest addon info - {response.status}: {addon.getLatestUrl()}",
          &"Get latest JSON bad response: {response.status}")
        addon.kind = GithubRepo
        return addon.getLatest()
      else:
        addon.setAddonState(Failed, &"Bad response retrieving latest addon info - {response.status}: {addon.getLatestUrl()}",
        &"Get latest JSON bad response: {response.status}")
      return
    sleep(100)

proc getLatestJson(addon: Addon): JsonNode {.gcsafe.} =
  var json: JsonNode
  let response = addon.getLatest()
  if addon.state == Failed: return
  try:
    json = parseJson(response.body)
  except Exception as e:
    addon.setAddonState(Failed, "JSON parsing error.", &"JSON Error: {addon.name} Unable to parse json.", e)
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
    addon.setAddonState(Failed, &"JSON Error: No game version matches current mode of {addon.config.mode}.",
    &"JSON Error: {addon.name} no game version matches current mode of {addon.config.mode}.")
  of Tukui:
    for data in json:
      if data["slug"].getStr() == addon.project:
        return data
    addon.setAddonState(Failed, "JSON Error: Addon not found.", &"JSON Error: {addon.name} not found.")
    return
  else:
    discard
  return json

proc install*(addon: Addon) {.gcsafe.} =
  let json = addon.getLatestJson()
  addon.setAddonState(Parsing, &"Parsing: {addon.getName()} JSON for latest version")
  addon.setVersion(json)
  if addon.pinned:
    addon.setAddonState(FinishedPinned, &"Finished: {addon.getName()} not updated, pinned to version {addon.version}")
    return
  if addon.version != addon.oldVersion:
    addon.time = now()
    addon.setDownloadUrl(json)
    addon.setName(json)
    addon.setAddonState(Downloading, &"Downloading: {addon.getName()}")
    addon.download(json)
    addon.setAddonState(Installing, &"Installing: {addon.getName()}")
    addon.unzip()
    addon.createBackup()
    addon.moveDirs()
    if addon.oldVersion.isEmptyOrWhitespace:
      addon.setAddonState(FinishedInstalled, &"Installed: {addon.getName()} installed at version {addon.version}")
    else:
      addon.setAddonState(FinishedUpdated, &"Updated: {addon.getName()} updated from {addon.oldVersion} to {addon.version}")
  else:
    addon.setAddonState(FinishedAlreadyCurrent, &"Finished: {addon.getName()} already up to date.")

proc uninstall*(addon: Addon) =
  addon.removeAddonFiles(addon.config.installDir, removeAllBackups = true)
  addon.setAddonState(Removed, &"Removed: {addon.getName()}")

proc pin*(addon: Addon) =
  addon.pinned = true
  addon.setAddonState(Pinned, &"Pinned: {addon.getName()} pinned to version {addon.version}")

proc unpin*(addon: Addon) =
  addon.pinned = false
  addon.setAddonState(Unpinned, &"Unpinned: {addon.getName()}")

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
      even = addon.line mod 2 == 0
      colors = if even: (fgDefault, DARK_GREY) else: (fgDefault, LIGHT_GREY)
      style = if not t.trueColor: (if even: styleBright else: styleReverse) else: styleBright
      kind = case addon.kind 
        of GithubRepo: "Github"
        else: $addon.kind      
      pin = if addon.pinned: "!" else: ""
      branch = if addon.branch.isSome: addon.branch.get() else: ""
      time = addon.time.format("MM/dd h:mm")
    t.write(1, addon.line, true, colors, style,
      fgBlue, &"{addon.id:<3}",
      fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
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
  addon.setAddonState(Restoring, &"Restoring: {addon.getName()}")
  var backups = getBackupFiles(addon)
  if len(backups) < 2:
    addon.setAddonState(NoBackup, &"Restoring Error: {addon.getName()} has no backups to restore")
    return
  let filename = backups[0]
  let start = filename.find("&V=") + 3
  addon.filename = filename
  addon.oldVersion = addon.version
  addon.version = filename[start .. ^5] #exclude .zip
  addon.time = getFileInfo(filename).creationTime.local()
  addon.unzip()
  addon.moveDirs()
  addon.setAddonState(Restored, &"Restore Finished: {addon.getName()}")
  if addon.state != Failed:
    removeFile(backups[1])

proc setOverrideName(addon: Addon) =
  addon.setAddonState(Renamed, &"{addon.name} renamed to {addon.getName()}")

proc workQueue*(addon: Addon) {.thread.} =
  case addon.action
  of Install: addon.install()
  of Remove:  addon.uninstall()
  of Pin:     addon.pin()
  of Unpin:   addon.unpin()
  of Restore: addon.restore()
  of Name:    addon.setOverrideName()
  else: discard
  if addon.state == Failed:
    addon.state = DoneFailed
  else:
    addon.state = Done
  addonChannel.send(addon)
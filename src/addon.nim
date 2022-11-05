import std/algorithm
import std/asyncdispatch
import std/colors
import std/httpclient
import std/json
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

proc `==`*(a, b: Addon): bool {.inline.} =
  a.project == b.project

proc newAddon*(project: string, kind: AddonKind, branch: Option[string] = none(string)): Addon =
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

const DARK_GREY: Color = Color(0x20_20_20)
const LIGHT_GREY: Color = Color(0x34_34_34)

proc getName*(addon: Addon): string =
  result = if not addon.name.isEmptyOrWhitespace: addon.name 
  else: $addon.kind & ':' & addon.project

proc stateMessage(addon: Addon) = 
  let 
    t = configData.term
    indent = 2
    even = addon.line mod 2 == 0
    arrow = if addon.old_version.isEmptyOrWhitespace: "" else: "->"
    colors = if even: (fgDefault, DARK_GREY) else: (fgDefault, LIGHT_GREY)
    style = if not t.trueColor: (if even: styleBright else: styleReverse) else: styleBright
  case addon.state
  of Checking, Parsing:
    t.write(indent, addon.line, true, colors, style,
      fgCyan, &"{$addon.state:<12}", fgDefault, &"{addon.getName():<32}",
      fgYellow, &"{addon.prettyOldVersion()}", resetStyle)
  of Downloading, Installing, Restoring:
    t.write(indent, addon.line, true, colors, style,
      fgCyan, &"{$addon.state:<12}", fgDefault, &"{addon.getName():<32}",
      fgYellow, &"{addon.prettyOldVersion()}", fgDefault, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of FinishedUpdated, FinishedInstalled:
    t.write(indent, addon.line, true, colors, style,
      fgGreen, &"{$addon.state:<12}", fgDefault, &"{addon.getName():<32}",
      fgYellow, &"{addon.prettyOldVersion()}", fgDefault, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of FinishedAlreadyCurrent:
    t.write(indent, addon.line, true, colors, style,
      fgGreen, &"{$addon.state:<12}", fgDefault, &"{addon.getName():<32}",
      fgYellow, &"{addon.prettyVersion()}", resetStyle)
  of FinishedPinned:
    t.write(indent, addon.line, true, colors, style,
      fgYellow, &"{$addon.state:<12}", fgDefault, &"{addon.getName():<32}",
      styleBright, fgRed, &"{addon.prettyOldVersion()}", fgDefault, &"{arrow}", 
      if addon.version != addon.oldVersion: fgGreen else: fgYellow,
      &"{addon.prettyVersion()}", resetStyle)
  of Removed, Pinned:
    t.write(indent, addon.line, true, colors, style,
      fgYellow, &"{$addon.state:<12}", fgDefault, &"{addon.getName():<32}",
      fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Unpinned:
    t.write(indent, addon.line, true, colors, style,
      fgGreen, &"{$addon.state:<12}", fgDefault, &"{addon.getName():<32}",
      fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Restored:
    t.write(indent, addon.line, true, colors, style,
      fgGreen, &"{$addon.state:<12}", fgDefault, &"{addon.getName():<32}",
      fgYellow, &"{addon.prettyOldVersion()}", fgDefault, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Failed, NoBackup:
    t.write(indent, addon.line, true, colors, style,
      fgRed, &"{$addon.state:<12}", fgDefault, &"{addon.getName():<32}",
      fgYellow, &"{addon.prettyOldVersion()}", fgDefault, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)

proc setAddonState(addon: Addon, state: AddonState, err: string = "", sendMessage: bool = true) =
  if addon.state != Failed:
    addon.state = state
  if err != "":
    configData.log.add(Error(addon: addon, msg: err))
  if sendMessage:
    addon.stateMessage()

proc setName(addon: Addon, json: JsonNode) =
  if addon.state == Failed: return
  case addon.kind
  of Github, GithubRepo, Gitlab:
    addon.name = addon.project.split('/')[^1]
  of TukuiMain, TukuiAddon:
    addon.name = json["name"].getStr()
  of Wowint:
    addon.name = json[0]["UIName"].getStr()

proc setVersion(addon: Addon, json: JsonNode) =
  if addon.state == Failed: return
  addon.old_version = addon.version
  case addon.kind
  of Github:
    let v = json["tag_name"].getStr()
    addon.version = if v != "": v else: json["name"].getStr()
  of GithubRepo:
    addon.version = json["sha"].getStr()
  of Gitlab:
    let v = json[0]["tag_name"].getStr()
    addon.version = if v != "": v else: json[0]["name"].getStr()
  of TukuiMain, TukuiAddon:
    addon.version = json["version"].getStr()
  of Wowint:
    addon.version = json[0]["UIVersion"].getStr()

proc getInvalidModeStrings(mode: Mode): seq[string] =
  case configData.mode
  of Retail:
    result = @["bcc", "tbc", "wotlk", "wotlkc", "wrath", "classic"]
  of Classic:
    result = @["mainline", "classic"]
  of Vanilla:
    result = @["mainline", "bcc", "tbc", "wotlk", "wotlkc", "wrath"]
  of None:
    discard

proc setDownloadUrl(addon: Addon, json: JsonNode) =
  if addon.state == Failed: return
  case addon.kind
  of Github:
    let assets = json["assets"]
    if len(assets) != 0:
      let invalid = getInvalidModeStrings(configData.mode)
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
  of TukuiMain, TukuiAddon:
    addon.downloadUrl = json["url"].getStr()
  of Wowint:
    addon.downloadUrl = json[0]["UIDownload"].getStr()


proc getLatestUrl(addon: Addon): string =
  case addon.kind
    of Github:
      return &"https://api.github.com/repos/{addon.project}/releases/latest"
    of Gitlab:
      let urlEncodedProject = addon.project.replace("/", "%2F")
      return &"https://gitlab.com/api/v4/projects/{urlEncodedProject}/releases"
    of TukuiMain:
        return &"https://www.tukui.org/api.php?ui={addon.project}"
    of TukuiAddon:
      return "https://www.tukui.org/api.php?addons"
    of Wowint:
      return &"https://api.mmoui.com/v3/game/WOW/filedetails/{addon.project}.json"
    of GithubRepo:
      return &"https://api.github.com/repos/{addon.project}/commits/{addon.branch.get()}"


proc getLatest(addon: Addon): Future[AsyncResponse] {.async.} =
  let url = addon.getLatestUrl()
  var headers = newHttpHeaders()
  case addon.kind
  of Github, GithubRepo:
    if configData.githubToken != "":
      headers["Authorization"] = &"token {configData.githubToken}"
  else:
    discard
  let client = newAsyncHttpClient(headers = headers)
  return await client.get(url)


proc download(addon: Addon) {.async.} =
  if addon.state == Failed: return
  var headers = newHttpHeaders()
  case addon.kind
  of Github, GithubRepo:
    if configData.githubToken != "":
      headers["Authorization"] = &"token {configData.githubToken}"
  else:
    discard
  let client = newAsyncHttpClient(headers = headers)
  let futureResponse = client.get(addon.downloadUrl)
  yield futureResponse
  if futureResponse.failed:
    addon.setAddonState(Failed, &"No response: {addon.downloadUrl}")
    return
  let response = futureResponse.read()
  if not response.status.contains("200"):
    addon.setAddonState(Failed, err = &"Response {response.status}: {addon.getLatestUrl()}")
    return
  var downloadName: string
  try:
    downloadName = response.headers["content-disposition"].split('=')[1].strip(chars = {'\'', '"'})
  except KeyError:
    downloadName = addon.downloadUrl.split('/')[^1]
  addon.filename = joinPath(configData.tempDir, downloadName)
  var file: File
  try:
    file = open(addon.filename, fmWrite)
  except CatchableError as e:
    addon.setAddonState(Failed, e.msg)
    return
  let futureBody = response.body
  yield futureBody
  if futureBody.failed:
    addon.setAddonState(Failed, &"Download failed: {addon.downloadUrl}")
    return
  system.write(file, futureBody.read())
  close(file)

proc processTocs(path: string): bool =
  for kind, file in walkDir(path):
    if kind == pcFile:
      var (dir, name, ext) = splitFile(file)
      if ext == ".toc":
        if name != lastPathPart(dir):
          let p = re("(.+?)(?:$|[-_](?i:mainline|wrath|tbc|vanilla|wotlkc?|bcc|classic))", flags = {reIgnoreCase})
          var m: array[2, string]
          discard find(cstring(name), p, m, 0, len(name))
          name = m[0]
          moveDir(dir, joinPath(parentDir(dir), name))
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

proc getBackupFiles(addon: Addon): seq[string] = 
  var name = $addon.kind & addon.project
  for c in invalidFilenameChars:
    name = name.replace(c, '-')
  var backups = collect(
    for kind, path in walkDir(configData.backupDir): 
      if kind == pcFile and lastPathPart(path).contains(name):
        path
  )
  # oldest to newest
  backups.sort((a, b) => int(getCreationTime(a).toUnix() - getCreationTime(b).toUnix()))
  return backups

proc removeAddonFiles(addon: Addon, removeAllBackups: bool) =
  addon.dirs.apply(d => removeDir(d))
  var backups = getBackupFiles(addon)
  if removeAllBackups:
    backups.apply(removeFile)

proc setIdAndCleanup(addon: Addon) =
  for a in configData.addons:
    if a == addon:
      addon.id = a.id
      a.removeAddonFiles(removeAllBackups = false)
      break

proc moveDirs(addon: Addon) =
  if addon.state == Failed: return
  var source = addon.getAddonDirs()
  source.sort()
  addon.setIdAndCleanup()
  addon.dirs = @[]
  for dir in source:
    let name = lastPathPart(dir)
    addon.dirs.add(name)
    let destination = joinPath(configData.installDir, name)
    try:
      moveDir(dir, destination)
    except CatchableError as e:
      addon.setAddonState(Failed, e.msg)

proc createBackup(addon: Addon) =
  if addon.state == Failed: return
  let backups = getBackupFiles(addon)
  var name = $addon.kind & addon.project & "&V=" & addon.version & ".zip"
  for c in invalidFilenameChars:
    name = name.replace(c, '-')
  createDir(configData.backupDir)
  if len(backups) > 1:
    removeFile(backups[0])
  try:
    moveFile(addon.filename, joinPath(configData.backupDir, name))
  except CatchableError as e:
    addon.setAddonState(Failed, e.msg)

proc unzip(addon: Addon) =
  if addon.state == Failed: return
  let (_, name, _) = splitFile(addon.filename)
  addon.extractDir = joinPath(configData.tempDir, name)
  try:
    extractAll(addon.filename, addon.extractDir)
  except CatchableError as e:
    addon.setAddonState(Failed, e.msg)

proc getLatestJson(addon: Addon): Future[JsonNode] {.async.} =
  var json: JsonNode
  if addon.kind != TukuiAddon or (addon.kind == TukuiAddon and configData.tukuiCache.isNil):
    let futureResponse = addon.getLatest()
    yield futureResponse
    if futureResponse.failed:
      addon.setAddonState(Failed, &"No response: {addon.getLatestUrl()}")
      return
    let response = futureResponse.read()
    if not response.status.contains("200"):
      addon.setAddonState(Failed, err = &"Response {response.status}: {addon.getLatestUrl()}")
      return
    let futureBody = response.body
    yield futureBody
    if futureBody.failed:
      addon.setAddonState(Failed, &"Failed to download json: {addon.getLatestUrl()}")
      return
    json = parseJson(futureBody.read())
  if addon.kind == TukuiAddon:
    if configData.tukuiCache.isNil:
      configData.tukuiCache = json
    for node in configData.tukuiCache:
      if node["id"].getStr() == addon.project:
        return node
    addon.setAddonState(Failed, "Addon not found in json")
    return
  return json

proc install*(addon: Addon): Future[Option[Addon]] {.async.} =
  addon.setAddonState(Checking)
  let json = await addon.getLatestJson()
  addon.setAddonState(Parsing)
  addon.setVersion(json)
  if addon.pinned:
    addon.setAddonState(FinishedPinned)
    return none(Addon)
  if addon.version != addon.oldVersion:
    addon.time = now()
    addon.setDownloadUrl(json)
    addon.setName(json)
    addon.setAddonState(Downloading)
    await addon.download()
    addon.setAddonState(Installing)
    addon.unzip()
    addon.createBackup()
    addon.moveDirs()
    if addon.oldVersion.isEmptyOrWhitespace:
      addon.setAddonState(FinishedInstalled)
    else:
      addon.setAddonState(FinishedUpdated)
    if addon.state == Failed:
      return none(Addon)
    return some(addon)
  else:
    addon.setAddonState(FinishedAlreadyCurrent)
    return none(Addon)

proc uninstall*(addon: Addon): Addon =
  addon.removeAddonFiles(removeAllBackups = true)
  addon.setAddonState(Removed)
  return addon

proc pin*(addon: Addon): Addon =
  addon.pinned = true
  addon.setAddonState(Pinned)
  return addon

proc unpin*(addon: Addon): Addon =
  addon.pinned = false
  addon.setAddonState(Unpinned)
  return addon

proc list*(addon: Addon) =
  let
    t = configData.term
    even = addon.line mod 2 == 0
    colors = if even: (fgDefault, DARK_GREY) else: (fgDefault, LIGHT_GREY)
    style = if not t.trueColor: (if even: styleBright else: styleReverse) else: styleBright
    kind = case addon.kind 
      of TukuiMain, TukuiAddon: "Tukui"
      of GithubRepo: "Github"
      else: $addon.kind
    pin = if addon.pinned: "!" else: ""
    branch = if addon.branch.isSome: addon.branch.get() else: ""
    time = addon.time.format("MM/dd h:mm")
  t.write(1, addon.line, true, colors, style,
    fgBlue, &"{addon.id:<3}",
    fgDefault, &"{addon.name:<32}",
    fgRed, pin,
    fgGreen, &"{addon.prettyVersion():<20}",
    fgCyan, &"{kind:<6}",
    fgDefault, if addon.branch.isSome: "@" else: "",
    fgBlue, if addon.branch.isSome: &"{branch:<11}" else: &"{branch:<12}",
    fgDefault, &"{time}",
    resetStyle)

proc restore*(addon: Addon): Option[Addon] =
  addon.setAddonState(Restoring)
  var backups = getBackupFiles(addon)
  if len(backups) < 2:
    addon.setAddonState(NoBackup)
    return none(Addon)
  let filename = backups[0]
  let start = filename.find("&V=") + 3
  addon.filename = filename
  addon.oldVersion = addon.version
  addon.version = filename[start .. ^5] #exclude .zip
  addon.time = getFileInfo(filename).creationTime.local()
  addon.unzip()
  addon.moveDirs()
  addon.setAddonState(Restored)
  if addon.state == Failed:
    return none(Addon)
  removeFile(backups[1])
  return some(addon)
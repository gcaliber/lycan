import print

import std/colors
import std/asyncdispatch
import std/httpclient
import std/json
import std/options
import std/os
import std/re
import std/strformat
import std/strutils
import std/terminal

import zip/zipfiles

import config
import types
import term

proc `==`*(a, b: Addon): bool {.inline.} =
  a.project == b.project

proc newAddon*(project: string, kind: AddonKind, 
              name: string = "", version: string = "", dirs: seq[string] = @[], branch: Option[string] = none(string)): Addon =
  var a = new(Addon)
  a.project = project
  a.name = name
  a.kind = kind
  a.version = version
  a.dirs = dirs
  a.branch = branch
  result = a


proc prettyVersion(addon: Addon): string =
  if addon.version.isEmptyOrWhitespace: 
    return ""
  case addon.kind
  of GithubRepo:
    return addon.version[0 ..< 7]
  else:
    return addon.version

proc prettyOldVersion(addon: Addon): string =
  if addon.oldVersion.isEmptyOrWhitespace: 
    return ""
  case addon.kind
  of GithubRepo:
    return addon.oldVersion[0 ..< 7]
  else:
    return addon.oldVersion

const DARK_GREY: Color = Color(0x20_20_20)
const LIGHT_GREY: Color = Color(0x34_34_34)

proc stateMessage(addon: Addon) = 
  let 
    t = configData.term
    indent = 2
    name = if not addon.name.isEmptyOrWhitespace: addon.name else: $addon.kind & ':' & addon.project
    even = addon.line mod 2 == 0
    arrow = if addon.old_version.isEmptyOrWhitespace: "" else: " > "
    colors = if even: (fgDefault, DARK_GREY) else: (fgDefault, LIGHT_GREY)
    style = if not t.trueColor: (if even: styleBright else: styleReverse) else: styleBright
  case addon.state
  of Checking, Parsing:
    t.write(indent, addon.line, true, colors, style,
      fgCyan, &"{$addon.state:<12}", fgDefault, &"{name:<32}",
      fgYellow, &"{addon.prettyOldVersion()}", resetStyle)
  of Downloading, Installing:
    t.write(indent, addon.line, true, colors, style,
      fgCyan, &"{$addon.state:<12}", fgDefault, &"{name:<32}",
      fgYellow, &"{addon.prettyOldVersion()}", fgDefault, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Finished:
    t.write(indent, addon.line, true, colors, style,
      fgGreen, &"{$addon.state:<12}", fgDefault, &"{name:<32}",
      fgYellow, &"{addon.prettyOldVersion()}", fgDefault, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of AlreadyUpdated:
      t.write(indent, addon.line, true, colors, style,
      fgGreen, &"{$addon.state:<12}", fgDefault, &"{name:<32}",
      fgGreen, &"{addon.prettyVersion()}", resetStyle)
  of Removing, Removed:
      t.write(indent, addon.line, true, colors, style,
      fgYellow, &"{$addon.state:<12}", fgDefault, &"{name:<32}", resetStyle)
  of Failed:
    t.write(indent, addon.line, true, colors, style,
      fgRed, &"{$addon.state:<12}", fgDefault, &"{name:<32}",
      fgYellow, &"{addon.prettyOldVersion()}", fgDefault, &"{arrow}", fgGreen, &"{addon.prettyVersion()}", resetStyle)

proc setAddonState(addon: Addon, state: AddonState, sendMessage: bool = true) =
  if addon.state != Failed:
    addon.state = state
  if sendMessage:
    addon.stateMessage()

proc setName(addon: Addon, json: JsonNode) =
  case addon.kind
  of Github, GithubRepo, Gitlab:
    addon.name = addon.project.split('/')[^1]
  of TukuiMain, TukuiAddon:
    addon.name = json["name"].getStr()
  of Wowint:
    addon.name = json[0]["UIName"].getStr()

proc setVersion(addon: Addon, json: JsonNode) =
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

proc setDownloadUrl(addon: Addon, json: JsonNode) =
  case addon.kind
  of Github:
    let assets = json["assets"]
    if len(assets) != 0:
      for asset in assets:
        if asset["content_type"].getStr() == "application/json":
          continue
        let lc = asset["name"].getStr().toLower()
        if not (lc.contains("bcc") or lc.contains("tbc") or lc.contains("wotlk") or lc.contains("wrath") or lc.contains("classic")):
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
  let client = newAsyncHttpClient()
  return await client.get(url)


proc download(addon: Addon) {.async.} =
  let client = newAsyncHttpClient()
  let futureResponse = client.get(addon.downloadUrl)
  yield futureResponse
  if futureResponse.failed:
    addon.setAddonState(Failed)
    return
  let response = futureResponse.read()
  var downloadName: string
  try:
    downloadName = response.headers["content-disposition"].split('=')[1].strip(chars = {'\'', '"'})
  except KeyError:
    downloadName = addon.downloadUrl.split('/')[^1]
  addon.filename = joinPath(configData.tempDir, downloadName)
  let file = open(addon.filename, fmWrite)
  let futureBody = response.body
  yield futureBody
  if futureBody.failed:
    addon.setAddonState(Failed)
    return
  io.write(file, futureBody.read())
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

proc getSubdirs(path: string): seq[string] =
  var subdirs: seq[string]
  for kind, dir in walkDir(path):
    if kind == pcDir:
      subdirs.add(dir)
  return subdirs

proc getAddonDirs(addon: Addon): seq[string] =
  var current = addon.extractDir
  var firstPass = true
  while true:
    let toc = processTocs(current)
    if not toc:
      let subdirs = getSubdirs(current)
      current = subdirs[0]
    else:
      if firstPass:
        return @[current]
      else:
        return getSubdirs(parentDir(current))
    firstPass = false

proc removeFiles(addon: Addon) =
  for dir in addon.dirs:
    removeDir(dir)

proc setIdAndCleanupInstalled(addon: Addon) =
  for a in configData.addons:
    if a == addon:
      addon.id = a.id
      a.removeFiles()
      break

proc moveDirs(addon: Addon) =
  let source = addon.getAddonDirs()
  addon.setIdAndCleanupInstalled()
  for dir in source:
    let name = lastPathPart(dir)
    addon.dirs.add(name)
    let destination = joinPath(configData.installDir, name)
    moveDir(dir, destination)

proc unzip(addon: Addon) =
  var z: ZipArchive
  if not z.open(addon.filename):
    addon.setAddonState(Failed)
    return
  let (dir, name, _) = splitFile(addon.filename)
  addon.extractDir = joinPath(dir, name)
  z.extractAll(addon.extractDir)

proc getLatestJson(addon: Addon): Future[JsonNode] {.async.} =
  if addon.kind == TukuiAddon:
    if configData.tukuiCache.isNil:
      let response = await addon.getLatest()
      let body = await response.body
      configData.tukuiCache = parseJson(body)
    for node in configData.tukuiCache:
      if node["id"].getStr().strip(chars = {'"'}) == addon.project:
        return node
    addon.setAddonState(Failed)
    return new(JsonNode)
  else:
    let response = await addon.getLatest()
    let body = await response.body
    return parseJson(body)

proc install*(addon: Addon): Future[Option[Addon]] {.async.} =
  addon.setAddonState(Checking)
  let json = await addon.getLatestJson()
  addon.setAddonState(Parsing)
  addon.setVersion(json)
  if addon.version != addon.oldVersion:
    addon.setDownloadUrl(json)
    addon.setName(json)
    addon.setAddonState(Downloading)
    await addon.download()
    addon.setAddonState(Installing)
    addon.unzip()
    addon.moveDirs()
    addon.setAddonState(Finished)
    if addon.state == Failed:
      return none(Addon)
    return some(addon)
  else:
    addon.setAddonState(AlreadyUpdated)
    return none(Addon)

proc uninstall*(addon: Addon): Addon =
  addon.setAddonState(Removing)
  addon.removeFiles()
  addon.setAddonState(Removed)
  return addon

proc toJsonHook*(a: Addon): JsonNode =
  result = newJObject()
  result["project"] = %a.project
  if a.branch.isSome():
    result["branch"] = %a.branch.get()
  result["name"] = %a.name
  result["kind"] = %a.kind
  result["version"] = %a.version
  result["id"] = %a.id
  result["dirs"] = %a.dirs
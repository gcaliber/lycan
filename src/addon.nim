import print

import std/asyncdispatch
import std/httpclient
import std/options
import std/os
import std/re
import std/strformat
import std/strutils
import std/json
import std/jsonutils

import zip/zipfiles

import config
import types

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

proc setName(addon: Addon, json: JsonNode) =
  case addon.kind
  of Github, GithubRepo, Gitlab:
    addon.name = addon.project.split('/')[^1]
  of TukuiMain, TukuiAddon:
    addon.name = json["name"].getStr()
  of Wowint:
    addon.name = json[0]["UIName"].getStr()


proc setVersion(addon: Addon, json: JsonNode): bool =
  let oldVersion = addon.version
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
  return addon.version != oldVersion

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
  let response = await client.get(addon.downloadUrl)
  var downloadName: string
  try:
    downloadName = response.headers["content-disposition"].split('=')[1].strip(chars = {'\'', '"'})
  except KeyError:
    downloadName = addon.downloadUrl.split('/')[^1]
  addon.filename = joinPath(configData.tempDir, downloadName)
  let file = open(addon.filename, fmWrite)
  write(file, await response.body)
  close(file)


proc processTocs(path: string): bool =
  for kind, file in walkDir(path):
    if kind == pcFile:
      var (dir, name, ext) = splitFile(file)
      if ext == ".toc":
        if name != lastPathPart(dir):
          let p = re("(.+?)(?:$|[-_](?i:mainline|wrath|tbc|vanilla|wotlkc?|bcc|classic))", flags = {reIgnoreCase})
          var m: array[2, string]
          let found = find(cstring(name), p, m, 0, len(name))
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

proc cleanupInstalled(addon: Addon): int16 =
  for a in configData.addons:
    if a == addon:
      a.removeFiles()
      return a.id
  return 0

proc moveDirs(addon: Addon) =
  let source = addon.getAddonDirs()
  addon.id = addon.cleanupInstalled()
  for dir in source:
    let name = lastPathPart(dir)
    addon.dirs.add(name)
    let destination = joinPath(configData.installDir, name)
    moveDir(dir, destination)


proc unzip(addon: Addon) =
  var z: ZipArchive
  if not z.open(addon.filename):
    echo &"Extracting {addon.filename} failed"
    return
  let (dir, name, _) = splitFile(addon.filename)
  addon.extractDir = joinPath(dir, name)
  z.extractAll(addon.extractDir)


proc fromCache(addon: Addon): Future[JsonNode] {.async.} =
  if configData.tukuiCache.isNil:
    let response = await addon.getLatest()
    let body = await response.body
    configData.tukuiCache = parseJson(body)
  var json = configData.tukuiCache
  for node in json:
    if node["id"].getStr().strip(chars = {'"'}) == addon.project:
      json = node
  return json

proc install*(addon: Addon): Future[Option[Addon]] {.async.} =
  echo "Checking: ", addon.project
  var json: JsonNode
  if addon.kind == TukuiAddon:
    json = await addon.fromCache()
  else:
    let response = await addon.getLatest()
    let body = await response.body
    json = parseJson(body)
  echo "Parsing: ", addon.project
  let updateNeeded = addon.setVersion(json)
  if updateNeeded:
    addon.setDownloadUrl(json)
    addon.setName(json)
    echo "Downloading: ", addon.name
    await addon.download()
    echo "Finishing: ", addon.name
    addon.unzip()
    addon.moveDirs()
    echo "Finished: ", addon.name
    return some(addon)
  else:
    echo "Skipped: ", addon.project
    return none(Addon)
  
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

proc fromJsonHook*(a: var Addon, j: JsonNode) =
  var
    b: Option[string]
    d: seq[string]
    k: AddonKind
  
  try:
    b = some($j["branch"])
  except:
    b = none(string)

  d.fromJson(j["dirs"])
  k.fromJson(j["kind"])

  a = newAddon(
    $j["project"],
    k,
    branch = b,
    version = $j["version"],
    name = $j["name"],
    dirs = d
  )
  

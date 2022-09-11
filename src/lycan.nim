import std/[asyncdispatch, asyncfile]
import myhttpclient
# This is a modified std/httpclient that only changes the reportProgress time from
# 1 second to 50 milliseconds. When the files are small, like with wow addons, 1 second
# just isn't enough time to display any useful information.
import std/[json, jsonutils]
import std/os
import std/parseopt
import std/re
import std/[strformat, strutils]

import zip/zipfiles
when not defined(release):
  import print

import illwill
import progressbar

type
  AddonSource = enum
    GITHUB, GITHUB_REPO, GITLAB, TUKUI, WOWINT

  Addon = object
    id: int16
    project: string
    branch: string
    name: string
    source: AddonSource
    version: string
    directories: seq[string]
  
  UpdateData = object
    addon: Addon
    needed: bool
    url: string
    version: string
    name: string
    filename: string
    pb: ProgressBar

  Config = object
    flavor: string
    tempDir: string
    addonDir: string
    installedAddonsJson: string
    addons: seq[Addon]
    tukuiCache: string
    updates: seq[UpdateData]

proc loadInstalledAddons(filename: string): seq[Addon] =
  if not fileExists(filename):
    return @[]
  let addonsJson = parseJson(readFile(filename))
  var addons: seq[Addon]
  for addon in addonsJson:
    addons.add(addon.to(Addon))
  return addons

proc exitProc() {.noconv.} =
  illwillDeinit()
  showCursor()
  quit(0)

let configJson = parseJson(readFile("test/lycan.json"))
let flavor = configJson["flavor"].getStr()
let installedFile = configJson[flavor]["installedAddons"].getStr()
var config = Config(
  flavor: flavor,
  tempDir: getTempDir(),
  addonDir: configJson[flavor]["addonDir"].getStr(),
  installedAddonsJson: installedFile,
  addons: loadInstalledAddons(installedFile)
)

proc newUpdateData(addon: Addon, needed: bool = false, url: string = "", version: string = "", name: string = "", filename: string = "", pb: ProgressBar = nil): UpdateData =
  result = UpdateData(
    addon: addon,
    needed: false,
    url: url,
    version: version,
    name: name,
    filename: filename,
    pb: pb
  )


proc getLatestUrl(project: string, source: AddonSource, branch: string = "master"): string =
  case source
    of GITHUB:
      return fmt"https://api.github.com/repos/{project}/releases/latest"
    of GITLAB:
      let urlEncodedProject = project.replace("/", "%2F")
      return fmt"https://gitlab.com/api/v4/projects/{urlEncodedProject}/releases"
    of TUKUI:
      if project == "elvui" or project == "tukui":
        return fmt"https://www.tukui.org/api.php?ui={project}"
      else:
        return "https://www.tukui.org/api.php?addons"
    of WOWINT:
      return fmt"https://api.mmoui.com/v3/game/WOW/filedetails/{project}.json"
    of GITHUB_REPO:
      return fmt"https://api.github.com/repos/{project}/commits/{branch}"


proc getLatestJson(addon: Addon): Future[string] {.async.} =
  let url = getLatestUrl(addon.project, addon.source)
  if addon.source == TUKUI and addon.project != "elvui" and addon.project != "tukui":
    if config.tukuiCache == "":
      let client = newAsyncHttpClient()
      config.tukuiCache = await client.getContent(url)
    return config.tukuiCache
  else:
    let client = newAsyncHttpClient()
    return await client.getContent(url)


illwillInit(fullscreen=false)
setControlCHook(exitProc)
hideCursor()
var tb = newTerminalBuffer(terminalWidth(), terminalHeight())



proc downloadAsset(update: UpdateData): Future[string] {.async.} =
  let client = newAsyncHttpClient()
  client.onProgressChanged = proc(total, progress, speed: BiggestInt) {.async.} =
    var update = update
    update.pb.set(toInt int(total) / int(progress) * 100.00)
  
  let future = client.get(update.url)
  yield future
  if future.failed:
    return "EMPTY"
  else:
    let resp = future.read()
    var downloadName: string
    try:
      downloadName = resp.headers["content-disposition"].split('=')[1].strip(chars = {'\'', '"'})
    except KeyError:
      downloadName = update.url.split('/')[^1]
    let filename = joinPath(config.tempDir, downloadName)
    let file = openAsync(filename, fmWrite)
    yield writeFromStream(file, resp.bodyStream)
    close(file)
    return filename


proc unzip(filename: string, extractDir: string) =
  var z: ZipArchive
  if not z.open(filename):
    echo fmt"Extracting {filename} failed"
    return
  z.extractAll(extractDir)


proc writeInstalledAddons() =
  let addonsJson = config.addons.toJson(opt = ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef))
  let file = open(config.installedAddonsJson, fmWrite)
  write(file, addonsJson)
  close(file)


proc newAddon(project: string, source: AddonSource, name: string = "", version: string = "", 
              dirs: seq[string] = @[], branch: string = "", removeDupes: bool = false): Addon =
  result = Addon(project: project, name: name, source: source, version: version, directories: dirs, id: -1, branch: branch)

  for addon in config.addons:
    if addon.project == project:
      result.id = addon.id
      if removeDupes:
        config.addons.delete(config.addons.find(addon))
      return result
  
  var ids: set[int16]
  if result.id == -1:
    for addon in config.addons:
      incl(ids, addon.id)
  
  var id: int16 = 1
  while result.id == -1:
    if id in ids:
      id += 1
    else:
      result.id = id


proc processTocs(path: string): bool =
  for kind, file in walkDir(path):
    if kind == pcFile:
      let (dir, name, extension) = splitFile(file)
      if extension == ".toc":
        if name != lastPathPart(dir):
          let p = re("(.+)[-_](mainline|wrath|tbc|vanilla|wotlkc?|bcc|classic)", flags = {reIgnoreCase})
          var m: array[2, string]
          let found = find(cstring(name), p, m, 0, len(name))
          if found != -1:
            moveDir(dir, joinPath(parentDir(dir), m[0]))
          else:
            moveDir(dir, joinPath(parentDir(dir), name))
        return true
  return false

proc getSubdirs(path: string): seq[string] =
  var subdirs: seq[string]
  for kind, dir in walkDir(path):
    if kind == pcDir:
      subdirs.add(dir)
  return subdirs

#TODO: Robustness: This doesn't handle addon authors packaging separate folders for retail/classic/wrath into a single release
proc getAddonDirs(path: string): seq[string] =
  var current = path
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


proc moveAddonDirs(extractDir: string): seq[string] =
  let sourceDirs = getAddonDirs(extractDir)
  var addonDirs: seq[string]
  for dir in sourceDirs:
    let name = lastPathPart(dir)
    let destination = joinPath(config.addonDir, name)
    moveDir(dir, destination)
    addonDirs.add(name)
  return addonDirs

# TODO: Robustness: Verify this is actually a valid source. Currently we just fail
# somewhere else if it is not and so don't report a very good error message.
proc parseAddonArg(arg: string): Addon =
  var urlmatch: array[2, string]
  let pattern = re"^(?:https?:\/\/)?(?:www\.)?(.*)\.(?:com|org)\/(.*[^\/\n])"
  var found = find(arg, pattern, urlmatch, 0, len(arg))
  if found == -1:
    echo "No url found"
    quit()
  case urlmatch[0].toLower()
    of "github":
      # https://github.com/Tercioo/Plater-Nameplates/tree/master

      # https://api.github.com/repos/Tercioo/Plater-Nameplates/releases/latest
      let p = re"^(.+\/.+)\/tree\/(.+)"
      var m: array[2, string]
      found = find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      if found == -1:
        return newAddon(urlmatch[1], GITHUB)
      else:
        return newAddon(m[0], GITHUB_REPO, branch = m[1])
    of "gitlab":
      # https://gitlab.com/siebens/legacy/autoactioncam
      # https://gitlab.com/api/v4/projects/siebens%2Flegacy%2Fautoactioncam/releases
      return newAddon(urlmatch[1], GITLAB)
    of "tukui":
      # https://www.tukui.org/download.php?ui=tukui
      # https://www.tukui.org/addons.php?id=209
      let p = re"^(?:download|addons)\.php\?(?:ui|id)=(.*)"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      return newAddon(m[0], TUKUI)
    of "wowinterface":
      # https://api.mmoui.com/v3/game/WOW/filedetails/24608.json
      # https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html
      let p = re"^downloads\/info(\d*)-"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      return newAddon(m[0], WOWINT)


proc removeAddon(n: int16) = 
  for addon in config.addons:
    if addon.id == n:
      for dir in addon.directories:
        removeDir(joinPath(config.addonDir, dir))
      config.addons.delete(config.addons.find(addon))
      writeInstalledAddons()
      return
  echo &"Error: No installed addon with id \"{n}\""

proc removeAddon(project: string) = 
  for addon in config.addons:
    if addon.project == project:
      removeAddon(addon.id)
      return
  echo &"Error: \"{project}\" not found"


proc getVersion(json: JsonNode, source: AddonSource): string =
  case source
  of GITHUB:
    let v = json["tag_name"].getStr()
    return if v != "": v else: json["name"].getStr()
  of GITLAB:
    let v = json[0]["tag_name"].getStr()
    return if v != "": v else: json[0]["name"].getStr()
  of TUKUI:
    return json["version"].getStr()
  of WOWINT:
    return json[0]["UIVersion"].getStr()
  of GITHUB_REPO:
    return json["sha"].getStr()


proc getPrettyName(json: JsonNode, project: string, source: AddonSource): string =
  case source
  of GITHUB, GITHUB_REPO, GITLAB:
    return project.split('/')[^1]
  of TUKUI:
    return json["name"].getStr()
  of WOWINT:
    return json[0]["UIName"].getStr()
  
  
proc getDownloadUrl(json: JsonNode, project: string, source: AddonSource, branch: string = "master"): string =
  case source
  of GITHUB:
    let assets = json["assets"]
    if len(assets) != 0:
      for asset in assets:
        if asset["content_type"].getStr() == "application/json":
          continue
        let lc = asset["name"].getStr().toLower()
        if not (lc.contains("bcc") or lc.contains("tbc") or lc.contains("wotlk") or lc.contains("wrath") or lc.contains("classic")):
          return asset["browser_download_url"].getStr()
    else:
      return json["zipball_url"].getStr()
  of GITLAB:
    for source in json[0]["assets"]["sources"]:
      if source["format"].getStr() == "zip":
        return source["url"].getStr()
  of TUKUI:
    return json["url"].getStr()
  of WOWINT:
    return json[0]["UIDownload"].getStr()
  of GITHUB_REPO:
    return fmt"https://www.github.com/{project}/archive/refs/heads/{branch}.zip"


proc getUpdateData(addon: Addon): Future[UpdateData] {.async.} =
  let future = getLatestJson(addon)
  yield future
  if future.failed:
    return newUpdateData(addon)
  else:
    var json = parseJson(future.read())
    if addon.source == TUKUI and addon.project != "tukui" and addon.project != "elvui":
      for item in json:
        if item["id"].getStr() == addon.project:
          json = item
    let version = getVersion(json, addon.source)
    return newUpdateData(
      addon,
      needed = version != addon.version,
      url = getDownloadUrl(json, addon.project, addon.source),
      version = version,
      name = getPrettyName(json, addon.project, addon.source),
      pb = newProgressBar(tb, 0, len(config.updates))
    )
    
proc getUpdatedFiles(addons: seq[Addon]) {.async.} =
  var futureUpdates: seq[Future[UpdateData]]
  for addon in addons:
    futureUpdates.add(getUpdateData(addon))

  for future in futureUpdates:
    yield future
    var update = future.read()
    config.updates.add(update)
    if update.needed:
      let filename = await downloadAsset(update)
      # yield filename
      update.filename = filename
      print update.filename

proc installAddons(addons: seq[Addon]) =
  waitFor getUpdatedFiles(addons)
  for data in config.updates:
    let (dir, name, _) = splitFile(data.filename)
    let extractDir = joinPath(dir, name)
    unzip(data.filename, extractDir)
    let addonDirs = moveAddonDirs(extractDir)
    config.addons.add(newAddon(
      data.addon.project, 
      data.addon.source, 
      branch = data.addon.branch, 
      name = data.name, 
      version = data.version, 
      dirs = addonDirs,
      removeDupes = true
    ))
  writeInstalledAddons()
  

proc displayHelp() =
  echo "  -u, --update                 Update installed addons"
  echo "  -i, --install <arg>          Install an addon where <arg> is the url"
  echo "  -a, --add <arg>              Same as --install"
  echo "  -r, --remove <arg>           Remove an installed addon where <arg> is the id# or project"
  echo "  -l, --list                   List installed addons"
  echo "      --clone <branch>         Install from github as a clone of <branch> instead of a release, defaults to master"
  echo "      --pin <addon id#>        Pin an addon at the current version, do not update"
  echo "      --unpin <addon id#>      Unpin an addon, resume updates"
  echo "      --restore <addon id#>    Restore addon to last backed up version and pin it"
  quit()

var opt = initOptParser(commandLineParams(), 
                        shortNoVal = {'h', 'l', 'u', 'i', 'a'}, 
                        longNoVal = @["help", "list", "update"])

type
  Command = enum
    install, remove, update, list, pin, unpin, restore

var command: Command = update
var arg: string
for kind, key, val in opt.getopt():
  case kind
  of cmdShortOption, cmdLongOption:
    # echo "key ", key
    # echo "val ", "'", val, "'"
    if val == "":
      case key:
        of "h", "help": displayHelp()
        of "a", "i": command = install
        of "r": command = remove
        of "l", "list": command = list
        else: displayHelp()
    else:
      arg = val
      case key:
        of "add", "install": command = install
        of "remove": command = remove
        of "pin": command = pin
        of "unpin": command = unpin
        of "restore": command = restore
        else: displayHelp()
  of cmdArgument:
    # echo "cmd ", "'", key, "'"
    arg = key
  else: displayHelp()

case command
  of install:
    let addon = parseAddonArg(arg)
    installAddons(@[addon])
  of remove:
    if len(arg) > 4:
      removeAddon(arg)
    else:
      removeAddon(int16(parseInt(arg)))
  of update:
    installAddons(config.addons)
  of list: echo "TODO list"
  of pin: echo "TODO pin"
  of unpin: echo "TODO unpin"
  of restore: echo "TODO restore"

# default wow folder on windows C:\Program Files (x86)\World of Warcraft\
# addons folder is <WoW>\_retail_\Interface\AddOns
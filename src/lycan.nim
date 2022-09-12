import std/[asyncdispatch, asyncfile]
import myhttpclient
# This is a modified std/httpclient that only changes the reportProgress time from
# 1 second to 100 milliseconds. When the files are small, like with wow addons, 1 second
# just isn't enough time to display any useful information.
import std/[json, jsonutils]
import std/os
import std/parseopt
import std/re
import std/[strformat, strutils]

import zip/zipfiles
when not defined(release):
  import print

when defined(progress):
  import illwill
  import progressbar
else:
  type ProgressBar = ref object

type
  Action = enum
    install, remove, list, pin, unpin, restore, none
  AddonSource = enum
    GITHUB, GITHUB_REPO, GITLAB, TUKUI, WOWINT

  Addon = object
    id: int16
    project: string
    branch: string
    name: string
    source: AddonSource
    version: string
    dirs: seq[string]
  
  UpdateData = object
    addon: Addon
    action: Action
    url: string
    filename: string
    id: int
    pb: ProgressBar

  Config = object
    flavor: string
    tempDir: string
    addonDir: string
    datafile: string
    tukuiCache: JsonNode
    addons: seq[Addon]
    updateCount: int

when defined(progress):
  import illwill
  import progressbar
  
  proc exitProc() {.noconv.} =
    illwillDeinit()
    showCursor()
    quit(0)

  illwillInit(fullscreen=false)
  setControlCHook(exitProc)
  hideCursor()
  var tb = newTerminalBuffer(terminalWidth(), terminalHeight())

  proc report(tb: var TerminalBuffer, msg: string) =
    tb.write(5, 20, msg)
    tb.display()
else:
  proc report(msg: string) =
      echo &"INFO: {msg}"


proc parseInstalledAddons(filename: string): seq[Addon] =
  if not fileExists(filename):
    return @[]
  let addonsJson = parseJson(readFile(filename))
  var addons: seq[Addon]
  for addon in addonsJson:
    addons.add(addon.to(Addon))
  return addons



let configJson = parseJson(readFile("test/lycan.json"))
let flavor = configJson["flavor"].getStr()
let datafile = configJson[flavor]["installedAddons"].getStr()
var config = Config(
  flavor: flavor,
  tempDir: getTempDir(),
  addonDir: configJson[flavor]["addonDir"].getStr(),
  datafile: datafile,
  addons: parseInstalledAddons(datafile),
  updateCount: 0
)

proc newUpdateData(addon: Addon, action: Action, url: string = "", filename: string = "", pb: ProgressBar = nil): UpdateData =
  result = UpdateData(
    addon: addon,
    action: action,
    url: url,
    filename: filename,
    id: config.updateCount,
    pb: pb
  )
  config.updateCount += 1

proc newAddon(project: string, source: AddonSource, name: string = "", version: string = "", 
              dirs: seq[string] = @[], branch: string = ""): Addon =
  result = Addon(
    project: project,
    name: name, 
    source: source, 
    version: version, 
    dirs: dirs, 
    branch: branch
  )

  for addon in config.addons:
    if addon.project == project:
      result.id = addon.id
  
  var ids: set[int16]
  if result.id == 0:
    for addon in config.addons:
      incl(ids, addon.id)
  
  var id: int16 = 1
  while result.id == 0:
    if id in ids: id += 1
    else: result.id = id


proc writeInstalledAddons() =
  let addonsJson = config.addons.toJson(opt = ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef))
  let file = open(config.datafile, fmWrite)
  write(file, addonsJson)
  close(file)
  

# TODO: Robustness: Verify this is actually a valid source. Currently we just fail
# somewhere else if it is not and so don't report a very good error message.
proc parseAddon(arg: string): Addon =
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
      for dir in addon.dirs:
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

var action: Action = install
var args: seq[string]
for kind, key, val in opt.getopt():
  case kind
  of cmdShortOption, cmdLongOption:
    # echo "key ", key
    # echo "val ", "'", val, "'"
    if val == "":
      case key:
        of "h", "help": displayHelp()
        of "a", "i": action = install
        of "r": action = remove
        of "l", "list": action = list
        else: displayHelp()
    else:
      args.add(val)
      case key:
        of "add", "install": action = install
        of "remove": action = remove
        of "pin": action = pin
        of "unpin": action = unpin
        of "restore": action = restore
        else: displayHelp()
  of cmdArgument:
    # echo "cmd ", "'", key, "'"
    args.add(key)
  else: displayHelp()


proc setName(addon: var Addon, json: JsonNode) =
  case addon.source
  of GITHUB, GITHUB_REPO, GITLAB:
    addon.name = addon.project.split('/')[^1]
  of TUKUI:
    addon.name = json["name"].getStr()
  of WOWINT:
    addon.name = json[0]["UIName"].getStr()

proc setVersion(addon: var Addon, json: JsonNode) =
  case addon.source
  of GITHUB:
    let v = json["tag_name"].getStr()
    addon.version = if v != "": v else: json["name"].getStr()
  of GITLAB:
    let v = json[0]["tag_name"].getStr()
    addon.version = if v != "": v else: json[0]["name"].getStr()
  of TUKUI:
    addon.version = json["version"].getStr()
  of WOWINT:
    addon.version = json[0]["UIVersion"].getStr()
  of GITHUB_REPO:
    addon.version = json["sha"].getStr()



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

proc removeDirs(addon: Addon) =
  for dir in addon.dirs:
    removeDir(dir)

proc deleteInstalled(addon: Addon) =
  for a in config.addons:
    if a.project == addon.project:
      a.removeDirs()
      config.addons.delete(config.addons.find(a))

proc install(update: var UpdateData) =
  var z: ZipArchive
  if not z.open(update.filename):
    report(&"Extracting {update.filename} failed")
    return
  let (dir, name, _) = splitFile(update.filename)
  let extractDir = joinPath(dir, name)
  z.extractAll(extractDir)
  update.addon.deleteInstalled()
  update.addon.dirs = moveAddonDirs(extractDir)


proc download(update: var UpdateData) {.async.} =
  let client = newAsyncHttpClient()
  when defined(progress):
    client.onProgressChanged = proc(total, progress, speed: BiggestInt) {.async.} =
      var update = update
      update.pb.set(toInt(int(total) / int(progress) * 100.00))
  
  let future = client.get(update.url)
  yield future
  if future.failed:
    report("download future failed")
  else:
    let resp = future.read()
    var downloadName: string
    try:
      downloadName = resp.headers["content-disposition"].split('=')[1].strip(chars = {'\'', '"'})
    except KeyError:
      downloadName = update.url.split('/')[^1]
    update.filename = joinPath(config.tempDir, downloadName)
    let file = openAsync(update.filename, fmWrite)
    let future = writeFromStream(file, resp.bodyStream)
    yield future
    if future.failed:
      report("write file future failed")
    else:
      close(file)


proc setDownloadUrl(update: var UpdateData, json: JsonNode) =
  case update.addon.source
  of GITHUB:
    let assets = json["assets"]
    if len(assets) != 0:
      for asset in assets:
        if asset["content_type"].getStr() == "application/json":
          continue
        let lc = asset["name"].getStr().toLower()
        if not (lc.contains("bcc") or lc.contains("tbc") or lc.contains("wotlk") or lc.contains("wrath") or lc.contains("classic")):
          update.url = asset["browser_download_url"].getStr()
    else:
      update.url = json["zipball_url"].getStr()
  of GITLAB:
    for source in json[0]["assets"]["sources"]:
      if source["format"].getStr() == "zip":
        update.url = source["url"].getStr()
  of TUKUI:
    update.url = json["url"].getStr()
  of WOWINT:
    update.url = json[0]["UIDownload"].getStr()
  of GITHUB_REPO:
    update.url = &"https://www.github.com/{update.addon.project}/archive/refs/heads/{update.addon.branch}.zip"


proc getLatestUrl(addon: Addon): string =
  case addon.source
    of GITHUB:
      return &"https://api.github.com/repos/{addon.project}/releases/latest"
    of GITLAB:
      let urlEncodedProject = addon.project.replace("/", "%2F")
      return &"https://gitlab.com/api/v4/projects/{urlEncodedProject}/releases"
    of TUKUI:
      if addon.project == "elvui" or addon.project == "tukui":
        return &"https://www.tukui.org/api.php?ui={addon.project}"
      else:
        return "https://www.tukui.org/api.php?addons"
    of WOWINT:
      return &"https://api.mmoui.com/v3/game/WOW/filedetails/{addon.project}.json"
    of GITHUB_REPO:
      return &"https://api.github.com/repos/{addon.project}/commits/{addon.branch}"

proc getUpdateInfo(update: var UpdateData) {.async.} =
  let addon = update.addon
  let url = addon.getLatestUrl()
  var json: JsonNode
  if addon.source == TUKUI and addon.project != "elvui" and addon.project != "tukui":
    if config.tukuiCache.isNil:
      let client = newAsyncHttpClient()
      config.tukuiCache = parseJson(await client.getContent(url))
    for item in config.tukuiCache:
      if item["id"].getStr() == addon.project:
        json = item
  else:
    let client = newAsyncHttpClient()
    json = parseJson(await client.getContent(url))
  
  let currentVersion = update.addon.version
  update.addon.setVersion(json)
  if update.addon.version != currentVersion:
    update.action = install
    update.setDownloadUrl(json)
    update.addon.setName(json)
  else:
    update.action = none


proc process(updates: var seq[UpdateData]) {.async.} =
  for update in updates.mitems:
    case update.action
    of install:
      await update.getUpdateInfo()
      if update.action == install:
        await update.download()
        update.install()
    of remove:echo "TODO list"
    of list: echo "TODO list"
    of pin: echo "TODO pin"
    of unpin: echo "TODO unpin"
    of restore: echo "TODO restore"
    of none: discard

var updates: seq[UpdateData]
for arg in args:
  var addon = parseAddon(arg)
  updates.add(newUpdateData(addon, action))

waitFor updates.process()

when defined(progress):
  exitProc()

# default wow folder on windows C:\Program Files (x86)\World of Warcraft\
# addons folder is <WoW>\_retail_\Interface\AddOns
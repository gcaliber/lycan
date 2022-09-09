import std/[asyncdispatch, asyncfile]
import std/httpclient
import std/[json, jsonutils]
import std/os
import std/parseopt
import std/re
import std/[strformat, strutils]

import zip/zipfiles
when not defined(release):
  import print

type
  AddonSource = enum
    GITHUB, GITHUB_REPO, GITLAB, TUKUI, WOWINT

  Addon = object
    id: int16
    project: string
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

let configJson = parseJson(readFile("test/lycan.json"))
let flavor = configJson["flavor"].getStr()
let installedFile = configJson[flavor]["installedAddons"].getStr()
var config = Config(flavor: flavor,
                    tempDir: getTempDir(),
                    addonDir: configJson[flavor]["addonDir"].getStr(),
                    installedAddonsJson: installedFile,
                    addons: loadInstalledAddons(installedFile),
                    tukuiCache: "")


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


proc downloadAsset(url: string): Future[string] {.async.} =
  let client = newAsyncHttpClient()
  let future = client.get(url)
  yield future
  if future.failed:
    return ""
  else:
    let resp = future.read()
    let filename = joinPath(config.tempDir, resp.headers["content-disposition"].split('=')[1].strip(chars = {'\'', '"'}))
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


proc getAddonWithId(project: string, name: string, source: AddonSource, version: string, dirs: seq[string]): Addon =
  var newAddon = Addon(project: project, name: name, source: source, version: version, directories: dirs, id: -1)

  for addon in config.addons:
    if addon.project == project:
      newAddon.id = addon.id
      config.addons.delete(config.addons.find(addon))
      return newAddon
  
  var ids: set[int16]
  if newAddon.id == -1:
    for addon in config.addons:
      incl(ids, addon.id)
  
  var id: int16 = 1
  while newAddon.id == -1:
    if id in ids:
      id += 1
    else:
      newAddon.id = id
  return newAddon

# TODO: Robustness, this can fail in some situations although those shouldn't really ever happen
proc getAddonDirs(root: string): seq[string] =
  var addonDirs: seq[string] = @[root]
  var n = 0
  var tocPaths: seq[(string, string)]
  while len(addonDirs) != 0:
    var current = addonDirs[n]
    for kind, path in walkDir(current):
      if kind == pcFile:
        let (dir, name, ext) = splitFile(path)
        if ext == ".toc":
          if name == lastPathPart(dir):
            return addonDirs
          tocPaths.add((dir, name))
    n += 1
    if n >= len(addonDirs):
      n = 0
      addonDirs = @[]
      for kind, path in walkDir(current):
        if kind == pcDir:
          addonDirs.add(path)
  # we did not find a toc file with a matching directory name
  # so we need to rename the directory based on the best toc file found
  # currently this just means excluding ones that contain classic names
  for (dir, name) in tocPaths:
    let lc = name.toLower()
    if not (lc.contains("tbc") or lc.contains("wtolk") or lc.contains("wrath") or lc.contains("bcc") or lc.contains("classic")):
      let parent = parentDir(dir)
      let newPath = joinPath(parent, name)
      moveDir(dir, newPath)
      return @[newPath]


proc moveAddonDirs(extractDir: string): seq[string] =
  let sourceDirs = getAddonDirs(extractDir)
  var addonDirs: seq[string]
  for dir in sourceDirs:
    let name = lastPathPart(dir)
    let destination = joinPath(config.addonDir, name)
    moveDir(dir, destination)
    addonDirs.add(name)
  return addonDirs


proc parseAddonArg(arg: string): (string, AddonSource) =
  var urlmatch: array[2, string]
  let pattern = re"^(?:https?:\/\/)?(?:www\.)?(.*)\.(?:com|org)\/(.*)"
  #instead of discarding we should check for -1 as an error
  discard find(arg, pattern, urlmatch, 0, len(arg))
  case urlmatch[0].toLower()
    of "github":
      # https://github.com/Tercioo/Plater-Nameplates
      # https://api.github.com/repos/Tercioo/Plater-Nameplates/releases/latest
      return (urlmatch[1], GITHUB)
    of "gitlab":
      # https://gitlab.com/siebens/legacy/autoactioncam
      # https://gitlab.com/api/v4/projects/siebens%2Flegacy%2Fautoactioncam/releases
      return (urlmatch[1], GITLAB)
    of "tukui":
      let p = re"^(?:download|addons)\.php\?(?:ui|id)=(.*)"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      return (m[0], TUKUI)
    of "wowinterface":
      # https://api.mmoui.com/v3/game/WOW/filedetails/{project}.json
      # https://api.mmoui.com/v3/game/WOW/filedetails/24608.json
      # https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html
      let p = re"^downloads\/info(\d*)-"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      return (m[0], WOWINT)


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
    return json["sha"].getStr()[0 .. 6]


proc getPrettyName(json: JsonNode, project: string, source: AddonSource): string =
  case source
  of GITHUB, GITHUB_REPO, GITLAB:
    return project
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
    return fmt"https://www.github.com/{project}/archive/refs/heads{branch}.zip"


proc getUpdateData(addon: Addon): Future[UpdateData] {.async.} =
  let future = getLatestJson(addon)
  yield future
  if future.failed:
    return UpdateData(addon: addon, needed: false, url: "", version: "", filename: "")
  else:
    let json = parseJson(future.read())
    let version = getVersion(json, addon.source)
    return UpdateData(addon: addon,
                      needed: version != addon.version,
                      url: getDownloadUrl(json, addon.project, addon.source),
                      version: version,
                      name: getPrettyName(json, addon.project, addon.source),
                      filename: "")


proc getUpdatedFiles(addons: seq[Addon]): Future[seq[UpdateData]] {.async.} =
  var futureUpdates: seq[Future[UpdateData]]
  for addon in addons:
    futureUpdates.add(getUpdateData(addon))

  var updates: seq[UpdateData]
  for future in futureUpdates:
    yield future
    var update = future.read()
    if update.needed:
      let filename = downloadAsset(update.url)
      yield filename
      update.filename = filename.read()
      updates.add(update)

  return updates


proc installAddons(addons: seq[Addon]) =
  let updates = waitFor getUpdatedFiles(addons)
  for data in updates:
    let (dir, name, _) = splitFile(data.filename)
    let extractDir = joinPath(dir, name)
    unzip(data.filename, extractDir)
    let addonDirs = moveAddonDirs(extractDir)

    config.addons.add(getAddonWithId(data.addon.project, data.name, data.addon.source, data.version, addonDirs))
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
    install, clone, remove, update, list, pin, unpin, restore

var command: Command = update
var args: seq[string]
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
      args.add(val)
      case key:
        of "add", "install": command = install
        of "remove": command = remove
        of "pin": command = pin
        of "unpin": command = unpin
        of "restore": command = restore
        of "clone:": command = clone
        else: displayHelp()
  of cmdArgument:
    # echo "cmd ", "'", key, "'"
    args.add(key)
  else: displayHelp()

case command
  of install:
    let (project, source) = parseAddonArg(arg)
    let addon = getAddonWithId(project, "", source, "", @[]) 
    installAddons(@[addon])
  of clone:
    let (project, source) = parseAddonArg(arg)
    let addon = getAddonWithId(project, "", source, "", @[]) 
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
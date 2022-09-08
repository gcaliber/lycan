import std/asyncdispatch
import std/httpclient
import std/json
import std/jsonutils
import std/strformat
import std/strutils

import std/os
import std/parseopt
import std/re

import zip/zipfiles

when not defined(release):
  import print

const
  tukuiAddonUrl = "https://www.tukui.org/api.php?addons"

type
  AddonSource = enum
    GITHUB, GITLAB, TUKUI, WOWINT

  Addon = object
    id: int16
    project: string
    source: AddonSource
    version: string
    directories: seq[string]
  
  UpdateData = object
    needed: bool
    downloadUrl: string
    version: string

  Config = object
    flavor: string
    tempDir: string
    addonDir: string
    installedAddonsJson: string
    addons: seq[Addon]
    tukuiCache: JsonNode
    updates: seq[UpdateData]

proc loadInstalledAddons(filename: string): seq[Addon] =
  let addonsJson = parseJson(readFile(filename))
  var addons: seq[Addon]
  for addon in addonsJson:
    addons.add(addon.to(Addon))
  return addons

let configJson = parseJson(readFile("test/lycan.json"))
let flavor = configJson["flavor"].getStr()
let installedFile = configJson[flavor]["installedAddons"].getStr()
var config* = Config(flavor: flavor,
                    tempDir: getTempDir(),
                    addonDir: configJson[flavor]["addonDir"].getStr(),
                    installedAddonsJson: installedFile,
                    addons: loadInstalledAddons(installedFile),
                    tukuiCache: nil)

proc getLatestUrl(project: string, source: AddonSource): string =
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
    else:
      quit()

proc getLatestJson(url: string): Future[string] {.async.} =
  var client = newAsyncHttpClient()
  return await client.getContent(url)


proc downloadAsset(url: string): Future[string] {.async.} =
  var client = newAsyncHttpClient()
  let response = await client.get(url)
  # echo response.headers["content-disposition"]
  # "content-disposition": ["attachment; filename=AdvancedInterfaceOptions-1.7.2.zip"]
  let filename = joinPath(config.tempDir, response.headers["content-disposition"].split('=')[1])
  # echo filename
  let file = open(filename, fmWrite)
  write(file, waitFor response.body)
  close(file)
  return filename


proc unzip(filename: string, extractDir: string) =
  var z: ZipArchive
  if not z.open(filename):
    echo fmt"Extracting {filename} failed"
    return
  z.extractAll(extractDir)


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
    if not (lc.contains("tbc") or lc.contains("wtolk") or lc.contains("bcc") or lc.contains("classic")):
      let parent = parentDir(dir)
      let newPath = joinPath(parent, name)
      moveDir(dir, newPath)
      return @[newPath]


proc writeInstalledAddons() =
  let addonsJson = config.addons.toJson(opt = ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef))
  let file = open(config.installedAddonsJson, fmWrite)
  write(file, addonsJson)
  close(file)


proc newAddon(project: string, source: AddonSource, version: string, dirs: seq[string]): Addon =
  var newAddon: Addon
  newAddon.project = project
  newAddon.source = source
  newAddon.version = version
  newAddon.directories = dirs
  
  newAddon.id = -1
  for addon in config.addons:
    if addon.project == project:
      newAddon.id = addon.id
      config.addons.delete(config.addons.find(addon))
      break
  
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


proc moveAddonDirs(extractDir: string): seq[string] =
  let sourceDirs = getAddonDirs(extractDir)
  var addonDirs: seq[string]
  for dir in sourceDirs:
    let name = lastPathPart(dir)
    let destinationDir = joinPath(config.addonDir, name)
    moveDir(dir, destinationDir)
    addonDirs.add(name)
  return addonDirs


proc installGithub(project: string) =
  let latestUrl = fmt"https://api.github.com/repos/{project}/releases/latest"
  let latestJson = parseJson(waitFor getLatestJson(latestUrl))
  
  let assets = latestJson["assets"]
  var downloadUrl: string
  if len(assets) != 0:
    for asset in assets:
      if asset["content_type"].getStr() == "application/json":
        continue
      let lc = asset["name"].getStr().toLower()
      if not (lc.contains("bcc") or lc.contains("tbc") or lc.contains("wotlk") or lc.contains("classic")):
        downloadUrl = asset["browser_download_url"].getStr()
        break
  else:
    downloadUrl = latestJson["zipball_url"].getStr()
    
  let filename = waitFor downloadAsset(downloadUrl)
  let path = joinPath(config.tempDir, filename)
  
  let extractDir = path.strip(chars = {'z', 'i', 'p'}).strip(chars = {'.'})
  unzip(filename, extractDir)
  
  let addonDirs = moveAddonDirs(extractDir)

  let v = latestJson["name"].getStr()
  let version = if v != "": v else: latestJson["tag_name"].getStr()
  config.addons.add(newAddon(project, GITHUB, version, addonDirs))


proc installGitlab(project: string) =
  # https://gitlab.com/siebens/legacy/autoactioncam
  # https://gitlab.com/api/v4/projects/siebens%2Flegacy%2Fautoactioncam/releases
  let urlEncodedProject = project.replace("/", "%2F")
  let latestUrl = fmt"https://gitlab.com/api/v4/projects/{urlEncodedProject}/releases"
  let latestJson = parseJson(waitFor getLatestJson(latestUrl))[0]
  
  var downloadUrl:string
  for source in latestJson["assets"]["sources"]:
    if source["format"].getStr() == "zip":
      downloadUrl = source["url"].getStr()
  if downloadUrl == "":
    echo fmt"Error: Unable to determine download URL for {project}"
  
  let filename = waitFor downloadAsset(downloadUrl)
  let path = joinPath(config.tempDir, filename)
  
  let extractDir = path.strip(chars = {'z', 'i', 'p'}).strip(chars = {'.'})
  unzip(filename, extractDir)
  
  let addonDirs = moveAddonDirs(extractDir)
  
  let v = latestJson["tag_name"].getStr()
  let version = if v != "": v else: latestJson["name"].getStr()
  config.addons.add(newAddon(project, GITLAB, version, addonDirs))


proc getTukuiAddons(): JsonNode =
  if config.tukuiCache.isNil:
    config.tukuiCache = parseJson(waitFor getLatestJson(tukuiAddonUrl))
  return config.tukuiCache


proc installTukUI(project: string) =
  var latestJson: JsonNode
  if project == "elvui" or project == "tukui":
    latestJson = parseJson(waitFor getLatestJson(fmt"https://www.tukui.org/api.php?ui={project}"))
  else:
    latestJson = getTukuiAddons()[project]

  let downloadUrl = latestJson["url"].getStr()
  let version = latestJson["version"].getStr()
  
  let filename = waitFor downloadAsset(downloadUrl)
  let path = joinPath(config.tempDir, filename)
  
  let extractDir = path.strip(chars = {'z', 'i', 'p'}).strip(chars = {'.'})
  unzip(filename, extractDir)
  
  let addonDirs = moveAddonDirs(extractDir)
  
  config.addons.add(newAddon(project, TUKUI, version, addonDirs))
  

proc parseAddonUrl(arg: string): (string, AddonSource) =
  var urlmatch: array[2, string]
  let pattern = re"^(?:https?:\/\/)?(?:www\.)?(.*)\.(?:com|org)\/(.*)"
  #instead of discarding we should check for -1 as an error
  discard find(arg, pattern, urlmatch, 0, len(arg))
  case urlmatch[0].toLower()
    of "github":
      # https://github.com/Stanzilla/AdvancedInterfaceOptions
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
      # https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html
      let p = re"^downloads\/info(\d*)-"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      return (m[0], WOWINT)
    else:
      echo "Unable to determine the addon source."
      quit()

proc installAddon(arg: string) =
  let (project, source) = parseAddonUrl(arg)
  case source
    of GITHUB:
      installGithub(project)
    of GITLAB:
      installGitlab(project)
    of TUKUI:
      installTukUI(project)
    of WOWINT:
      echo "TODO"
    else:
      quit()
  writeInstalledAddons()

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

proc updateAll(): {.async.} =
  # get seq[Future[UpdateData]]
  # loop over seq, 


proc displayHelp() =
  echo "  -u, --update                 Update installed addons"
  echo "  -i, --install <arg>          Install an addon where <arg> is the url"
  echo "  -a, --add <arg>              Same as --install"
  echo "  -r, --remove <arg>           Remove an installed addon where <arg> is the id# or project"
  echo "  -l, --list                   List installed addons"
  echo "      --pin <addon id#>        Pin an addon at the current version, do not update"
  echo "      --unpin <addon id#>      Unpin an addon, resume updates"
  echo "      --restore <addon id#>    Restore addon to last backed up version and pin it"
  quit()

var opt = initOptParser(commandLineParams(), 
                        shortNoVal = {'h', 'l', 'u', 'i', 'a'}, 
                        longNoVal = @["help", "list", "update"])

type
  Command = enum
    install, remove, update, list, pin, unpin, restore, none

var command: Command = none
var target: string = ""
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
      target = val
      case key:
        of "add", "install": command = install
        of "remove": command = remove
        of "pin": command = pin
        of "unpin": command = unpin
        of "restore": command = restore
        else: displayHelp()
  of cmdArgument:
    # echo "cmd ", "'", key, "'"
    target = key
  else: displayHelp()
case command
  of install: 
    installAddon(target)
  of remove:
    if len(target) > 4:
      removeAddon(target)
    else:
      removeAddon(int16(parseInt(target)))
  of update:
    discard updateAll()
  of list: echo "TODO"
  of pin: echo "TODO"
  of unpin: echo "TODO"
  of restore: echo "TODO"
  of none: echo "TODO" #if no args at all just update everything

# default wow folder on windows C:\Program Files (x86)\World of Warcraft\
# addons folder is <WoW>\_retail_\Interface\AddOns
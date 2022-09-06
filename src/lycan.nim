import std/asyncdispatch
import std/hashes
import std/httpclient
import std/json
import std/jsonutils
import std/strformat
import std/strutils

import std/os
import std/parseopt
import std/re

import zip/zipfiles

type
  AddonSource* = enum
    github, gitlab, tukui_main, tukui_addon, wowint, unknown

type
  Addon* = object
    id: int16
    project: string
    source: AddonSource
    version: string
    directories: seq[string]

  Config* = object
    flavor: string
    tempDir: string
    addonDir: string
    installedAddonsJson: string
    addons: seq[Addon]

proc loadInstalledAddons(file: string): seq[Addon] =
  let addonsJson = parseJson(readFile(file))
  var addons: seq[Addon]
  for addon in addonsJson:
    addons.add(addon.to(Addon))
  return addons

let configJson = parseJson(readFile("test/lycan.json"))
let flavor = configJson["flavor"].getStr()
let install = configJson[flavor]["installedAddons"].getStr()
var config* = Config(flavor: flavor,
                    tempDir: getTempDir(),
                    addonDir: configJson[flavor]["addonDir"].getStr(),
                    installedAddonsJson: install,
                    addons: loadInstalledAddons(install))


proc getLatestJson(url: string): Future[string] {.async.} =
  var client = newAsyncHttpClient()
  return await client.getContent(url)


proc downloadAsset(url: string, filename: string) {.async.} =
  var client = newAsyncHttpClient()
  let response = await client.get(url)
  let file = open(filename, fmWrite)
  write(file, waitFor response.body)
  close(file)


proc unzip(filename: string, extractDir: string) =
  var z: ZipArchive
  if not z.open(filename):
    echo fmt"Opening {filename} failed"
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
  for (dir, name) in tocPaths:
    let lc = name.toLower()
    if not (lc.contains("tbc") or lc.contains("wtolk") or lc.contains("bcc") or lc.contains("classic")):
      let (base, _) = splitPath(dir)
      let newPath = joinPath(base, name)
      moveDir(dir, newPath)
      return @[newPath]


proc writeInstalledAddons() =
  let options = ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef)
  let addonsJson = config.addons.toJson(opt = options)
  let file = open("test/lycan_addons.json", fmWrite)
  write(file, addonsJson)
  close(file)

proc installGithub(project: string) =
  let latestUrl = fmt"https://api.github.com/repos/{project}/releases/latest"
  let latestJson = parseJson(waitFor getLatestJson(latestUrl))
  
  let assets = latestJson["assets"]
  var name: string
  var downloadUrl: string
  if len(assets) != 0:
    for asset in assets:
      if asset["content_type"].getStr() == "application/json":
        continue
      name = asset["name"].getStr()
      let n = name.toLower()
      if not (n.contains("bcc") or n.contains("tbc") or n.contains("wotlk") or n.contains("classic")):
        downloadUrl = asset["browser_download_url"].getStr()
        break
  else:
    name = hash(project).intToStr() & ".zip"
    downloadUrl = latestJson["zipball_url"].getStr()
    
  let filename = joinPath(config.tempDir, name)
  waitFor downloadAsset(downloadUrl, filename)
  
  let extractDir = joinPath(config.tempDir, name.strip(chars = {'z', 'i', 'p'}).strip(chars = {'.'}))
  unzip(filename, extractDir)
  
  let sourceDirs = getAddonDirs(extractDir)
  var addonsDirs: seq[string]
  for dir in sourceDirs:
    let (_, name) = splitPath(dir)
    let destinationDir = joinPath(config.addonDir, name)
    moveDir(dir, destinationDir)
    addonsDirs.add(name)
  
  var newAddon: Addon
  newAddon.id = -1
  newAddon.project = project
  newAddon.source = github
  let v = latestJson["name"].getStr()
  newAddon.version = if v != "": v else: latestJson["tag_name"].getStr()
  newAddon.directories = addonsDirs
  
  for addon in config.addons:
    if addon.project == project:
      newAddon.id = addon.id
      delete(config.addons, find(config.addons, addon))
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

  config.addons.add(newAddon)
  writeInstalledAddons()

proc parseAddonUrl(arg: string): (string, AddonSource) =
  var urlmatch: array[2, string]
  let pattern = re"^(?:https?:\/\/)?(?:www\.)?(.*)\.(?:com|org)\/(.*)"
  #instead of discarding we should check for -1 as an error
  discard find(arg, pattern, urlmatch, 0, len(arg))
  case urlmatch[0]
    of "github":
      return (urlmatch[1], github)
    of "gitlab":
      # https://gitlab.com/siebens/legacy/autoactioncam
      # https://gitlab.com/api/v4/projects/siebens%2Flegacy%2Fautoactioncam/releases
      return (urlmatch[1], gitlab)
    of "tukui":
      let p = re"^(download|addons)\.php\?(?:ui|id)=(.*)"
      var m: array[2, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      if m[0] == "download":
        return (m[1], tukui_main)
      elif m[0] == "addons":
        return (m[1], tukui_addon)
    of "wowinterface":
      # https://api.mmoui.com/v3/game/WOW/filedetails/{project}.json
      # https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html
      let p = re"^downloads\/info(\d*)-"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      return (m[0], wowint)
    else:
      echo "Unable to determine the addon source."
      quit()

proc installAddon(arg: string) =
  let (id, source) = parseAddonUrl(arg)
  case source
    of github:
      installGithub(id)
    else:
      quit()

proc removeAddon(arg: int16) = 
  for addon in config.addons:
    if addon.id == arg:
      for dir in addon.directories:
        removeDir(joinPath(config.addonDir, dir))
      config.addons.delete(config.addons.find(addon))
      writeInstalledAddons()
      return
  echo &"Error: No installed addon with id \"{arg}\""

proc removeAddon(arg: string) = 
  for addon in config.addons:
    if addon.project == arg:
      removeAddon(addon.id)
      return
  echo &"Error: \"{arg}\" not found"

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
  of install: installAddon(target)
  of remove:
    if len(target) > 4:
      removeAddon(target)
    else:
      removeAddon(int16(parseInt(target)))
  of update: echo "TODO"
  of list: echo "TODO"
  of pin: echo "TODO"
  of unpin: echo "TODO"
  of restore: echo "TODO"
  of none: echo "TODO" #if no args at all just update everything

# default wow folder on windows C:\Program Files (x86)\World of Warcraft\
# addons folder is <WoW>\_retail_\Interface\AddOns
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

proc displayHelp() =
  echo "  -u, --update                Update installed addons"
  echo "  -i, --install <addon id>    Install an addon"
  echo "  -a, --add <addon id>        Same as --install"
  echo "  -r, --remove <addon id>     Remove an installed addon"
  echo "  -l, --list                  List installed addons"
  echo "      --pin <addon id>        Pin an addon at the current version, do not update"
  echo "      --unpin <addon id>      Unpin an addon, resume updates"
  echo "      --restore <addon id>    Restore addon to last backed up version and pin it"
  quit()

type
  AddonSource = enum
    github, gitlab, tukui, wowint, unknown

type
  Addon* = object
    id: string
    source: AddonSource
    version: string
    directories: seq[string]

let config = parseJson(readFile("test/lycan.json"))
let flavor = "retail"
let tempDir = getTempDir()

proc parseAddonUrl(arg: string): (string, AddonSource) =
  var matches: array[4, string]
  let pattern = re"^(?:https?:\/\/)?(?:www\.)?(.\w*)\.(?:com|org)\/(?:(?:(.\w*\/(.\w*-?\w*)(?:\.html)?))|(?:download\.php\?ui=(.*)))"
  discard find(arg, pattern, matches, 0, len(arg))
  case matches[0]
    of "github":
      return (matches[1], github)
    of "gitlab":
      return (matches[1], gitlab)
    of "tukui":
      return (matches[3], tukui)
    of "wowinterface":
      return (matches[2], wowint)
    else:
      echo "Unable to determine the addon source."
      quit()

proc loadInstalledAddons(): seq[Addon] =
  let addonsJson = parseJson(readFile("test/lycan_addons.json"))
  var addons: seq[Addon]
  for addon in addonsJson:
    addons.add(addon.to(Addon))
  return addons

var addons: seq[Addon] = loadInstalledAddons()
# var addons: seq[Addon]

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


proc getAddonDirs(path: string): seq[string] =
  var subDirs: seq[string] = @[path]
  var dirs: seq[string] = @[]
  while len(dirs) == 0 and len(subDirs) > 0:
    let parent = subDirs[0]
    for kind, path in walkDir(parent):
      if kind == pcFile:
        let (_, name, ext) = splitFile(path)
        if ext == ".toc":
          let (parentHead, parentTail) = splitPath(parent)
          if name == parentTail:
            return subDirs
          else:
            return @[joinPath(parentHead, name)]
    subDirs = @[]
    for kind, path in walkDir(parent):
      if kind == pcDir:
        subDirs.add(path)
    # TODO: Error Handling, should raise an error instead of returning empty sequence
  return @[]

proc writeInstalledAddons() =
  let options = ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef)
  let addonsJson = addons.toJson(opt = options)
  let file = open("test/lycan_addons.json", fmWrite)
  write(file, addonsJson)
  close(file)

proc installGithub(id: string) =
  let latestUrl = fmt"https://api.github.com/repos/{id}/releases/latest"
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
    name = hash(id).intToStr() & ".zip"
    downloadUrl = latestJson["zipball_url"].getStr()
    
  let filename = joinPath(tempDir, name)
  waitFor downloadAsset(downloadUrl, filename)
  
  let extractDir = joinPath(tempDir, name.strip(chars = {'z', 'i', 'p'}).strip(chars = {'.'}))
  unzip(filename, extractDir)
  
  let sourceDirs = getAddonDirs(extractDir)
  var addonsDirs: seq[string]
  for dir in sourceDirs:
    let (_, name) = splitPath(dir)
    let destinationDir = joinPath(config[flavor]["dir"].getStr(), name)
    moveDir(dir, destinationDir)
    addonsDirs.add(destinationDir)
  
  var newAddon: Addon
  newAddon.id = id
  newAddon.source = github
  let v = latestJson["name"].getStr()
  newAddon.version = if v != "": v else: latestJson["tag_name"].getStr()
  newAddon.directories = addonsDirs
  
  for addon in addons:
    if addon.id == id:
      addons.delete(addons.find(addon))
      break
  addons.add(newAddon)
  writeInstalledAddons()

proc installAddon(arg: string) =
  let (id, source) = parseAddonUrl(arg)
  case source
    of github:
      installGithub(id)
    else:
      quit()

var opt = initOptParser(commandLineParams(), 
                        shortNoVal = {'h', 'l', 'u'}, 
                        longNoVal = @["help", "list", "update"])

for kind, key, val in opt.getopt():
  case kind
  of cmdShortOption, cmdLongOption:
    case key:
      of "h", "help": displayHelp()
      of "a", "i", "add", "install":
        installAddon(val)
      of "u", "r", "uninstall", "remove": echo "TODO"
      of "l", "list": echo "TODO"
      of "pin": echo "TODO"
      of "unpin": echo "TODO"
      of "restore": echo "TODO"
      else: displayHelp()
  else: displayHelp()

# default wow folder on windows C:\Program Files (x86)\World of Warcraft\
# addons folder is <WoW>\_retail_\Interface\AddOns
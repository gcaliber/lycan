import std/asyncdispatch
import std/httpclient
import std/json
import std/strformat
import std/strutils

import std/os
import std/parseopt

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
    github, gitlab, wowint, unknown

type
  Addon* = object
    id: string
    source: AddonSource
    version: string

proc determineSource(arg: string): (string, AddonSource) =
  if arg.startsWith("http://"):
    var source: AddonSource
    let parts = arg[7..^1].split('/')
    if parts[0].contains("github"):
      return (parts[1] & "/" & parts[2], github)
    if parts[0].contains("gitlab"):
      return (parts[1] & "/" & parts[2], gitlab)
    if parts[0].contains("wowinterface"):
      # need to strip .html off the end
      return (parts[2], wowint)
  
  if arg.startsWith("github.com")
  return unknown

proc installAddon(arg: string) =
  let id, source = parseArg(arg)
  case source
  of github:
    return
  else:
    return

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

let config = parseJson(readFile("test/lycan.json"))
let flavor = "retail"
let tempDir = getTempDir()

proc loadInstalledAddons(): seq[Addon] =
  let addonsJson = parseJson(readFile("test/lycan_addons.json"))
  var addons: seq[Addon]
  for addon in addonsJson["addons"]:
    addons.add(addon.to(Addon))
  return addons

let addons: seq[Addon] = loadInstalledAddons()

proc getLatestJson(url: string): Future[string] {.async.} =
  var client = newAsyncHttpClient()
  return await client.getContent(url)

proc downloadAsset(url: string, filename: string) {.async.} =
  var client = newAsyncHttpClient()
  await client.downloadFile(url, filename)

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
    let current = subDirs[0]
    for kind, path in walkDir(current):
      if kind == pcFile:
        let (_, _, ext) = splitFile(path)
        if ext == ".toc":
          return subDirs
    subDirs = @[]
    for kind, path in walkDir(current):
      if kind == pcDir:
        subDirs.add(path)
    # TODO: Error Handling, should raise an error instead of returning empty sequence
  return @[]

proc updateAddon(addon: Addon, assets: JsonNode) =
  for asset in assets:
    if asset["content_type"].getStr() == "application/json":
      continue
    let name = asset["name"].getStr()
    let nameLower = name.toLower()
    if nameLower.contains("bcc") or 
      nameLower.contains("tbc") or
      nameLower.contains("wotlk") or
      nameLower.contains("classic"):
        continue
    else:
      let downloadUrl = asset["browser_download_url"].getStr()
      let filename = joinPath(tempDir, name)
      waitFor downloadAsset(downloadUrl, filename)
      
      let extractDir = joinPath(tempDir, name.strip(chars = {'z', 'i', 'p'}).strip(chars = {'.'}))
      unzip(filename, extractDir)
      
      let addonDirs = getAddonDirs(extractDir)
      for dir in addonDirs:
        let (_, name) = splitPath(dir)
        let destinationDir = joinPath(config[flavor]["dir"].getStr(), name)
        moveDir(dir, destinationDir)


      break
  return

for addon in addons:
  let latestUrl = fmt"https://api.github.com/repos/{addon.id}/releases/latest"
  let latestJson = parseJson(waitFor getLatestJson(latestUrl))

  let version = latestJson["name"].getStr()
  if version == addon.version:
    echo addon.id, " skipped"
  else:
    echo addon.id, " updating"
    updateAddon(addon, latestJson["assets"])
    
import std/[json, jsonutils]
import std/options
import std/os
import std/[strformat, strutils]
import std/times

import types
import term

var configData*: Config

proc fromJsonHook(a: var Addon, j: JsonNode) =
  var
    b: Option[string]
    d: seq[string]
    k: AddonKind
  
  try:
    b = some(j["branch"].getStr())
  except KeyError:
    b = none(string)

  d.fromJson(j["dirs"])
  k.fromJson(j["kind"])

  a = new(Addon)
  a.project = j["project"].getStr()
  a.kind = k
  a.branch = b
  a.version = j["version"].getStr()
  a.name = j["name"].getStr()
  a.dirs = d
  a.id = int16(j["id"].getInt())
  a.pinned = j["pinned"].getBool()
  a.time = parse(j["time"].getStr(), "yyyy-MM-dd'T'HH:mm")

proc parseInstalledAddons(filename: string): seq[Addon] =
  if not fileExists(filename): return @[]
  let addonsJson = parseJson(readFile(filename))
  for addon in addonsJson:
    var a = new(Addon)
    a.fromJson(addon)
    result.add(a)

proc dir(mode: Mode): string =
  return '_' & $mode & '_'

proc getWowDir(mode: Mode): string =
  echo &"No configuration found. Searching for World of Warcraft install location for mode: {$mode}"
  var root = getHomeDir()
  when defined(windows):
    let default = joinPath("C:", "Program Files (x86)", "World of Warcraft")
    if dirExists(default):
      return default
    root = "C:"
  for path in walkDirRec(root, yieldFilter = {pcDir}):
    let dir = mode.dir()
    if path.contains("World of Warcraft" / dir):
      var wow = path
      while not wow.endsWith("World of Warcraft"):
        wow = parentDir(wow)
      if dirExists(joinPath(wow, dir, "Interface", "AddOns")):
        return wow
      else:
        echo &"Found WoW install location: {wow}"
        echo "No AddOns directory was found. Make sure you have started WoW at least once."
        echo "If this location is incorrect you can set it manually:"
        echo "  lycan --config path <path/to/World of Warcraft>\n"
        return ""
  echo "Unable to determine the World of Warcraft install location."
  echo "Set the location manually:"
  echo "  lycan --config path <path/to/World of Warcraft>\n"
  echo "Change modes:"
  echo "  lycan --config mode <mode>\n"
  echo "For supported modes see lycan --help"
  return ""

let 
  lycanConfigFile: string = "lycan.cfg"
  localPath: string = getCurrentDir() / lycanConfigFile
  configPath: string = joinPath(getConfigDir(), "lycan", lycanConfigFile)

proc writeConfig*(config: Config) =
  let json = newJObject()
  json["mode"] = %config.mode
  json["githubToken"] = %config.githubToken
  let path = if fileExists(localPath): localPath else: configPath
  let file = readFile(path)
  var existingConfig: JsonNode
  try:
    existingConfig = parseJson(file)
  except JsonParsingError:
    existingConfig = newJObject()
  for mode in [Retail, Vanilla, Wrath]:
    if mode == config.mode:
      json[$mode] = newJObject()
      json[$mode]["addonJsonFile"] = %config.addonJsonFile
      json[$mode]["installDir"] = %config.installDir
      json[$mode]["backupEnabled"] = %config.backupEnabled
      json[$mode]["backupDir"] = %config.backupDir
    else:
      try:
        json[$mode] = existingConfig[$mode]
      except KeyError:
        json[$mode] = newJObject()
        json[$mode]["addonJsonFile"] = %""
        json[$mode]["installDir"] = %""
        json[$mode]["backupEnabled"] = %true
        json[$mode]["backupDir"] = %""
  if not dirExists(path.parentDir()):
    createDir(path.parentDir())
  writeFile(path, pretty(json))

proc loadConfig*(newMode: Mode = None, newPath: string = ""): Config =
  var 
    configJson: JsonNode
    local = false
  if fileExists(localPath):
    try:
      let file = readFile(localPath)
      local = true
      if len(file) != 0:
        configJson = parseJson(file)
    except CatchableError as e:
      echo &"Unable to parse {localPath}"
      echo &"When present this file overrides {configPath}\n"
      echo e.msg
      quit()
  elif fileExists(configPath):
    try: 
      configJson = parseJson(readFile(configPath))
    except CatchableError as e:
      echo &"Unable to parse {configPath}"
      echo "Delete this file to have lycan recreate the default config."
      echo e.msg
      quit()

  var
    mode: Mode
    settings: JsonNode
    modeExists = true
  result = Config()
  if not configJson.isNil:
    try:
      if newMode == None:
        mode.fromJson(configJson["mode"])
      else:
        mode = newMode
      settings = configJson[$mode]
      if settings["addonJsonFile"].getStr() == "":
        modeExists = false
    except KeyError:
      modeExists = false
  else:
    mode = if newMode == None: Retail else: newMode
    modeExists = false
  
  var addonJsonFile: string
  if modeExists:
    addonJsonFile = settings["addonJsonFile"].getStr()
    result.installDir = settings["installDir"].getStr()
    result.addonJsonFile = addonJsonFile
    result.backupEnabled = settings["backupEnabled"].getBool()
    result.backupDir = settings["backupDir"].getStr()
  else:
    var wow = if newPath == "": getWowDir(mode) else: newPath
    result.backupEnabled = true
    if wow != "":
      let dir = mode.dir()
      addonJsonFile = joinPath(wow, dir, "WTF", "lycan_addons.json")
      result.installDir = joinPath(wow, dir, "Interface", "AddOns")
      result.addonJsonFile = addonJsonFile
      result.backupDir = joinPath(wow, dir, "Interface", "lycan_backup")

  try:
    result.githubToken = configJson["githubToken"].getStr()
  except:
    discard
  result.mode = mode
  result.tempDir = getTempDir()
  result.term = termInit()
  result.local = local
  if addonJsonFile != "":
    result.addons = parseInstalledAddons(addonJsonFile)

proc setPath*(path: string) =
  let normalPath = path.normalizePathEnd()
  if not dirExists(normalPath):
    echo &"Error: Path provided does not exist:\n  {normalPath}"
    quit()
  let mode = configData.mode.dir()
  let installDir = joinPath(normalPath, mode, "Interface", "AddOns")
  if not dirExists(installDir):
    echo &"Error: Did not find {installDir}"
    echo "Make sure you are in the correct mode and that World of Warcraft has been started at least once."
    quit()
  configData = loadConfig(newPath = normalPath)

proc setMode*(mode: string) =
  case mode.toLower()
  of "retail", "r":
    configData.mode = Retail
  of "classic", "wrath", "wrathc", "wotlk", "wotlkc", "w":
    configData.mode = Wrath
  of "classic_era", "vanilla", "v":
    configData.mode = Vanilla
  else:
    echo "Valid modes are"
    echo "  retail, r    Most recent retail expansion"
    echo "  wrath, w     Wrath of the Lich King Classic"
    echo "  vanilla, v   Vanilla era Classic"
  configData = loadConfig(configData.mode)

proc setBackup*(arg: string) =
  configData = loadConfig()
  case arg.toLower()
  of "y", "yes", "on", "enable", "enabled", "true":
    configData.backupEnabled = true
  of "n", "no", "off", "disable", "disabled", "false":
    configData.backupEnabled = false
  else:
    if not dirExists(arg):
      echo &"Error: Path provided does not exist:\n  {arg}"
      quit()
    configData = loadConfig()
    for kind, path in walkDir(configData.backupDir):
      if kind == pcFile:
        moveFile(path, arg / lastPathPart(path))
    configData.backupDir = arg
    echo "Backup directory now ", arg
    echo "Existing backup files have been moved."
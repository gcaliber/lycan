import std/[json, jsonutils]
import std/options
import std/os
import std/[strformat, strutils]
import std/times

import types
import term
import logger

var configData*: Config
var addonChannel*: Channel[Addon]

proc fromJsonHook(a: var Addon, j: JsonNode) =
  var
    b, n: Option[string]
    d: seq[string]
    k: AddonKind
  try:
    b = some(j["branch"].getStr())
  except KeyError:
    b = none(string)
  try:
    n = some(j["overrideName"].getStr())
  except KeyError:
    n = none(string)

  d.fromJson(j["dirs"])
  k.fromJson(j["kind"])

  a = new(Addon)
  a.project = j["project"].getStr()
  a.kind = k
  a.branch = b
  a.version = j["version"].getStr()
  a.name = j["name"].getStr()
  a.overrideName = n
  a.dirs = d
  a.id = int16(j["id"].getInt())
  a.pinned = j["pinned"].getBool()
  a.time = parse(j["time"].getStr(), "yyyy-MM-dd'T'HH:mm")

proc parseInstalledAddons(filename: string): seq[Addon] =
  if not fileExists(filename): return @[]
  var addonsJson: JsonNode
  try:
    addonsJson = parseJson(readFile(filename))
  except Exception as e:
    echo &"Fatal error parsing installed addons file: {filename}"
    log(&"Fatal error parsing installed addons file: {filename}", Fatal, e)
    quit()
  for addon in addonsJson:
    var a = new(Addon)
    a.fromJson(addon)
    result.add(a)

proc dir(mode: Mode): string =
  return case mode
  of Retail: "_retail_"
  of Vanilla: "_classic_era_"
  of Classic: "_classic_"
  of None: ""

proc getWowDir(mode: Mode, fast: bool = false): string =
  log("Starting search for World of Warcraft install location", Info)
  var searchPaths: seq[string]
  if not configData.isNil:
    let knownDir = configData.installDir.parentDir().parentDir().parentDir()
    if knownDir != "":
      searchPaths.add(knownDir)
  let dir = mode.dir()
  searchPaths.add(getCurrentDir())
  if not fast:
    when defined(windows):
      let default = joinPath("C:", "Program Files (x86)", "World of Warcraft")
      if dirExists(default / dir):
        return default
      searchPaths.add("C:")
    else:
      searchPaths.add(getHomeDir())
  for root in searchPaths:
    log(&"Searching subdirecties for World of Warcraft starting in {root}", Info)
    for path in walkDirRec(root, yieldFilter = {pcDir}):
      if path.contains("World of Warcraft" / dir):
        var wow = path
        while not wow.endsWith("World of Warcraft"):
          wow = parentDir(wow)
        log(&"Found World of Warcraft directory: {wow}.", Info)
        return wow
  log("Unable to find World of Warcraft directory", Info)
  return ""

let 
  lycanConfigFile: string = "lycan.cfg"
  localPath: string = getCurrentDir() / lycanConfigFile
  configPath: string = joinPath(getConfigDir(), "lycan", lycanConfigFile)

proc writeConfig*(config: Config) =
  let json = newJObject()
  json["mode"] = %config.mode
  json["githubToken"] = %config.githubToken
  json["logLevel"] = %config.logLevel
  let path = if fileExists(localPath): localPath else: configPath
  if not dirExists(path.parentDir()):
    createDir(path.parentDir())
  var existingConfig: JsonNode
  try:
      let file = readFile(path)
      existingConfig = parseJson(file)
  except:
    existingConfig = newJObject()
  for mode in [Retail, Vanilla, Classic]:
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
        json[$mode]["backupEnabled"] = %true
        let wowPath = getWowDir(mode, fast = true)
        let dir = mode.dir()
        let addonsPath = joinPath(wowPath, dir, "Interface", "AddOns")
        if wowPath != "" and dirExists(addonsPath):
          json[$mode]["addonJsonFile"] = %joinPath(wowPath, dir, "WTF", "lycan_addons.json")
          json[$mode]["installDir"] = %addonsPath
          json[$mode]["backupDir"] = %joinPath(wowPath, dir, "Interface", "lycan_backup")
        else:
          json[$mode]["addonJsonFile"] = %""
          json[$mode]["installDir"] = %""
          json[$mode]["backupDir"] = %""
  try:
    writeFile(path, pretty(json))
    log(&"Configuration file saved: {path}", Info)
  except Exception as e:
    log(&"Fatal error writing: {path}", Fatal, e)

proc loadConfig*(newMode: Mode = None, newLogLevel: LogLevel = None, newPath: string = "", basic = false): Config =
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
    if newLogLevel == None:
      result.logLevel.fromJson(configJson["logLevel"])
    else:
      result.logLevel = newLogLevel
  else:
    result.logLevel = if defined(release): Fatal else: Debug
    mode = if newMode == None: Retail else: newMode
    modeExists = false

  result.mode = mode
  result.tempDir = getTempDir()
  result.term = termInit()
  result.local = local

  if basic: 
    return

  var addonJsonFile: string
  if modeExists:
    addonJsonFile = settings["addonJsonFile"].getStr()
    result.installDir = settings["installDir"].getStr()
    result.addonJsonFile = addonJsonFile
    result.backupEnabled = settings["backupEnabled"].getBool()
    result.backupDir = settings["backupDir"].getStr()
  else:
    result.backupEnabled = true
    # if newMode != None:
    #   return
    var wowPath: string
    if newPath != "": 
      wowPath = newPath
    else: 
      echo "Searching for World of Warcraft install location."
      wowPath = getWowDir(mode)
    if wowPath == "":
      echo "Unable to determine the World of Warcraft install location."
      echo "Set the location manually:"
      echo "  lycan --config path <path/to/World of Warcraft>\n"
      echo "Change modes:"
      echo "  lycan --config mode <mode>\n"
      echo "For supported modes see lycan --help"
      quit()
    let dir = mode.dir()
    let addonsPath = joinPath(wowPath, dir, "Interface", "AddOns")
    if not dirExists(addonsPath):
      echo &"Found a WoW directory: {wowPath}\nNo AddOns directory was found. Make sure you have started WoW at least once."
    if wowPath != "":
      echo &"Found a WoW directory: {wowPath}"
      addonJsonFile = joinPath(wowPath, dir, "WTF", "lycan_addons.json")
      result.installDir = addonsPath
      result.addonJsonFile = addonJsonFile
      result.backupDir = joinPath(wowPath, dir, "Interface", "lycan_backup")

  try:
    result.githubToken = configJson["githubToken"].getStr()
  except:
    discard
  if addonJsonFile != "":
    result.addons = parseInstalledAddons(addonJsonFile)
  log("Configuration loaded", Info)

proc setPath*(path: string) =
  let normalPath = path.strip(chars = {'\'', '"'}).normalizePathEnd()
  if not dirExists(normalPath):
    echo &"Error: Path provided does not exist:\n  {normalPath}"
    quit()
  let mode = configData.mode.dir()
  let addonDir = joinPath(normalPath, mode, "Interface", "AddOns")
  if not dirExists(addonDir):
    echo &"Error: Did not find {addonDir}"
    echo "Make sure you are in the correct mode and that World of Warcraft has been started at least once."
    quit()
  log(&"Path: {normalPath} set as location for {$mode} mode", Info)
  configData = loadConfig(newPath = normalPath)

proc setMode*(mode: string) =
  case mode.toLower()
  of "retail", "r":
    configData.mode = Retail
  of "classic", "wrath", "c", "w":
    configData.mode = Classic
  of "classic_era", "vanilla", "v", "ce":
    configData.mode = Vanilla
  else:
    echo "Supported modes are"
    echo "  retail, r    Most recent retail expansion"
    echo "  classic, c   Wrath of the Lich King Classic"
    echo "  vanilla, v   Vanilla era Classic"
  log(&"Mode changed: {$mode}", Info)
  configData = loadConfig(configData.mode)

proc setBackup*(arg: string) =
  configData = loadConfig()
  case arg.toLower()
  of "y", "yes", "on", "enable", "enabled", "true":
    configData.backupEnabled = true
    log(&"Backup enabled for {configData.mode}", Info)
  of "n", "no", "off", "disable", "disabled", "false":
    configData.backupEnabled = false
    log(&"Backup disabled for {configData.mode}", Info)
  else:
    let dir = arg.strip(chars = {'\'', '"'}).normalizePathEnd()
    if not dirExists(dir):
      echo &"Error: Path provided does not exist:\n  {dir}"
      quit()
    configData = loadConfig()
    for kind, path in walkDir(configData.backupDir):
      if kind == pcFile:
        moveFile(path, arg / lastPathPart(path))
    configData.backupDir = arg
    log(&"New backup directory set: {dir}", Info)
    echo "Backup directory now ", dir
    echo "Existing backup files have been moved."

proc setGithubToken*(token: string) =
  configData = loadConfig()
  configData.githubToken = token
  log(&"Github token set to: {token}", Info)

proc showConfig*() =
  configData = loadConfig()
  let mode = case configData.mode
    of Retail: "Retail"
    of Classic: "Classic"
    of Vanilla: "Vanilla"
    of None: "Error: No mode set"
  echo &"Configuration for current mode: {mode}"
  echo &"Logging level: "
  echo &"  Addons directory: {configData.installDir}"
  echo &"  Backups enabled: {configData.backupEnabled}"
  if configData.backupEnabled:
    echo &"  Backups directory: {configData.backupDir}"
  quit()

proc setLogLevel*(arg: string) =
  let level = arg.toLower()
  var newLevel: LogLevel
  case level
  of "off": newLevel = Off
  of "debug": newLevel = Debug
  of "warn", "warning": newLevel = Warning
  of "info": newLevel = Info
  of "fatal": newLevel = Fatal
  else: 
    echo "Valid logging levels are off, info, debug, warn, and fatal"
    quit()
  configData = loadConfig(newLogLevel = newLevel)
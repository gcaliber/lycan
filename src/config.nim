import std/[json, jsonutils]
import std/options
import std/os
import std/[strformat, strutils]
import std/times

import types
import term
import jsonbeautify

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

proc getWowDir(mode: Mode): string =
  when not defined(release):
    createDir("/home/mike/projects/lycan/test/_retail_/Interface/AddOns")
    createDir("/home/mike/projects/lycan/test/_retail_/WTF")
    return "/home/mike/projects/lycan/test/"
  var root = joinPath(getHomeDir())
  when defined(windows):
    let default = joinPath("C:", "Program Files (x86)", "World of Warcraft")
    if pathExists(default):
      return default
    root = "C:"
  for path in walkDirRec(root, yieldFilter = {pcDir}):
    let dir = '_' & $mode & '_'
    if path.contains(joinPath("World of Warcraft", dir)):
      var wow = path
      while not wow.endsWith("World of Warcraft"):
        wow = parentDir(wow)
      if dirExists(joinPath(wow, dir, "Interface", "AddOns")):
        return wow
      else:
        echo &"Found WoW directory: {wow}"
        echo "No AddOns directory was found. Make sure you have started WoW at least once to create this directory."
        echo "If this location is incorrect you can set it manually with"
        echo "  lycan --config path <path/to/World of Warcraft>\n"
        quit()
  echo "Unable to determine the World of Warcraft install location."
  echo "Set the location manually with"
  echo "  lycan --config path <path/to/World of Warcraft>\n"
  quit()

let 
  lycanConfigFile: string = "lycan.cfg"
  localPath: string = joinPath(getCurrentDir(), lycanConfigFile)
  configPath: string = joinPath(getConfigDir(), "lycan", lycanConfigFile)

proc writeConfig*(config: Config) =
  let j = newJObject()
  let mode = $config.mode
  j["mode"] = %config.mode
  j["githubToken"] = %config.githubToken
  j[mode] = newJObject()
  j[mode]["addonJsonFile"] = %config.addonJsonFile
  j[mode]["installDir"] = %config.installDir
  j[mode]["backupEnabled"] = %config.backupEnabled
  j[mode]["backupDir"] = %config.backupDir
  

  let prettyJson = beautify($j)
  let path = if config.local: localPath else: configPath
  let file = open(path, fmWrite)
  write(file, prettyJson)
  close(file)

proc loadConfig(default: Mode = None): Config =
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
    mode.fromJson(configJson["mode"])
    result.githubToken = configJson["githubToken"].getStr()
    settings = configJson[$mode] 
  else:
    mode = if default == None: Retail else: default
    modeExists = false
  
  var addonJsonFile: string
  if modeExists:
    addonJsonFile = settings["addonJsonFile"].getStr()
    result.installDir = settings["installDir"].getStr()
    result.addonJsonFile = addonJsonFile
    result.backupEnabled = settings["backupEnabled"].getBool()
    result.backupDir = settings["backupDir"].getStr()
  else:
    let wow = getWowDir(mode)
    let dir = '_' & $mode & '_'
    addonJsonFile = joinPath(wow, dir, "WTF", "lycan_addons.json")
    result.installDir = joinPath(wow, dir, "Interface", "AddOns")
    result.addonJsonFile = addonJsonFile
    result.backupEnabled = true
    result.backupDir = joinPath(wow, dir, "Interface", "lycan_backup")

  result.mode = mode
  result.tempDir = getTempDir()
  result.term = termInit()
  result.local = local
  result.addons = parseInstalledAddons(addonJsonFile)
    
var configData* = loadConfig()


proc setPath*(path: string) =
  if not dirExists(path):
    echo &"Error: Path provided does not exist:\n  {path}"
    quit()
  let mode = $configData.mode
  configData.installDir = joinPath(path, mode, "Interface", "AddOns")
  if not dirExists(configdata.installDir):
    echo &"Error: Did not find {configdata.installDir}"
    echo "Make sure you are in the correct mode (retail, wotlk, etc) and that World of Warcraft has been started at least once."
    quit()
  configData.addonJsonFile = joinPath(path, mode, "WTF", "lycan_addons.json")
  configData.backupDir = joinPath(path, mode, "Interface", "lycan_backup")

proc setMode*(mode: string) =
  case mode.toLower()
  of "retail", "r", :
    configData.mode = Retail
  of "wrath", "wrathc", "wotlk", "wotlkc", "classic", "w", "c":
    configData.mode = Classic
  of "vanilla", "v":
    configData.mode = Vanilla
  else:
    echo "Valid modes are"
    echo "  retail    Most recent expansion"
    echo "  classic   Wrath of the Lich King Classic"
    echo "  vanilla   Vanilla era Classic"
    echo "These can be shortened to their first letter as well."
  configData = loadConfig(configData.mode)

proc setBackup*(arg: string) =
  case arg.toLower()
  of "y", "yes", "on", "enable", "enabled", "true":
    configData.backupEnabled = true
  of "n", "no", "off", "disable", "disabled", "false":
    configData.backupEnabled = false
  else:
    if not dirExists(arg):
      echo &"Error: Path provided does not exist:\n  {arg}"
      quit()
    for kind, path in walkDir(configData.backupDir):
      if kind == pcFile:
        moveFile(path, joinPath(arg, lastPathPart(path)))
    configData.backupDir = arg
    echo "Backup directory now ", arg
    echo "Existing backup files have been moved."

proc setGithubToken*(arg: string) =
  configData.githubToken = arg
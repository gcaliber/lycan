import std/options
import std/os
import std/json
import std/jsonutils
import std/strformat
import std/strutils
import std/times

import types
import term
import prettyjson

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

proc getWowDir(mode: string): string =
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
    if path.contains(joinPath("World of Warcraft", mode)):
      var wow = path
      while not wow.endsWith("World of Warcraft"):
        wow = parentDir(wow)
      if dirExists(joinPath(wow, mode, "Interface", "AddOns")):
        return wow
      else:
        echo &"Found WoW directory but no AddOns directory was found."
        echo "Make sure you have started WoW at least once to create this directory."
        echo "If this is the incorrect location you can set it manually with"
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
  let mode = config.mode
  j["mode"] = %config.mode
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

proc loadConfig(default: string = ""): Config =
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
    mode: string
    settings: JsonNode
    modeExists = true
  try:
    mode = if default.isEmptyOrWhitespace: configJson["mode"].getStr() else: default
    settings = configJson[mode]
  except KeyError:
    mode = if default.isEmptyOrWhitespace: "_retail_" else: default
    modeExists = false
    
  if modeExists:
    let addonJsonFile = settings["addonJsonFile"].getStr()
    result = Config(
      installDir: settings["installDir"].getStr(),
      addonJsonFile: addonJsonFile,
      backupEnabled: settings["backupEnabled"].getBool(),
      backupDir: settings["backupDir"].getStr(),
    )
  else:
    let wow = getWowDir(mode)
    let addonJsonFile = joinPath(wow, mode, "WTF", "lycan_addons.json")
    result = Config(
      installDir: joinPath(wow, mode, "Interface", "AddOns"),
      addonJsonFile: addonJsonFile,
      backupEnabled: true,
      backupDir: joinPath(wow, mode, "Interface", "lycan_backup"),
    )

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
  let mode = configData.mode
  configData.installDir = joinPath(path, mode, "Interface", "AddOns")
  if not dirExists(configdata.installDir):
    echo &"Error: Did not find {configdata.installDir}"
    echo "Make sure you are in the correct mode (retail, wotlk, etc) and that World of Warcraft has been started at least once."
    quit()
  configData.addonJsonFile = joinPath(path, mode, "WTF", "lycan_addons.json")
  configData.backupDir = joinPath(path, mode, "Interface", "lycan_backup")

proc setMode*(mode: string) =
  case mode.toLower()
  of "retail", "r":
    configData.mode = "_retail_"
  of "wrath", "w":
    configData.mode = "_classic_"
  of "classic", "c":
    configData.mode = "_classic_era_"
  else:
    echo "Valid modes are"
    echo "  retail    Most recent expansion, Shadowlands"
    echo "  wrath     Wrath of the Lich King Classic"
    echo "  classic   Vanilla era Classic"
    echo "These can be shortened to their first letter as well."
  configData = loadConfig(configData.mode)

proc setBackup*(arg: string) =
  case arg.toLower()
  of "y", "yes", "on", "enable", "true":
    configData.backupEnabled = true
  of "n", "no", "off", "disable", "false":
    configData.backupEnabled = false
  else:
    if not dirExists(arg):
      echo &"Error: Path provided does not exist:\n  {arg}"
      quit()
    for kind, path in walkDir(configData.backupDir):
      if kind == pcFile:
        moveFile(path, joinPath(arg, lastPathPart(path)))
    configData.backupDir = arg
    echo "Backup dir now ", arg
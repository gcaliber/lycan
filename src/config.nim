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

proc getWowDir(): string =
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
    if path.contains(joinPath("World of Warcraft", "_retail_")):
      var wow = path
      while not wow.endsWith("World of Warcraft"):
        wow = parentDir(wow)
      if dirExists(joinPath(wow, "_retail_", "Interface", "AddOns")):
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

proc loadConfig(): Config =
  var 
    configJson: JsonNode
    local = false
    configExists = false
  if fileExists(localPath):
    try:
      let file = readFile(localPath)
      if len(file) != 0:
        configJson = parseJson(file)
        configExists = true
      local = true
    except CatchableError as e:
      echo &"Unable to parse {localPath}"
      echo &"When present this file overrides {configPath}\n"
      echo e.msg
      quit()
  elif fileExists(configPath):
    try: 
      configJson = parseJson(readFile(configPath))
      configExists = true
    except CatchableError as e:
      echo &"Unable to parse {configPath}"
      echo "Delete this file to have lycan recreate the default config."
      echo e.msg
      quit()

  if not configExists:
    let mode = "_retail_"
    let wow = getWowDir()
    let addonJsonFile = joinPath(wow, mode, "WTF", "lycan_addons.json")
    let c = Config(
      mode: "_retail_",
      tempDir: getTempDir(),
      installDir: joinPath(wow, mode, "Interface", "AddOns"),
      addonJsonFile: addonJsonFile,
      backupEnabled: true,
      backupDir: joinPath(wow, mode, "Interface", "lycan_backup"),
      addons: parseInstalledAddons(addonJsonFile),
      term: termInit(),
      local: local
    )
    writeConfig(c)
    return c
  
  let mode = configJson["mode"].getStr()
  let addonJsonFile = configJson[mode]["addonJsonFile"].getStr()
  return Config(
    mode: mode,
    tempDir: getTempDir(),
    installDir: configJson[mode]["installDir"].getStr(),
    addonJsonFile: addonJsonFile,
    backupEnabled: configJson[mode]["backupEnabled"].getBool(),
    backupDir: configJson[mode]["backupDir"].getStr(),
    addons: parseInstalledAddons(addonJsonFile),
    term: termInit(),
    local: local
  )

var configData* = loadConfig()





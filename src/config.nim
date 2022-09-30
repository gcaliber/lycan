import std/options
import std/os
import std/json
import std/jsonutils

import types

const LYCAN_CFG: string = "/home/mike/projects/lycan/test/lycan.cfg"

let configJson = parseJson(readFile(LYCAN_CFG))
let mode = configJson["mode"].getStr()
let file = configJson[mode]["installedAddons"].getStr()

proc fromJsonHook(a: var Addon, j: JsonNode) =
  var
    b: Option[string]
    d: seq[string]
    k: AddonKind
  
  try:
    b = some($j["branch"])
  except:
    b = none(string)

  d.fromJson(j["dirs"])
  k.fromJson(j["kind"])

  a = new(Addon)
  a.project = $j["project"]
  a.kind = k
  a.branch = b
  a.version = $j["version"]
  a.name = $j["name"]
  a.dirs = d

proc parseInstalledAddons(filename: string): seq[Addon] =
  if not fileExists(filename):
    return @[]
  let addonsJson = parseJson(readFile(filename))
  var addons: seq[Addon]
  for addon in addonsJson:
    var a = new(Addon)
    a.fromJson(addon)
    addons.add(a)
  return addons

var configData* = Config(
  mode: mode,
  tempDir: getTempDir(),
  installDir: configJson[mode]["addonDir"].getStr(),
  addonJsonFile: file,
  addons: parseInstalledAddons(file)
)


  

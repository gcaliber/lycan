import print

import std/options
import std/os
import std/json
import std/jsonutils

import types
import term

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
  addons: parseInstalledAddons(file),
  term: termInit()
)


  

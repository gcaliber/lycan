import std/os
import std/json

import types

const LYCAN_CFG: string = "/home/mike/projects/lycan-nim/test/lycan.cfg"

let configJson = parseJson(readFile(LYCAN_CFG))
let mode = configJson["mode"].getStr()
let file = configJson[mode]["installedAddons"].getStr()

proc parseInstalledAddons(filename: string): seq[Addon] =
  if not fileExists(filename):
    return @[]
  let addonsJson = parseJson(readFile(filename))
  var addons: seq[Addon]
  for addon in addonsJson:
    addons.add(addon.to(Addon))
  return addons

var configData* = Config(
  mode: mode,
  tempDir: getTempDir(),
  installDir: configJson[mode]["addonDir"].getStr(),
  addonJsonFile: file,
  addons: parseInstalledAddons(file)
)


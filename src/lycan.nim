type
  Addon* = object
    id: string
    site: string
    version: string

import std/asyncdispatch
import std/httpclient
import std/json
import std/strformat
import std/strutils

import std/os
import std/parseopt

proc displayHelp() =
  echo "  -i, --install <addon id>    Install an addon"
  echo "  -a, --add <addon id>        Same as --install"
  echo "  -u, --uninstall <addon id>  Uninstall an addon"
  echo "  -r, --remove <addon id>     Same as --uninstall"
  echo "  -l, --list                  Display installed addons"
  quit()

var id: string
var opt = initOptParser(commandLineParams())

for kind, key, val in opt.getopt():
  case kind
  of cmdShortOption, cmdLongOption:
    case key:
      of "h", "help": displayHelp()
      of "a", "i", "add", "install": echo "install"
      of "u", "r", "uninstall", "remove": echo "uninstall"
      of "l", "list": echo "list"
      else: displayHelp()
  else: displayHelp()

let addon = Addon(
  id: "Stanzilla/AdvancedInterfaceOptions", 
  site: "github",
  version: "1.7.1"
)

# https://api.github.com/repos/Stanzilla/AdvancedInterfaceOptions/releases/latest
let latestUrl = fmt"https://api.github.com/repos/{addon.id}/releases/latest"

proc getLatestJson(latestUrl: string): Future[string] {.async.} =
  var client = newAsyncHttpClient()
  return await client.getContent(latestUrl)

let latestJson = parseJson(waitFor getLatestJson(latestUrl))

for item in latestJson["assets"]:
  let name = item["name"].getStr().toLower()
  if item["content_type"].getStr() == "application/json":
    continue
  #TODO: put these into an array since we might need to add more
  if name.contains("bcc") or 
    name.contains("tbc") or
    name.contains("wotlk") or
    name.contains("classic"):
      continue
  echo name
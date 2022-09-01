import std/asyncdispatch
import std/httpclient
import std/json
import std/strformat
import std/strutils

import std/os
import std/parseopt

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

var opt = initOptParser(commandLineParams(), 
                        shortNoVal = {'h', 'l', 'u'}, 
                        longNoVal = @["help", "list", "update"])

for kind, key, val in opt.getopt():
  case kind
  of cmdShortOption, cmdLongOption:
    case key:
      of "h", "help": displayHelp()
      of "a", "i", "add", "install": echo "TODO"
      of "u", "r", "uninstall", "remove": echo "TODO"
      of "l", "list": echo "TODO"
      of "pin": echo "TODO"
      of "unpin": echo "TODO"
      of "restore": echo "TODO"
      else: displayHelp()
  else: displayHelp()

type
  Addon* = object
    id: string
    site: string
    version: string

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
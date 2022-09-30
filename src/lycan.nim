import print

import std/asyncdispatch
import std/json
import std/jsonutils
import std/options
import std/os
import std/parseopt
import std/re
import std/sequtils
import std/strutils
import std/sugar

import prettyjson

import config
import addon
import types

proc assignIds(addons: seq[Addon]) =
  var ids: set[int16]
  for addon in addons:
    incl(ids, addon.id)

  var id: int16 = 1
  for addon in addons:
    if addon.id == 0:
      while id in ids: id += 1
      addon.id = id
      incl(ids, id)

proc writeAddons(addons: seq[Addon]) =
  let addonsJson = addons.toJson(opt = ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef))
  let prettyJson = beautify($addonsJson)
  let file = open(configData.addonJsonFile, fmWrite)
  write(file, prettyJson)
  close(file)
  
# https://github.com/Stanzilla/AdvancedInterfaceOptions
# https://github.com/Tercioo/Plater-Nameplates/tree/master
# https://gitlab.com/siebens/legacy/autoactioncam
# https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html
# https://www.tukui.org/download.php?ui=elvui
# https://www.tukui.org/addons.php?id=209

# https://github.com/Stanzilla/AdvancedInterfaceOptions https://github.com/Tercioo/Plater-Nameplates/tree/master https://gitlab.com/siebens/legacy/autoactioncam https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html https://www.tukui.org/download.php?ui=elvui https://www.tukui.org/addons.php?id=209

proc addonFromUrl(url: string): Option[Addon] =
  var urlmatch: array[2, string]
  let pattern = re"^(?:https?://)?(?:www\.)?(.+)\.(?:com|org)/(.+[^/\n])"
  var found = find(cstring(url), pattern, urlmatch, 0, len(url))
  if found == -1:
    return none(Addon)
  case urlmatch[0].toLower()
    of "github":
      # https://api.github.com/repos/Tercioo/Plater-Nameplates/releases/latest
      let p = re"^(.+?/.+?)(?:/|$)(?:tree/)?(.+)?"
      var m: array[2, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      if m[1] == "":
        return some(newAddon(m[0], Github))
      else:
        return some(newAddon(m[0], GithubRepo, branch = some(m[1])))
    of "gitlab":
      # https://gitlab.com/api/v4/projects/siebens%2Flegacy%2Fautoactioncam/releases
      return some(newAddon(urlmatch[1], Gitlab))
    of "tukui":
      let p = re"^(download|addons)\.php\?(?:ui|id)=(.+)"
      var m: array[2, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      if m[0] == "download":
        return some(newAddon(m[1], TukuiMain))
      else:
        return some(newAddon(m[1], TukuiAddon))
    of "wowinterface":
      # https://api.mmoui.com/v3/game/WOW/filedetails/24608.json
      let p = re"^downloads\/info(\d+)-"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      return some(newAddon(m[0], Wowint))
    else:
      return none(Addon)


proc displayHelp() =
  echo "  -u, --update                 Update installed addons"
  echo "  -i, --install <arg>          Install an addon where <arg> is the url"
  echo "  -a, --add <arg>              Same as --install"
  echo "  -r, --remove <addon id#>     Remove an installed addon where <arg> is the id# or project"
  echo "  -l, --list                   List installed addons"
  echo "      --pin <addon id#>        Pin an addon at the current version, do not update"
  echo "      --unpin <addon id#>      Unpin an addon, resume updates"
  echo "      --restore <addon id#>    Restore addon to last backed up version and pin it"
  quit()

var opt = initOptParser(
  commandLineParams(), 
  shortNoVal = {'h', 'l', 'u', 'i', 'a'}, 
  longNoVal = @["help", "list", "update"]
)

proc process(addons: seq[Addon]): Future[seq[Addon]] {.async.} =
  var futures: seq[Future[Option[Addon]]]
  for addon in addons:
    futures.add(addon.install())
  let opt = await all(futures)
  let addons = collect(newSeq):
    for a in opt:
      if a.isSome: a.get()
  return addons


var action: Action = doUpdate
var args: seq[string]
for kind, key, val in opt.getopt():
  case kind
  of cmdShortOption, cmdLongOption:
    if val == "":
      case key:
        of "h", "help": displayHelp()
        of "a", "i": action = doInstall
        of "u": action = doUpdate
        of "r": action = doRemove
        of "l", "list": action = doList
        else: displayHelp()
    else:
      args.add(val)
      case key:
        of "add", "install": action = doInstall
        of "remove": action = doRemove
        of "pin": action = doPin
        of "unpin": action = doUnpin
        of "restore": action = doRestore
        else: displayHelp()
  of cmdArgument:
    args.add(key)
  else: displayHelp()

var addons: seq[Addon]
case action
  of doInstall:
    for arg in args:
      var addon = addonFromUrl(arg)
      if addon.isSome:
        addons.add(addon.get())
  of doUpdate:
    echo "TODO"
  of doRemove: 
    echo "TODO"
  of doPin: echo "TODO pin"
  of doUnpin: echo "TODO unpin"
  of doRestore: echo "TODO restore"
  of doList: echo "TODO list"
  of doNothing: discard

let updates = waitFor addons.process()
let noupdates = configData.addons.filter(proc (addon: Addon): bool = addon in updates)
let finalAddons = concat(updates, noupdates)
assignIds(finalAddons)
writeAddons(finalAddons)

# default wow folder on windows C:\Program Files (x86)\World of Warcraft\
# addons folder is <WoW>\_retail_\Interface\AddOns
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
import std/algorithm

import addon
import config
import prettyjson
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

proc writeAddons(addons: var seq[Addon]) =
  if len(addons) == 0: return
  addons.sort((a, z) => int(a.name < z.name))
  let addonsJson = addons.toJson(ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef))
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

proc addonFromId(id: int16): Option[Addon] =
  for a in configData.addons:
    if a.id == id:
      return some(a)
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

proc installAll(addons: seq[Addon]): Future[seq[Addon]] {.async.} =
  var futures: seq[Future[Option[Addon]]]
  for addon in addons:
    futures.add(addon.install())
  let opt = await all(futures)
  let addons = collect(newSeq):
    for a in opt:
      if a.isSome: a.get()
  return addons

proc removeAll(addons: seq[Addon]): seq[Addon] =
  var removed: seq[Addon]
  for addon in addons:
    removed.add(addon.uninstall())
  return removed

proc pinToggleAll(addons: seq[Addon]): seq[Addon] =
  var pinned: seq[Addon]
  for addon in addons:
    pinned.add(addon.pinToggle())
  return pinned

var action: Action = DoUpdate
var args: seq[string]
for kind, key, val in opt.getopt():
  case kind
  of cmdShortOption, cmdLongOption:
    if val == "":
      case key:
        of "h", "help": displayHelp()
        of "a", "i": action = DoInstall
        of "u": action = DoUpdate
        of "r": action = DoRemove
        of "l", "list": action = DoList
        else: displayHelp()
    else:
      args.add(val)
      case key:
        of "add", "install": action = DoInstall
        of "remove": action = DoRemove
        of "pin": action = DoPin
        of "unpin": action = DoUnpin
        of "restore": action = DoRestore
        else: displayHelp()
  of cmdArgument:
    args.add(key)
  else: displayHelp()

var 
  addons: seq[Addon]
  line = 0
  ids: seq[int16]
case action
of DoInstall:
  for arg in args:
    var addon = addonFromUrl(arg)
    if addon.isSome:
      var a = addon.get()
      a.line = line
      addons.add(a)
      line += 1
of DoUpdate:
  for addon in configData.addons:
    addon.line = line
    addons.add(addon)
    line += 1
of DoRemove, DoPin, DoUnpin:
  for arg in args:
    try:
      ids.add(int16(arg.parseInt()))
    except:
      continue
  for id in ids:
    var addon = addonFromId(id)
    if addon.isSome:
      var a = addon.get()
      a.line = line
      addons.add(a)
      line += 1
of DoList: echo "TODO list"
of DoRestore: echo "TODO restore"



var final: seq[Addon]

case action
of DoInstall, DoUpdate:
  let updates = waitFor addons.installAll()
  let noupdates = configData.addons.filter(addon => addon notin updates)
  final = concat(updates, noupdates)
  assignIds(final)
of DoRemove:
  let removed = addons.removeAll()
  final = configData.addons.filter(addon => addon notin removed)
of DoPin, DoUnpin:
  let toggled = addons.pinToggleAll()
  let rest = configData.addons.filter(addon => addon notin toggled)
  final = concat(toggled, rest)
of DoList: echo "TODO list"
of DoRestore: echo "TODO restore"

writeAddons(final)

# default wow folder on windows C:\Program Files (x86)\World of Warcraft\
# addons folder is <WoW>\_retail_\Interface\AddOns
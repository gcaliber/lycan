import print

import std/algorithm
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
import std/times

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
  addons.sort((a, z) => a.name > z.name)
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
  shortNoVal = {'h', 'u', 'i', 'a'}, 
  longNoVal = @["help", "update"]
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

var action: Action = Nothing
var args: seq[string]
for kind, key, val in opt.getopt():
  let lastAction = action
  case kind
  of cmdShortOption, cmdLongOption:
    if val == "":
      case key:
        of "a", "i": action = Install
        of "u": action = Update
        of "r": action = Remove
        of "l", "list": action = List
        else: displayHelp()
    else:
      args.add(val)
      case key:
        of "add", "install": action = Install
        of "update": action = Update
        of "remove": action = Remove
        of "pin": action = Pin
        of "unpin": action = Unpin
        of "restore": action = Restore
        else: displayHelp()
  of cmdArgument:
    args.add(key)
  else: displayHelp()
  if action != Nothing and lastAction != Nothing:
    echo "One thing at a time, bruh."
    displayHelp()

var 
  addons: seq[Addon]
  line = 0
  ids: seq[int16]
case action
of Install:
  for arg in args:
    var addon = addonFromUrl(arg)
    if addon.isSome:
      var a = addon.get()
      a.line = line
      addons.add(a)
      line += 1
of Update, Nothing:
  for addon in configData.addons:
    addon.line = line
    addons.add(addon)
    line += 1
of Remove, Pin, Unpin:
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
of List:
  addons = configData.addons
  if "t" in args or "time" in args:
    addons.sort((a, z) => a.time < z.time)
  for addon in addons:
    addon.line = line
    line += 1
of Restore: echo "TODO restore"

var final: seq[Addon]

case action
of Install, Update:
  let updates = waitFor addons.installAll()
  let noupdates = configData.addons.filter(addon => addon notin updates)
  final = concat(updates, noupdates)
  assignIds(final)
of Remove:
  let removed = addons.removeAll()
  final = configData.addons.filter(addon => addon notin removed)
of Pin, Unpin:
  let toggled = addons.pinToggleAll()
  let rest = configData.addons.filter(addon => addon notin toggled)
  final = concat(toggled, rest)
of List: 
  addons.apply(list)
  quit()
of Restore: echo "TODO restore"
else:
  discard

writeAddons(final)

# default wow folder on windows C:\Program Files (x86)\World of Warcraft\
# addons folder is <WoW>\_retail_\Interface\AddOns
import std/algorithm
import std/asyncdispatch
import std/[json, jsonutils]
import std/options
import std/[os, parseopt]
import std/re
import std/sequtils
import std/strformat
import std/strutils
import std/sugar
import std/terminal
import std/times

import addon
import config
import prettyjson
import term
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

proc toJsonHook(a: Addon): JsonNode =
  result = newJObject()
  result["project"] = %a.project
  if a.branch.isSome(): result["branch"] = %a.branch.get()
  result["name"] = %a.name
  result["kind"] = %a.kind
  result["version"] = %a.version
  result["id"] = %a.id
  result["pinned"] = %a.pinned
  result["dirs"] = %a.dirs
  result["time"] = %a.time.format("yyyy-MM-dd'T'HH:mm")

proc writeAddons(addons: var seq[Addon]) =
  if len(addons) == 0: return
  addons.sort((a, z) => a.name.toLower() > z.name.toLower())
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
  result = collect(newSeq):
    for a in opt:
      if a.isSome: a.get()

proc removeAll(addons: seq[Addon]): seq[Addon] =
  var removed: seq[Addon]
  for addon in addons:
    removed.add(addon.uninstall())
  return removed

proc restoreAll(addons: seq[Addon]): seq[Addon] =
  var opt: seq[Option[Addon]]
  for addon in addons:
    opt.add(addon.restore())
  result = collect(newSeq):
    for a in opt:
      if a.isSome: a.get()

proc pinAll(addons: seq[Addon]): seq[Addon] =
  var pinned: seq[Addon]
  for addon in addons:
    pinned.add(addon.pin())
  return pinned

proc unpinAll(addons: seq[Addon]): seq[Addon] =
  var pinned: seq[Addon]
  for addon in addons:
    pinned.add(addon.unpin())
  return pinned

var 
  action = Empty
  actionCount = 0
  args: seq[string]
for kind, key, val in opt.getopt():
  case kind
  of cmdShortOption, cmdLongOption:
    if val == "":
      case key:
        of "a", "i":          action = Install; actionCount += 1
        of "u":               action = Update; actionCount += 1
        of "r":               action = Remove; actionCount += 1
        of "l", "list":       action = List; actionCount += 1
        else: displayHelp()
    else:
      args.add(val)
      case key:
        of "add", "install":  action = Install; actionCount += 1
        of "update":          action = Update; actionCount += 1
        of "remove":          action = Remove; actionCount += 1
        of "pin":             action = Pin; actionCount += 1
        of "unpin":           action = Unpin; actionCount += 1
        of "restore":         action = Restore; actionCount += 1
        else: displayHelp()
  of cmdArgument:
    args.add(key)
  else:
    displayHelp()
  if actionCount > 1:
    echo "One thing at a time, bruh"
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
of Update, Empty:
  for addon in configData.addons:
    addon.line = line
    addons.add(addon)
    line += 1
of Remove, Restore, Pin, Unpin:
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

var processed, rest, final: seq[Addon]
case action
of Install, Update, Empty:
  processed = waitFor addons.installAll()
  assignIds(processed)
of Remove:
  processed = addons.removeAll()
of Pin:
  processed = addons.pinAll()
of Unpin:
  processed = addons.unpinAll()
of Restore:
  processed = addons.restoreAll()
of List: 
  addons.apply(list)
  quit()

rest = configData.addons.filter(addon => addon notin processed)
final = if action != Remove: concat(processed, rest) else: rest
writeAddons(final)

let t = configData.term
t.write(0, t.yMax, false, "\n")
for item in configData.log:
  t.write(0, t.yMax, false, fgRed, &"\nError: ", fgCyan, item.addon.getName, "\n", resetStyle)
  t.write(4, t.yMax, false, fgDefault, item.msg, "\n", resetStyle)


# default wow folder on windows C:\Program Files (x86)\World of Warcraft\
# addons folder is <WoW>\_retail_\Interface\AddOns
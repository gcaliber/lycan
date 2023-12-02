# https://github.com/Stanzilla/AdvancedInterfaceOptions
# https://github.com/Tercioo/Plater-Nameplates/tree/master
# https://gitlab.com/woblight/actionmirroringframe
# https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html

# https://github.com/Stanzilla/AdvancedInterfaceOptions https://github.com/Tercioo/Plater-Nameplates/tree/master https://gitlab.com/woblight/actionmirroringframe https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html

# https://github.com/p3lim-wow/QuickQuest https://www.tukui.org/download.php?ui=elvui https://github.com/AdiAddons/AdiBags

import std/algorithm
import std/asyncdispatch
import std/[json, jsonutils]
import std/options
import std/[os, parseopt]
import std/re
import std/sequtils
import std/[strformat, strutils]
import std/sugar
import std/terminal
import std/times

import addon
import config
import help
import term
import types

proc assignIds(addons: seq[Addon]) =
  var ids: set[int16]
  addons.apply((a: Addon) => ids.incl(a.id))

  var id: int16 = 1
  for a in addons:
    if a.id == 0:
      while id in ids: id += 1
      a.id = id
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
  addons.sort((a, z) => int(a.name.toLower() > z.name.toLower()))
  let addonsJson = addons.toJson(ToJsonOptions(enumMode: joptEnumString, jsonNodeMode: joptJsonNodeAsRef))
  let prettyJson = pretty(addonsJson)
  let file = open(configData.addonJsonFile, fmWrite)
  write(file, prettyJson)
  close(file)

proc addonFromUrl(url: string): Option[Addon] =
  var urlmatch: array[2, string]
  let pattern = re"^(?:https?://)?(?:www\.)?(.+)\.(?:com|org)/(.+[^/\n])"
  var found = find(cstring(url), pattern, urlmatch, 0, len(url))
  if found == -1:
    return none(Addon)
  case urlmatch[0].toLower()
    of "curseforge":
      return some(newAddon(url, Curse))
    of "github":
      let p = re"^(.+?/.+?)(?:/|$)(?:tree/)?(.+)?"
      var m: array[2, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      if m[1] == "":
        return some(newAddon(m[0], Github))
      else:
        return some(newAddon(m[0], GithubRepo, branch = some(m[1])))
    of "gitlab":
      return some(newAddon(urlmatch[1], Gitlab))
    of "tukui":
      return some(newAddon(urlmatch[1], Tukui))
    of "wowinterface":
      let p = re"^downloads\/info(\d+)-"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      return some(newAddon(m[0], Wowint))
    else:
      return none(Addon)

proc addonFromId(id: int16): Option[Addon] =
  for a in configData.addons:
    if a.id == id: return some(a)
  return none(Addon)

proc installAll(addons: seq[Addon]): Future[seq[Addon]] {.async.} =
  let futures = addons.map(install)
  let opt = await all(futures)
  return collect(for a in opt: (if a.isSome: a.get()))

proc restoreAll(addons: seq[Addon]): seq[Addon] =
  let opt = addons.map(restore)
  return collect(for a in opt: (if a.isSome: a.get()))

proc setup(args: seq[string]) =
  if len(args) == 0:
    assert configData.mode != None
    let mode = $configData.mode
    echo &"Mode: {mode}"
    echo &"Addons directory: {configData.installDir}"
    echo &"Backups enabled: {configData.backupEnabled}"
    if configData.backupEnabled:
      echo &"Backups directory: {configData.backupDir}"
    quit()

  if len(args) < 2:
    echo "Missing argument\n"
    displayHelp("config")
  for i in 0 ..< len(args) - 1:
    let item = args[i]
    case item:
    of "path":
      setPath(args[i + 1]); break
    of "m", "mode":
      setMode(args[i + 1]); break
    of "backup":
      setBackup(args[i + 1]); break
    of "github":
      configData.githubToken = args[i + 1]; break
    else:
      echo &"Unrecognized option {item}\n"
      displayHelp("config")
  writeConfig(configData)
  quit()




proc main() =
  var opt = initOptParser(
    commandLineParams(), 
    shortNoVal = {'u', 'i', 'a'}, 
    longNoVal = @["update"]
  )
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
        of "u":               action = Update;  actionCount += 1
        of "r":               action = Remove;  actionCount += 1
        of "l", "list":       action = List;    actionCount += 1
        of "c", "config":     action = Setup;   actionCount += 1
        of "h", "help":       action = Help;    actionCount += 1
        else: displayHelp()
      else:
        args.add(val)
        case key:
        of "add", "install":  action = Install; actionCount += 1
        of "update":          action = Update;  actionCount += 1
        of "r", "remove":     action = Remove;  actionCount += 1
        of "l", "list":       action = List;    actionCount += 1
        of "pin":             action = Pin;     actionCount += 1
        of "unpin":           action = Unpin;   actionCount += 1
        of "restore":         action = Restore; actionCount += 1
        of "c", "config":     action = Setup;   actionCount += 1
        of "help":            action = Help;    actionCount += 1
        else: displayHelp()
    of cmdArgument:
      args.add(key)
    else:
      displayHelp()
    if actionCount > 1 or (len(args) > 0 and action == Empty):
      displayHelp()

  case action
  of Setup, Help:
    discard
  else:
    configData = loadConfig()

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
      addons.sort((a, z) => int(a.time < z.time))
    for addon in addons:
      addon.line = line
      line += 1
  of Setup:
    setup(args)
  of Help:
    if args.len > 0:
      displayHelp(args[0])
    else:
      displayHelp()

  var processed, rest, final: seq[Addon]
  case action
  of Install, Update, Empty:
    processed = waitFor addons.installAll()
    assignIds(processed.concat(configData.addons))
  of Remove:
    processed = addons.map(uninstall)
  of Pin:
    processed = addons.map(pin)
  of Unpin:
    processed = addons.map(unpin)
  of Restore:
    processed = addons.restoreAll()
  of List:
    if addons.len == 0:
      quit()
    let maxName = addons[addons.map(a => a.name.len).maxIndex()].name.len
    let maxVersion = addons[addons.map(a => a.version.len).maxIndex()].version.len
    for a in addons:
      a.list(maxName + 2, maxVersion + 2)
    quit()
  of Help, Setup: discard

  rest = configData.addons.filter(addon => addon notin processed)
  final = if action != Remove: concat(processed, rest) else: rest

  writeAddons(final)
  writeConfig(configData)

  let t = configData.term
  if configData.log.len > 0:
    t.write(0, t.yMax, false, "\n")
  for item in configData.log:
    t.write(0, t.yMax, false, fgRed, &"\nError: ", fgCyan, item.addon.getName, "\n", resetStyle)
    t.write(4, t.yMax, false, fgDefault, item.msg, "\n", resetStyle)

main()
# https://github.com/Stanzilla/AdvancedInterfaceOptions
# https://github.com/Tercioo/Plater-Nameplates/tree/master
# https://gitlab.com/woblight/actionmirroringframe
# https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html

# https://www.tukui.org/elvui https://github.com/Stanzilla/AdvancedInterfaceOptions https://github.com/Tercioo/Plater-Nameplates/tree/master https://gitlab.com/woblight/actionmirroringframe https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html

# https://github.com/Tercioo/Plater-Nameplates/tree/master https://www.tukui.org/elvui https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html https://gitlab.com/woblight/actionmirroringframe

# https://www.wowinterface.com/downloads/info22095.html

import std/algorithm
import std/enumerate
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
import logger

const pollRate = 20

proc addonFromUrl(url: string): Option[Addon] =
  var urlmatch: array[2, string]
  let pattern = re"^(?:https?://)?(?:www\.)?(.+)\.(?:com|org)/(.+[^/\n])"
  let found = find(cstring(url), pattern, urlmatch, 0, len(url))
  if found == -1 or urlmatch[1] == "":
    echo &"Unable to determine addon from {url}."
  case urlmatch[0].toLower()
    of "curseforge":
      var m: array[1, string]
      let pattern = re"\/mods\/(\d+)\/"
      discard find(cstring(urlmatch[1]), pattern, m, 0, len(urlmatch[1]))
      if m[0] == "":
        echo &"Unable to determine addon from {url}."
        echo &"Make sure you have the corret URL. Go to the addon page, click download, and copy the 'try again' link."
      else:
        return some(newAddon(m[0], Curse))
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
      let p = re"^downloads\/info(\d+)-?"
      var m: array[1, string]
      discard find(cstring(urlmatch[1]), p, m, 0, len(urlmatch[1]))
      return some(newAddon(m[0], Wowint))
    else:
      discard
  return none(Addon)

proc validId(id: string, kind: AddonKind): bool =
  case kind
  of Curse, Wowint:
    return id.all(isDigit)
  of Tukui:
    return id == "tukui" or id == "elvui"
  of Github, Gitlab:
    var match: array[2, string]
    let pattern = re"^[^\/]*\/[^\/]*$"
    let found = find(cstring(id), pattern, match, 0, len(id))
    if not found == -1:
      return true
  else:
    return false
  return false

proc addonFromProject(s: string): Option[Addon] =
  var match: array[2, string]
  let pattern = re"^([^:]+):(.*)$"
  let found = find(cstring(s), pattern, match, 0, len(s))
  if found == -1:
    echo &"Unable to determine addon from {s}."
    return none(Addon)
  let source = match[0].toLower()
  let id = match[1].toLower()
  case source
  of "curse": 
    if validId(id, Curse):
      return some(newAddon(id, Curse))
  of "wowint":
    if validId(id, Wowint):
      return some(newAddon(id, Wowint))
  of "tukui":
    if validId(id, Tukui):
      return some(newAddon(id, Tukui))
  of "gitlab":
    if validId(id, Gitlab):
      return some(newAddon(id, Gitlab))
  of "github":
    if validId(id, Github):
      var match: array[2, string]
      let pattern = re"^(.+?)(?:@(.+))?$"
      discard find(cstring(id), pattern, match, 0, len(id))
      if match[1] == "":
        return some(newAddon(id, Github))
      else:
        return some(newAddon(match[0], GithubRepo, branch = some(match[1])))
  else: 
    discard
  return none(Addon)

proc parseAddon(s: string): Option[Addon] =
  var match: array[2, string]
  let pattern = re"^(?:https?:\/\/)?(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+.*[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?"
  let found = find(cstring(s), pattern, match, 0, len(s))
  if found == -1:
    return addonFromProject(s)
  else:
    return addonFromUrl(s)

proc addonFromId(id: int16): Option[Addon] =
  for a in configData.addons:
    if a.id == id: return some(a)
  return none(Addon)

proc setup(args: seq[string]) =
  if len(args) == 0:
    showConfig()
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
      setGithubToken(args[i + 1]); break
    else:
      echo &"Unrecognized option {item}\n"
      displayHelp("config")
  writeConfig(configData)
  quit()

proc processMessages(): seq[Addon] =
  var maxName {.global.} = 0
  var maxVersion {.global.} = 0
  var addons {.global.}: seq[Addon]
  while true:
    let (ok, addon) = addonChannel.tryRecv()
    if ok:
      case addon.state
      of Done, DoneFailed:
        result.add(addon)
      else:
        addons = addons.filter(a => a != addon)
        addons.add(addon)
        maxName = addons[addons.map(a => a.getName().len).maxIndex()].getName().len + 2
        maxVersion = addons[addons.map(a => a.getVersion().len).maxIndex()].getVersion().len + 2
        for addon in addons:
          addon.stateMessage(maxName, maxVersion)
    else:
      break

proc processLog() =
  while true:
    let (ok, logMessage) = logChannel.tryRecv()
    if ok:
      if logMessage.level <= configData.logLevel:
        log(logMessage)
    else:
      break





proc main() =
  configData = loadConfig(basic = true)
  logInit(configData.logLevel)
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
        of "n", "name":       action = Name;    actionCount += 1
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
        of "name":            action = Name;    actionCount += 1
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
  of Help, Setup:
    discard
  else:
    configData = loadConfig()

  var
    addons: seq[Addon]
    line = 0
    ids: seq[int16]
  case action
  of Install:
    var addonStrings: seq[string]
    var f: File
    if f.open(args[0]):
      while true:
        try: addonStrings.add(f.readline())
        except: break
      f.close()
    else:
      addonStrings = args
    for str in addonStrings:
      var opt = parseAddon(str)
      if opt.isSome:
        var addon = opt.get
        addon.line = line
        addon.action = Install
        addons.add(addon)
        line += 1
    if addons.len == 0:
      echo "Unable to parse any provided URLs"
      quit()
  of Update, Empty:
    for addon in configData.addons:
      addon.line = line
      addon.action = Install
      addons.add(addon)
      line += 1
    if addons.len == 0:
      displayHelp()
  of Remove, Restore, Pin, Unpin:
    for arg in args:
      try:
        ids.add(int16(arg.parseInt()))
      except:
        continue
    for id in ids:
      var opt = addonFromId(id)
      if opt.isSome:
        var addon = opt.get
        addon.line = line
        case action
        of Remove:  addon.action = Remove
        of Restore: addon.action = Restore
        of Pin:     addon.action = Pin
        of Unpin:   addon.action = Unpin
        else: discard
        addons.add(addon)
        line += 1
  of Name:
    var id: int16
    try:
      id = int16(args[0].parseInt())
    except:
      echo "Clear name override: lycan -n <id>"
      echo "  Add name override: lycan -n <id> <new name>"
      quit()
    var opt = addonFromId(id)
    if opt.isSome:
      let addon = opt.get
      if args.len == 1:
        addon.overrideName = none(string)
      elif args.len == 2:
        addon.overrideName = some(args[1])
      else:
        echo "TODO: show help for name overrides"
        quit()
      addon.action = Name
      addons.add(addon)
    else:
      echo "TODO: show help for name overrides 3"
  of List:
    addons = configData.addons
    if "t" in args or "time" in args:
      addons.sort((a, z) => int(a.time < z.time))
    addons.list()
  of Setup:
    setup(args)
  of Help:
    if args.len > 0:
      displayHelp(args[0])
    else:
      displayHelp()

  addonChannel.open()
  var thr = newSeq[Thread[Addon]](len = addons.len)
  for i, addon in enumerate(addons):
    addon.config = addr configData
    createThread(thr[i], workQueue, addon)

  var processed, failed, success, rest, final: seq[Addon]
  while true:
    processed &= processMessages()
    processLog()
    var runningCount = 0
    for t in thr:
      runningCount += int(t.running)
    if runningCount == 0:
      break
    sleep(pollRate)

  processLog()
  processed &= processMessages()
  thr.joinThreads()
  
  failed = processed.filter(a => a.state == DoneFailed)
  success = processed.filter(a => a.state == Done)

  let t = configData.term
  case action
  of Install:
    assignIds(success & configData.addons)
    # Using sugar here creates code that seg faults. This works fine so seems like a Nim bug to me
    success.apply(proc(a: Addon) = t.write(1, a.line, false, fgBlue, &"{a.id:<3}", resetStyle))
  else:
    discard

  rest = configData.addons.filter(addon => addon notin success)
  final = if action != Remove: success & rest else: rest

  writeAddons(final)
  writeConfig(configData)

  t.write(0, t.yMax, false, "\n")
  for addon in failed:
    t.write(0, t.yMax, false, fgRed, styleBright, &"\nError: ", fgCyan, addon.getName, "\n", resetStyle)
    t.write(4, t.yMax, false, fgWhite, addon.errorMsg, "\n", resetStyle)

main()
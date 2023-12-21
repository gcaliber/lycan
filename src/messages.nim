import std/colors
import std/options
import std/[strformat, strutils]
import std/times
import std/terminal

import config
import types
import term

const DARK_GREY: Color = Color(0x20_20_20)
const LIGHT_GREY: Color = Color(0x34_34_34)

proc getVersion*(addon: Addon): string =
  if addon.version.isEmptyOrWhitespace and addon.startVersion.isEmptyOrWhitespace: 
    return ""
  case addon.kind
  of GithubRepo: 
    if addon.version.isEmptyOrWhitespace: 
      return addon.startVersion[0 ..< 7]
    return addon.version[0 ..< 7]
  else:
    if addon.version.isEmptyOrWhitespace: 
      return addon.startVersion
    return addon.version

proc getName*(addon: Addon): string =
  if addon.overrideName.isSome: 
    return addon.overrideName.get
  if addon.name.isEmptyOrWhitespace:
    return $addon.kind & ':' & addon.project
  return addon.name

proc stateMessage*(addon: Addon, nameSpace, versionSpace: int) = 
  case addon.state
  of Failed, DoneFailed: return
  else: discard

  let
    t = configData.term
    indent = 1
    even = addon.line mod 2 == 0
    colors = if even: (fgWhite, DARK_GREY) else: (fgWhite, LIGHT_GREY)
    style = if not t.trueColor: (if even: styleBright else: styleReverse) else: styleBright
    branch = if addon.branch.isSome: addon.branch.get else: ""
    
    kind = case addon.kind
    of GithubRepo: "Github"
    else: $addon.kind

    stateColor = case addon.state
    of Checking, Parsing, Downloading, Installing, Restoring: fgCyan
    of FinishedUpdated, FinishedInstalled, FinishedUpToDate, Pinned, FinishedPinned, Removed, Unpinned, Renamed, Restored: fgGreen
    of Failed, NoBackup: fgRed
    else: fgWhite

    versionColor = case addon.state
    of Checking, Parsing, Downloading, Installing, Restoring, FinishedUpToDate, Pinned, FinishedPinned, Unpinned, Renamed, Failed, NoBackup: fgYellow
    of FinishedUpdated, FinishedInstalled, Removed, Restored, List: fgGreen
    else: fgWhite

  case addon.state
  of List:
    let pin = if addon.pinned: "!" else: " "
    let time = addon.time.format("dd-MM-yy hh:mm")
    t.write(1, addon.line, true, colors, style,
      fgBlue, &"{addon.id:<3}",
      fgWhite, &"{addon.getName().alignLeft(nameSpace)}",
      fgRed, pin,
      versionColor, &"{addon.getVersion().alignLeft(versionSpace)}",
      fgCyan, &"{kind:<6}",
      fgWhite, if addon.branch.isSome: "@" else: "",
      fgBlue, if addon.branch.isSome: &"{branch:<11}" else: &"{branch:<12}",
      fgWhite, &"{time}",
      resetStyle)
  else:
    t.write(indent, addon.line, true, colors, style,
      fgBlue, &"{addon.id:<3}", 
      stateColor, &"{$addon.state:<12}",
      fgWhite, &"{addon.getName().alignLeft(nameSpace)}", 
      versionColor, &"{addon.getVersion().alignLeft(versionSpace)}", 
      fgCyan, &"{kind:<6}", 
      fgWhite, if addon.branch.isSome: "@" else: "", 
      fgBlue, if addon.branch.isSome: &"{branch:<11}" else: &"{branch:<12}", 
      resetStyle)
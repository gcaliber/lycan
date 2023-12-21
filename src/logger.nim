import std/strformat
import std/os
import std/times

import types

var logFile: File
var logLevel: LogLevel
var logChannel*: Channel[LogMessage]
let logFileName = getCurrentDir() / "lycan.log"

proc logInit*(level: LogLevel) =
  logFile = open(logFileName, fmWrite)
  logFile.close()
  logFile = open(logFileName, fmAppend)
  logLevel = level
  if level != Off:
    logChannel.open()

proc time(): string =
  return now().format("HH:mm:ss'.'fff")

proc writeLog(msg: string) =
  logFile.write(msg)

proc log*(msg: string, level: LogLevel = Debug) =
  var loggedMessage: string
  case logLevel:
  of Debug, Fatal, Warning, Info:
    loggedMessage = &"[{time()}]:[{$level}] {msg}\n"
  of Off, None: discard
  writeLog(loggedMessage)

proc log*(msg: string, level: LogLevel, e: ref Exception) =
  var loggedMessage: string
  case logLevel:
  of Debug:
    loggedMessage = &"[{time()}]:[{$level}]\n{e.name}: {e.msg}\n{e.getStackTrace()}\n"
  of Fatal, Warning, Info:
    loggedMessage = &"[{time()}]:[{$level}] {e.name}: {e.msg}\n"
  of Off, None: discard
  writeLog(loggedMessage)

proc log*(logMessage: LogMessage) =
  if logMessage.e.isNil:
    log(logMessage.msg, logMessage.level)
  else:
    log(logMessage.msg, logMessage.level, logMessage.e)
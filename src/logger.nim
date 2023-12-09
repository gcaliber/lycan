import std/strformat
import std/locks
import std/os
import std/times

import types

var logFile: File
var logLock: Lock
var logLevel: LogLevel
var logChannel*: Channel[LogMessage]

proc logInit*(level: LogLevel) =
  logLevel = level
  if level != Off:
    logChannel.open()
    let logFileName = getCurrentDir() / "lycan.log"
    logFile = open(logFileName, fmWrite)
    initLock(logLock)

proc time(): string =
  return now().format("HH:mm:ss'.'ffffff")

proc writeLog(msg: string) =
  acquire(logLock)
  logFile.write(msg)
  release(logLock)

proc log(msg: string, level: LogLevel) =
    var loggedMessage: string
    case logLevel:
    of Debug, Fatal, Warning, Info:
      loggedMessage = &"[{time()}]:[{$level}] {msg}\n"
    of Off: discard
    writeLog(loggedMessage)

proc log(msg: string, level: LogLevel, e: ref Exception) =
    var loggedMessage: string
    case logLevel:
    of Debug:
      loggedMessage = &"[{time()}]:[{$level}]\n{e.name}: {e.msg}\n{e.getStackTrace()}\n"
    of Fatal, Warning, Info:
      loggedMessage = &"[{time()}]:[{$level}] {e.name}: {e.msg}\n"
    of Off: discard
    writeLog(loggedMessage)

proc log*(logMessage: LogMessage) =
  if logMessage.e.isNil:
    log(logMessage.msg, logMessage.level)
  else:
    log(logMessage.msg, logMessage.level, logMessage.e)
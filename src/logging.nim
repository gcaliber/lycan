import std/os

import types
import config

proc log*(msg: string, level: LogLevel) =
  if configData.logLevel.ord >= level.ord:
    case configData.logLevel:
    of Debug: discard # stack trace
    of Fatal, Warning, Info: discard # error name & message
    of Off: discard

proc log*(e: CatchableError, level: LogLevel) =
  if configData.logLevel.ord >= level.ord:
    case configData.logLevel:
    of Debug: discard # stack trace
    of Fatal, Warning, Info: discard # error name & message
    of Off: discard
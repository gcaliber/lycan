import std/colors
import std/exitprocs
import std/terminal
import std/macros

import types

proc moveTo(t: Term, x, y: int) =
  let
    xOffset = t.x - x
    yOffset = t.y - y

  if xOffset > 0:
    t.f.cursorBackward(count = xOffset)
  elif xOffset < 0:
    t.f.cursorForward(count = abs(xOffset))

  if yOffset > 0:
    t.f.cursorUp(count = yOffset)
  elif yOffset < 0:
    var n = abs(yOffset)
    while n < t.yMax: 
      t.f.cursorDown()
      n += 1
    while n < y:
      t.f.write("\n")
      n += 1
# I need to take terminal height into account somehow
# sorta close to being right other than that
  t.x = x
  t.y = y

proc updatePos(t: Term, s: string) =
  for c in s:
    case c
    of '\t': t.x += 4
    of '\n': t.x = 0; t.y += 1
    of '\r': t.x = 0
    else:    t.x += 1
  
  let h = terminalHeight()
  if t.y > h: t.y = h
  if t.y > t.yMax: t.yMax = t.y


proc write*(t: Term, s: string) =
  t.f.write(s)
  t.f.flushFile()
  t.updatePos(s)

proc writeLine*(t: Term, s: string) =
  t.f.write(s)
  t.f.write("\n")
  t.f.flushFile()
  t.updatePos(s)
  t.updatePos("\n")

proc write*(t: Term, x, y: int, erase: bool, s: string) =
  t.moveTo(x, y)
  if erase: t.f.eraseLine()
  t.write(s)

proc writeLine*(t: Term, x, y: int, erase: bool, s: string) =
  t.moveTo(x, y)
  if erase: t.f.eraseLine()
  t.writeLine(s)

proc eraseLine(t: Term, erase: bool) =
  if erase: t.f.eraseLine()

proc exitTerm(t: Term): proc() =
  return proc() =
    t.writeLine(0, t.yMax, false, "\n")
    resetAttributes()
    showCursor()

proc termInit*(f: File = stdout): Term =
  enableTrueColors()
  hideCursor()
  result = new(Term)
  result.f = f
  result.trueColor = isTrueColorSupported()
  let exit = exitTerm(result)
  exitprocs.addExitProc(exit)

template writeProcessArg(t: Term, s: string) =
  t.write(s)

template writeProcessArg(t: Term, style: Style) =
  t.f.setStyle({style})

template writeProcessArg(t: Term, style: set[Style]) =
  t.f.setStyle(style)

template writeProcessArg(t: Term, color: ForegroundColor) =
  t.f.setForegroundColor(color)

template writeProcessArg(t: Term, color: BackgroundColor) =
  t.f.setBackgroundColor(color)

template writeProcessArg(t: Term, colors: tuple[fg, bg: Color]) =
  let (fg, bg) = colors
  t.f.setForegroundColor(fg)
  t.f.setBackgroundColor(bg)

template writeProcessArg(t: Term, colors: tuple[fg: ForegroundColor, bg: Color]) =
  let (fg, bg) = colors
  t.f.setForegroundColor(fg)
  t.f.setBackgroundColor(bg)

template writeProcessArg(t: Term, colors: tuple[fg: Color, bg: BackgroundColor]) =
  let (fg, bg) = colors
  t.f.setForegroundColor(fg)
  t.f.setBackgroundColor(bg)

template writeProcessArg(t: Term, cmd: TerminalCmd) =
  when cmd == resetStyle:
    t.f.resetAttributes()

macro write*(t: Term, args: varargs[typed]): untyped =
  result = newNimNode(nnkStmtList)
  if args.len >= 3 and args[0].typeKind() == ntyInt and args[1].typeKind() == ntyInt:
    let x = args[0]
    let y = args[1]
    result.add(newCall(bindSym"moveTo", t, x, y))
    if args.len >= 4 and args[2].typeKind() == ntyBool:
      let erase = args[2]
      result.add(newCall(bindSym"eraseLine", t, erase))
    for i in 3..<args.len:
      let item = args[i]
      result.add(newCall(bindSym"writeProcessArg", t, item))
  else:
    for item in args.items:
      result.add(newCall(bindSym"writeProcessArg", t, item))


when isMainModule:
  import std/strformat

  let t = termInit()
  for line in 5 .. 10:
    t.write(0, line, true, &"{line}")
    # t.write(0, line, true, fgWhite, &"{line}", resetStyle)
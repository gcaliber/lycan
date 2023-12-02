import std/colors
import std/exitprocs
import std/terminal
import std/macros

import types

proc moveTo(t: Term, x, y: int, erase: bool) =
  let yOffset = t.y - y
  var newLine = false

  if yOffset > 0:
    t.f.cursorUp(yOffset)
  elif yOffset < 0:
    var i = t.y
    while i < t.yMax and i < y:
      t.f.cursorDown()
      i += 1
    if i < y: newLine = true
    while i < y:
      t.f.write("\n")
      i += 1
      
  if erase or newLine:
    t.f.eraseLine()
    t.f.cursorForward(x)
  else:
    let xOffset = t.x - x
    if xOffset > 0:
      t.f.cursorBackward(xOffset)
    elif xOffset < 0:
      t.f.cursorForward(abs(xOffset))

  t.x = x
  t.y = y

  let h = terminalHeight()
  if t.y > h: t.y = h
  if t.y > t.yMax: t.yMax = t.y
  

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
  t.moveTo(x, y, erase)
  t.write(s)

proc writeLine*(t: Term, x, y: int, erase: bool, s: string) =
  t.moveTo(x, y, erase)
  t.writeLine(s)

proc exitTerm(t: Term): proc() =
  return proc() =
    # t.writeLine(0, t.yMax, false, "")
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
  if args.len >= 4 and args[0].typeKind() == ntyInt and args[1].typeKind() == ntyInt and args[2].typeKind() == ntyBool:
    let x = args[0]
    let y = args[1]
    let erase = args[2]
    result.add(newCall(bindSym"moveTo", t, x, y, erase))
    for i in 3..<args.len:
      let item = args[i]
      result.add(newCall(bindSym"writeProcessArg", t, item))
  else:
    for item in args.items:
      result.add(newCall(bindSym"writeProcessArg", t, item))
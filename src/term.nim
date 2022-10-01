import std/colors
import std/exitprocs
import std/strformat
import std/strutils
import std/terminal
import std/macros

import types

var t = new(Term)
enableTrueColors()
hideCursor()

proc moveTo(x, y: int) =
  let
    xOffset = t.x - x
    yOffset = t.y - y

  if xOffset != 0:
    if xOffset > 0:
      stdout.cursorBackward(count = xOffset)
    else:
      stdout.cursorForward(count = abs(xOffset))

  if yOffset != 0:
    if yOffset > 0:
      stdout.cursorUp(count = yOffset)
    else:
      stdout.cursorDown(count = abs(yOffset))
  
  t.x = x
  t.y = y

proc update(s: string) =
  for c in s:
    case c
    of '\t': 
      t.x += 4
    of '\n': 
      t.x = 0
      t.y += 1
    of '\r':
      t.x = 0
    else:
      t.x += 1
  
  let h = terminalHeight()
  if t.y > h:
    t.y = h
  if t.y > t.yMax:
    t.yMax = t.y


proc writeTerm(f: File, s: string) =
  f.write(s)
  update(s)

proc writeStyledTerm(f: File, s:string, style: set[Style]) =
  f.styledWrite(s, style)
  update(s)

proc write*(f: File, s: string, x: int = t.x, y: int = t.y, erase: bool = false) =
  moveTo(x, y)
  if erase:
    f.eraseLine()
  f.writeTerm(s)

proc writeStyled*(f: File, s: string, style: set[Style] = {styleBright}, x: int = t.x, y: int = t.y, erase: bool = false) =
  moveTo(x, y)
  if erase:
    f.eraseLine()
  f.writeStyledTerm(s, style)

proc writeLine*(f: File, s: string, x: int = t.x, y: int = t.y, erase: bool = false) =
  f.write(s, x, y, erase = erase)
  f.writeTerm("\n")

proc writeStyledLine*(f: File, s: string, style: set[Style] = {styleBright}, x: int = t.x, y: int = t.y, erase: bool = false) =
  f.writeStyled(s, style, x, y, erase)
  f.writeTerm("\n")


proc reset() =
  stdout.writeLine(0, t.yMax, false, "")
  stdout.resetAttributes()
  showCursor()

exitprocs.addExitProc(reset)

# template styledEchoProcessArg(f: File, x, y: int, erase: bool, s: string) = writeTerm(f, x, y, erase, s)
# template styledEchoProcessArg(f: File, x, y: int, erase: bool, style: Style) = setStyle(f, {style})
# template styledEchoProcessArg(f: File, x, y: int, erase: bool, style: set[Style]) = setStyle f, style
# template styledEchoProcessArg(f: File, x, y: int, erase: bool, color: ForegroundColor) =
#   setForegroundColor f, color
# template styledEchoProcessArg(f: File, x, y: int, erase: bool, color: BackgroundColor) =
#   setBackgroundColor f, color
# template styledEchoProcessArg(f: File, x, y: int, erase: bool, color: Color) =
#   setTrueColor f, color
# template styledEchoProcessArg(f: File, x, y: int, erase: bool, cmd: TerminalCmd) =
#   when cmd == resetStyle:
#     resetAttributes(f)
#   elif cmd in {fgColor, bgColor}:
#     let term = getTerminal()
#     term.fgSetColor = cmd == fgColor

# macro styledWriteTerm*(f: File, x, y: int, erase: bool, m: varargs[typed]): untyped =
#   var reset = false
#   result = newNimNode(nnkStmtList)

#   for i in countup(0, m.len - 1):
#     let item = m[i]
#     case item.kind
#     of nnkStrLit..nnkTripleStrLit:
#       if i == m.len - 1:
#         # optimize if string literal is last, just call write
#         result.add(newCall(bindSym"writeTerm", f, x, y, erase, item))
#         if reset: result.add(newCall(bindSym"resetAttributes", f))
#         return
#       else:
#         # if it is string literal just call write, do not enable reset
#         result.add(newCall(bindSym"writeTerm", f, x, y, erase, item))
#     else:
#       result.add(newCall(bindSym"styledEchoProcessArg", f, x, y, erase, item))
#       reset = true
#   if reset: result.add(newCall(bindSym"resetAttributes", f))

# template styledWriteLineTerm*(f: File, x, y: int, erase: bool, args: varargs[untyped]) =
#   styledWriteTerm(f, x, y, erase, args)
#   writeTermReal(f, "\n")
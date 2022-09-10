import os, strutils
import illwill

# tb.write(x, y, "some text ", "comma separted")

const
  DEFAULT_COMPLETE_CHAR = '='
  DEFAULT_INCOMPLETE_CHAR = '.'
  DEFAULT_COMPLETE_HEAD = '>'
  DEFAULT_LEFT_DELIM = '['
  DEFAULT_RIGHT_DELIM = ']'

type
  ProgressBar* = ref object
    tb: TerminalBuffer
    X: Natural
    Y: Natural
    width: Natural
    total: Natural
    step: Natural
    current: Natural
    leftDelim: char
    rightDelim: char
    complete: char
    incomplete: char
    incompleteHead: char

proc newProgressBar*(tb: TerminalBuffer, x, y: Natural, width: Natural = 60, 
  total: Natural = 100, step: Natural = 1, left: char = DEFAULT_LEFT_DELIM,
  right: char = DEFAULT_RIGHT_DELIM, complete: char = DEFAULT_COMPLETE_CHAR, 
  head: char = DEFAULT_COMPLETE_HEAD, incomplete: char = DEFAULT_INCOMPLETE_CHAR
): ProgressBar =
  result = ProgressBar(
    tb: tb,
    X: x,
    Y: y,
    width: width,
    total: total,
    step: step,
    current: 0,
    leftDelim: left,
    rightDelim: right,
    complete: complete,
    incomplete: incomplete,
    incompleteHead: head
  )

proc isComplete*(pb: ProgressBar): bool =
  ## Check whether the progress bar is complete.
  result = pb.current == pb.total

proc currentPosition(pb: ProgressBar): int =
  ## Get the progress bar's current position.
  result = toInt(((pb.current * pb.width) / pb.total))

proc percent*(pb: ProgressBar): float =
  ## Get the progress bar's current completion percentage.
  result = toFloat(pb.current) / (toFloat(pb.total) / 100.0)

proc print(pb: ProgressBar) =
  ## Print the progress bar to TerminalBuffer.
  let
    position = pb.currentPosition()
    isComplete = pb.isComplete()

  var completeBar = pb.complete.repeat(position - 1)
  if isComplete:
    completeBar.add(pb.complete)
  else:
    completeBar.add(pb.incompleteHead)

  let
    incompleteBar = pb.incomplete.repeat(pb.width - position)
    percentage = formatFloat(pb.percent(), ffDecimal, 2) & "%"

  pb.tb.write(pb.X, pb.Y, pb.leftDelim & completeBar & incompleteBar & pb.rightDelim & " " & percentage)

  # write(pb.output, "\r" & pb.leftDelim & completeBar & incompleteBar & pb.rightDelim & " " & percentage)
  # flushFile(pb.output)

  # if isComplete:
  #   pb.output.writeLine("")

proc start*(pb: ProgressBar) =
  ## Start the progress bar. This will write the empty (0%) bar to the screen, which may not always be desired.
  if pb.current == 0:
    pb.print()

proc tick*(pb: var ProgressBar, count: int = 1) =
  ## Increment the progress bar by `count` places.
  pb.current += count
  if pb.current < 0:
    pb.current = 0
  if pb.current > pb.total:
    pb.current = pb.total
  pb.print()

proc increment*(pb: var ProgressBar) =
  ## Increment the progress bar by one step.
  pb.tick(pb.step)

proc set*(pb: var ProgressBar, pos: int) =
  ## Set the progress bar's current position to `pos`.
  pb.current = pos
  pb.print()

proc finish*(pb: var ProgressBar) =
  ## Set the progress bar's current position to completion.
  if pb.current != pb.total:
    pb.set(pb.total)

when(isMainModule):
  proc exitProc() {.noconv.} =
    illwillDeinit()
    showCursor()
    quit(0)

  illwillInit(fullscreen=false)
  setControlCHook(exitProc)
  hideCursor()

  var tb = newTerminalBuffer(terminalWidth(), terminalHeight())
  var pb = newProgressBar(tb, 0, 0, total = 10, width = 10)
  var pb2 = newProgressBar(tb, 0, 1, total = 20)

  while true:
    var key = getKey()
    case key
    of Key.None: discard
    of Key.Escape, Key.Q: exitProc()
    else:
      pb.tick()
      pb2.tick()
    tb.display()
    sleep(20)
import std/strutils

const indent: int = 2

proc beautify*(j: string): string = 
  var s: string
  var d = indent

  var newline = false
  var insideSeq = false
  for c in j:
    case c
    of '{':
      if newline:
        s = s & c & '\n' & ' '.repeat(d + indent)
        newline = false
      else:
        s = s & '\n' & ' '.repeat(d) & c & '\n' & ' '.repeat(d + indent)
        newline = true
      d += indent
    of '}':
      d -= indent
      s = s & '\n' & ' '.repeat(d) & c
      newline = true
    of ',':
      if insideSeq:
        s = s & c & ' '
        newline = false
      else:
        s = s & c & '\n' & ' '.repeat(d)
        newline = true
    of '[':
      s = s & c
      if d != indent:
        insideSeq = true
    of ']':
      if newline:
        s = s & '\n' & c
      else: 
        s = s & c
      if d != indent:
        insideSeq = false
    else:
      s = s & c
      newline = false

  return s
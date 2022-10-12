import std/strutils

proc indent(s: var string, n: int) =
  s = s & ' '.repeat(n)

proc beautify*(json: string, n: int = 2): string =
  var s: string
  var depth = 0

  for i in 0 ..< len(json):
    let c = json[i]
    var inString = false
    
    if not inString:
      case c
      of '{', '[':
        s = s & c & '\n'
        depth += n
        s.indent(depth)
      of '}', ']':
        s = s & '\n'
        depth -= n
        s.indent(depth)
        s = s & c
      of ',':
        s = s & c & '\n'
        s.indent(depth)
      of ':':
        s = s & c & ' '
      of '"':
        s = s & c
        inString = true
      else:
        s = s & c
    else:
      case c
      of '"':
        s = s & c
        if i > 0 and json[i - 1] != '\\':
          inString = false
      else:
        s = s & c

  return s
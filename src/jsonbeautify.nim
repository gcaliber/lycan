from std/strutils import repeat

proc indent(s: var string, n: int) =
  s = s & ' '.repeat(n)

proc beautify*(json: string, n: int = 2): string =
  var 
    s: string
    depth = 0
    inString = false

  for i in 0 ..< len(json):
    let c = json[i]
    
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
        if i > 1 and json[i - 1] != '\\' and json[i - 2] != '\\':
          inString = false
      else:
        s = s & c

  return s
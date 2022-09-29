import std/json
import std/options

type
  Action* = enum
    doInstall, doUpdate, doRemove, doList, doPin, doUnpin, doRestore, doNothing

  Config* = object
    mode*: string
    tempDir*: string
    installDir*: string
    addonJsonFile*: string
    tukuiCache*: JsonNode
    addons*: seq[Addon]

  AddonKind* = enum
    Github,
    GithubRepo,
    Gitlab,
    TukuiMain,
    TukuiAddon,
    Wowint,

  Addon* = ref object
    project*: string
    branch*: Option[string]
    name*: string
    kind*: AddonKind
    version*: string
    id*: int16
    dirs*: seq[string]
    downloadUrl*: string
    filename*: string
    extractDir*: string
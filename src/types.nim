import std/json
import std/options

type
  Action* = enum
    DoInstall, DoUpdate, DoRemove, DoList, DoPin, DoUnpin, DoRestore

  AddonState* = enum
    Checking = "Checking",
    Parsing = "Parsing",
    Downloading = "Downloading",
    Installing = "Installing",
    Finished = "Finished",
    AlreadyUpdated = "Finished",
    Failed = "Failed",
    # BackingUp = "Backing up",
    Pinned = "Pinned",
    Unpinned = "Unpinned",
    Removed = "Removed",
  
  AddonKind* = enum
    Github, GithubRepo, Gitlab, TukuiMain, TukuiAddon, Wowint,
  
  Config* = object
    mode*: string
    tempDir*: string
    installDir*: string
    addonJsonFile*: string
    tukuiCache*: JsonNode
    addons*: seq[Addon]
    term*: Term

  Addon* = ref object
    state*: AddonState
    project*: string
    branch*: Option[string]
    name*: string
    kind*: AddonKind
    version*: string
    oldVersion*: string
    id*: int16
    dirs*: seq[string]
    downloadUrl*: string
    filename*: string
    extractDir*: string
    line*: int
    pinned*: bool

  Term* = ref object
    f*: File
    trueColor*: bool
    x*: int
    y*: int
    yMax*: int

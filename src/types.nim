import std/json
import std/options
import std/times

type
  Action* = enum
    Install, Update, Remove, List, Pin, Unpin, Restore, Setup, Empty

  Mode* = enum
    Retail = "retail",
    Classic = "classic",
    Vanilla = "clasic_era",
    None = "",

  AddonState* = enum
    Checking = "Checking",
    Parsing = "Parsing",
    Downloading = "Downloading",
    Installing = "Installing",
    FinishedInstalled = "Installed",
    FinishedUpdated = "Updated",
    FinishedPinned = "Pinned",
    FinishedAlreadyCurrent = "Finished",
    Failed = "Failed",
    Restoring = "Restoring",
    Restored = "Restored",
    Pinned = "Pinned",
    Unpinned = "Unpinned",
    Removed = "Removed",
    NoBackup = "Not Found"
  
  AddonKind* = enum
    Github, GithubRepo, Gitlab, TukuiMain, TukuiAddon, Wowint,

  Error* = object
    addon*: Addon
    msg*: string

  Config* = object
    mode*: Mode
    tempDir*: string
    installDir*: string
    backupEnabled*: bool
    backupDir*: string
    addonJsonFile*: string
    tukuiCache*: JsonNode
    addons*: seq[Addon]
    term*: Term
    log*: seq[Error]
    local*: bool
    githubToken*: string

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
    time*: DateTime

  Term* = ref object
    f*: File
    trueColor*: bool
    x*: int
    y*: int
    yMax*: int

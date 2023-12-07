import std/json
import std/options
import std/times

type
  Action* = enum
    Install, Update, Remove, List, Pin, Unpin, Restore, Setup, Empty, Help

  LogLevel* = enum
    Off, Fatal, Warning, Info, Debug

  Mode* = enum
    Retail = "retail",
    Vanilla = "classic_era",
    Classic = "classic"
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
    Done = "Done"
    DoneFailed = "Failed"
  
  AddonKind* = enum
    Github, GithubRepo, Gitlab, Tukui, Wowint, Curse

  Config* = ref object
    mode*: Mode
    tempDir*: string
    installDir*: string
    backupEnabled*: bool
    backupDir*: string
    addonJsonFile*: string
    tukuiCache*: JsonNode
    addons*: seq[Addon]
    term*: Term
    local*: bool
    githubToken*: string
    logLevel*: LogLevel

  Addon* = ref object
    action*: Action
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
    config*: ptr Config
    errorMsg*: string

  Term* = ref object
    f*: File
    trueColor*: bool
    x*: int
    y*: int
    yMax*: int
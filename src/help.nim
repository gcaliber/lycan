import std/terminal

import config
import term

proc displayHelp*(option: string = "") =
  let t = configData.term

  t.write(6, t.yMax, false, fgGreen, "Lycan", fgYellow, " 0.1.0", fgDefault, " by inverimus\n", resetStyle)
  
  case option
  of "a", "i", "add", "install":
    let x = 2
    let x2 = 4
    t.write(x, t.yMax, true, fgWhite, "-a, --add <args>", "\n")
    t.write(x, t.yMax, true, fgWhite, "-i, --install <args>", "\n\n")
    t.write(x, t.yMax, true, fgDefault, "Installs an addon from a url. Supported sites are github releases, github repositories, tukui, wowinterface, and gitlab releases. Including 'http://' will work but is not required.\n\n")
    t.write(x, t.yMax, true, "EXAMPLES:", "\n")
    t.write(x2, t.yMax, true, "lycan -i https://github.com/Stanzilla/AdvancedInterfaceOptions", "\n")
    t.write(x2, t.yMax, true, "  Installs the latest release.", "\n")
    t.write(x2, t.yMax, true, "lycan -i https://github.com/Tercioo/Plater-Nameplates/tree/master", "\n")
    t.write(x2, t.yMax, true, "  Installs the latest commit from branch \"master\".", "\n")
    t.write(x2, t.yMax, true, "lycan -i https://gitlab.com/siebens/legacy/autoactioncam", "\n")
    t.write(x2, t.yMax, true, "lycan -i https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html", "\n")
    t.write(x2, t.yMax, true, "lycan -i https://www.tukui.org/download.php?ui=elvui", "\n")
    t.write(x2, t.yMax, true, "lycan -i https://www.tukui.org/addons.php?id=209", "\n")
    quit()

  of "c", "config":
    let x = 2
    let x2 = 4
    t.write(x, t.yMax, true, fgWhite, "-c, --config [options]", "\n\n")
    t.write(x, t.yMax, true, fgDefault, "Set lycan configuration options including mode, wow path, and backups. If no options are provided, displays the current options.\n\n")
    t.write(x, t.yMax, true, fgGreen, "OPTIONS:", "\n")
    t.write(x2, t.yMax, true, fgDefault, "[m|mode] [retail|classic|vanilla]  Set the mode to retail, classic, or vanilla.\n")
    t.write(x2, t.yMax, true, "  Can also be abbreviated as the first letter\n\n")
    t.write(x2, t.yMax, true, "path   Set the path of the World of Warcraft directory for the current mode.\n\n")
    t.write(x2, t.yMax, true, "backup [path|on|off]   Path sets the backup directory. The default backs up to a folder alongside the WoW AddOns folder.\n")
    t.write(x2, t.yMax, true, "  On or off enables or disables backups respectively.\n")
    t.write(x2, t.yMax, true, "github <token>   Sets a github personal access token. This may be required if you get 403 forbidden responses with github.\n")
    t.write(x2, t.yMax, true, "  On or off enables or disables backups respectively.\n")
    t.write(x, t.yMax, true, fgGreen, "EXAMPLES:", "\n")
    t.write(x2, t.yMax, true, fgDefault, "lycan -c m w", "\n")
    t.write(x2, t.yMax, true, "  Change the mode to Wrath of the Lich King Classic", "\n")
    t.write(x2, t.yMax, true, "lycan path \"C:\\Program Files (x86)\\World of Warcraft\"", "\n")
    t.write(x2, t.yMax, true, "lycan backup off", "\n")
    t.write(x2, t.yMax, true, "  Disable backing up addons. Restore feature will be disabled for any addons installed or updated while off.", "\n")
    t.write(x2, t.yMax, true, "lycan backup \"D:\\wow addon backup\"", "\n")
    t.write(x2, t.yMax, true, "  Change the backup directory to \"D:\\wow addon backup\"  Existing backups will be moved to the new location.", "\n")
    quit()

  of "l", "list":
    let x = 2
    let x2 = 4
    t.write(x, t.yMax, true, fgWhite, "-l, --list [options]", "\n\n")
    t.write(x, t.yMax, true, fgDefault, "Lists installed addons. The default order is alphabetical.\n\n")
    t.write(x, t.yMax, true, fgGreen, "OPTIONS:", "\n")
    t.write(x2, t.yMax, true, fgDefault, "[t|time]   Sort by most recent install install/update date and time.\n\n")
    t.write(x, t.yMax, true, fgGreen, "EXAMPLES:", "\n")
    t.write(x2, t.yMax, true, fgDefault, "lycan -l time", "\n")
    t.write(x2, t.yMax, true, "lycan -lt", "\n")
    quit()

  else:
    let x = 2
    let x2 = 30
    t.write(x, t.yMax, true, fgWhite, "-a, --add <args>")
    t.write(x2, t.yMax, false, fgDefault, "Install an addon. <args> is a list of urls seperated by spaces.", "\n")
    t.write(x, t.yMax, true, fgWhite, "-c, --config [options]")
    t.write(x2, t.yMax, false, fgDefault, "Configuration options. lycan --help config for more info", "\n")
    t.write(x, t.yMax, true, fgWhite, "    --help")
    t.write(x2, t.yMax, false, fgDefault, "Display this message.", "\n")
    t.write(x, t.yMax, true, fgWhite, "-i, --install <args>")
    t.write(x2, t.yMax, false, fgDefault, "Alias for --add", "\n")
    t.write(x, t.yMax, true, fgWhite, "-l, --list [options]")
    t.write(x2, t.yMax, false, fgDefault, "List installed addons sorted by name.", "\n")
    t.write(x, t.yMax, true, fgWhite, "    --pin <ids>")
    t.write(x2, t.yMax, false, fgDefault, "Pin addon to current version. Addon will not be updated until unpinned.", "\n")
    t.write(x, t.yMax, true, fgWhite, "-r, --remove <ids>")
    t.write(x2, t.yMax, false, fgDefault, "Remove installed addons by id number", "\n")
    t.write(x, t.yMax, true, fgWhite, "    --restore <ids>")
    t.write(x2, t.yMax, false, fgDefault, "Restore addons to the version prior to last update.", "\n")
    t.write(x, t.yMax, true, fgWhite, "    --unpin")
    t.write(x2, t.yMax, false, fgDefault, "Unpin addon to restore updates.", "\n")
    t.write(x, t.yMax, true, fgWhite, "-u, --update")
    t.write(x2, t.yMax, false, fgDefault, "Update installed addons. Default if no arguments are given.", "\n")
    quit()
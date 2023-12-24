import std/terminal

import term

const 
  version = "0.1.0"
  ind2 = 2
  ind4 = 4
  ind6 = 6
  ind30 = 30

proc displayHelp*(option: string = "") =
  let t = termInit()
  
  case option
  of "a", "i", "add", "install":
    t.write(ind2, t.yMax, true, fgCyan, "-a, --add <args>", "\n")
    t.write(ind2, t.yMax, true, fgCyan, "-i, --install <args>", "\n\n")
    t.write(ind2, t.yMax, true, fgWhite, "Installs an addon from a url, addon short name, or file. Supported sites are github releases, github repositories, gitlab releases, tukui, wowinterface, and curseforge.\n\n")
    t.write(ind2, t.yMax, true, fgGreen, "EXAMPLES:", "\n")
    t.write(ind4, t.yMax, true, fgWhite, "lycan -i https://github.com/Stanzilla/AdvancedInterfaceOptions", "\n")
    t.write(ind4, t.yMax, true, fgWhite, "lycan -i github:Stanzilla/AdvancedInterfaceOptions", "\n")
    t.write(ind4, t.yMax, true, "lycan -i https://github.com/Tercioo/Plater-Nameplates/tree/master", "\n")
    t.write(ind4, t.yMax, true, "lycan -i github:Tercioo/Plater-Nameplates@master", "\n")
    t.write(ind6, t.yMax, true, fgYellow, "Including the branch will install and track the latest commit to that branch instead of releases.", "\n")
    t.write(ind4, t.yMax, true, fgWhite, "lycan -i https://gitlab.com/woblight/actionmirroringframe", "\n")
    t.write(ind4, t.yMax, true, fgWhite, "lycan -i gitlab:woblight/actionmirroringframe", "\n")
    t.write(ind4, t.yMax, true, "lycan -i https://www.wowinterface.com/downloads/info24608-HekiliPriorityHelper.html", "\n")
    t.write(ind4, t.yMax, true, "lycan -i wowint:24608", "\n")
    t.write(ind4, t.yMax, true, "lycan -i https://www.tukui.org/elvui", "\n")
    t.write(ind4, t.yMax, true, "lycan -i tukui:elvui", "\n")
    t.write(ind4, t.yMax, true, "lycan -i https://www.curseforge.com/api/v1/mods/334372/files/4956577/download", "\n")
    t.write(ind4, t.yMax, true, "lycan -i curse:334372", "\n")
    t.write(ind6, t.yMax, true, fgYellow, "To get this url/id, go the addon page and click download then copy the link for 'try again.'", "\n")
    t.write(ind4, t.yMax, true, fgWhite, "lycan -i <filename>", "\n")
    t.write(ind6, t.yMax, true, fgYellow, "This will try to install each line of the file as a separate addon.", "\n", resetStyle)

  of "c", "config":
    t.write(ind2, t.yMax, true, fgCyan, "-c, --config [options]", "\n\n")
    t.write(ind2, t.yMax, true, fgWhite, "Set lycan configuration options including mode, wow path, and backups. If no options are provided, displays the current options.\n\n")
    t.write(ind2, t.yMax, true, fgGreen, "OPTIONS:", "\n")
    t.write(ind4, t.yMax, true, fgWhite, "[m|mode] [retail|classic|vanilla]  Set the mode to retail, classic (Wrath), or vanilla (Classic Era).\n")
    t.write(ind6, t.yMax, true, "Can also be abbreviated as the first letter\n\n")
    t.write(ind4, t.yMax, true, "path   Set the path of the World of Warcraft directory for the current mode.\n\n")
    t.write(ind4, t.yMax, true, "backup [path|on|off]   Path sets the backup directory. The default backs up to a folder alongside the WoW AddOns folder.\n")
    t.write(ind6, t.yMax, true, "On or off enables or disables backups respectively.\n")
    t.write(ind4, t.yMax, true, "github <token>   Sets a github personal access token. This may be required if you get 403 forbidden responses with github.\n")
    t.write(ind6, t.yMax, true, "On or off enables or disables backups respectively.\n")
    t.write(ind2, t.yMax, true, fgGreen, "EXAMPLES:", "\n")
    t.write(ind4, t.yMax, true, fgWhite, "lycan -c m w", "\n")
    t.write(ind6, t.yMax, true, "Change the mode to Wrath of the Lich King Classic", "\n")
    t.write(ind4, t.yMax, true, "lycan path \"C:\\Program Files (ind286)\\World of Warcraft\"", "\n")
    t.write(ind4, t.yMax, true, "lycan backup off", "\n")
    t.write(ind6, t.yMax, true, "Disable backing up addons. Restore feature will be disabled for any addons installed or updated while off.", "\n")
    t.write(ind4, t.yMax, true, "lycan backup \"D:\\wow addon backup\"", "\n")
    t.write(ind6, t.yMax, true, "Change the backup directory to \"D:\\wow addon backup\"  Existing backups will be moved to the new location.", "\n")

  of "l", "list":
    t.write(ind2, t.yMax, true, fgCyan, "-l, --list [options]", "\n\n")
    t.write(ind2, t.yMax, true, fgWhite, "Lists installed addons. The default order is alphabetical.\n\n")
    t.write(ind2, t.yMax, true, fgGreen, "OPTIONS:", "\n")
    t.write(ind4, t.yMax, true, fgWhite, "[t|time]   Sort by most recent install or update date and time.\n\n")
    t.write(ind2, t.yMax, true, fgGreen, "EXAMPLES:", "\n")
    t.write(ind4, t.yMax, true, fgWhite, "lycan -l time", "\n")
    t.write(ind4, t.yMax, true, "lycan -lt", "\n")

  else:
    t.write(ind2, t.yMax, false, fgGreen, "Lycan", fgYellow, " ", version, fgWhite, " by inverimus\n\n", resetStyle)
    t.write(ind2, t.yMax, true, fgCyan, "-a, --add <args>")
    t.write(ind30, t.yMax, false, fgWhite, "Install an addon. <args> is a list of urls seperated by spaces.", "\n")
    t.write(ind2, t.yMax, true, fgCyan, "-c, --config [options]")
    t.write(ind30, t.yMax, false, fgWhite, "Configuration options. lycan --help config for more info", "\n")
    t.write(ind2, t.yMax, true, fgCyan, "-e, --export")
    t.write(ind30, t.yMax, false, fgWhite, "Write installed addons to a file that can imported with lycan --install <filename>", "\n")
    t.write(ind6, t.yMax, true, fgCyan, "--help")
    t.write(ind30, t.yMax, false, fgWhite, "Display this message.", "\n")
    t.write(ind2, t.yMax, true, fgCyan, "-i, --install <args>")
    t.write(ind30, t.yMax, false, fgWhite, "Alias for --add", "\n")
    t.write(ind2, t.yMax, true, fgCyan, "-l, --list [options]")
    t.write(ind30, t.yMax, false, fgWhite, "List installed addons sorted by name.", "\n")
    t.write(ind2, t.yMax, true, fgCyan, "-n, --name <id> <name>")
    t.write(ind30, t.yMax, false, fgWhite, "Set your own <name> for addon with <id>. Must use quotes around <name> if it contains spaces.\n")
    t.write(ind30, t.yMax, false, fgWhite, "Leave <name> blank to go back to the default name.\n")
    t.write(ind6, t.yMax, true, fgCyan, "--pin <ids>")
    t.write(ind30, t.yMax, false, fgWhite, "Pin addon to current version. Addon will not be updated until unpinned.", "\n")
    t.write(ind2, t.yMax, true, fgCyan, "-r, --remove <ids>")
    t.write(ind30, t.yMax, false, fgWhite, "Remove installed addons by id number", "\n")
    t.write(ind6, t.yMax, true, fgCyan, "--reinstall")
    t.write(ind30, t.yMax, false, fgWhite, "Force a reinstall of all addons. Can be used to restore from an existing lycan_addons.json file.", "\n")
    t.write(ind6, t.yMax, true, fgCyan, "--restore <ids>")
    t.write(ind30, t.yMax, false, fgWhite, "Restore addons to the version prior to last update. Backups must be enabled.", "\n")
    t.write(ind6, t.yMax, true, fgCyan, "--unpin")
    t.write(ind30, t.yMax, false, fgWhite, "Unpin addon to restore updates.", "\n")
    t.write(ind2, t.yMax, true, fgCyan, "-u, --update")
    t.write(ind30, t.yMax, false, fgWhite, "Update all installed addons. The default if no arguments are given.", "\n")
  quit()
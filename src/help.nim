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
    t.write(x, t.yMax, true, "-a, --add <args>", "\n")
    t.write(x, t.yMax, true, "-i, --install <args>", "\n\n")
    t.write(x, t.yMax, true, "Installs an addon from a url. Supported sites are github releases, github repositories, tukui, wowinterface, and gitlab releases. Including 'http://' will work but is not required.\n\n")
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

  of "l", "list":
    let x = 2
    let x2 = 4
    t.write(x, t.yMax, true, "-l, --list [options]", "\n\n")
    t.write(x, t.yMax, true, "Lists installed addons. The default order is alphabetical.\n\n")
    t.write(x, t.yMax, true, "OPTIONS:", "\n")
    t.write(x2, t.yMax, true, "t / time   Sort by most recent install install/update date and time.\n\n")
    t.write(x, t.yMax, true, "EXAMPLES:", "\n")
    t.write(x2, t.yMax, true, "lycan -l time", "\n")
    t.write(x2, t.yMax, true, "lycan -lt", "\n")
    quit()

  else:
    let x = 2
    let x2 = 30
    t.write(x, t.yMax, true, "-a, --add <args>")
    t.write(x2, t.yMax, false, "Install an addon. <args> is a list of urls seperated by spaces.", "\n")
    t.write(x, t.yMax, true, "-h, --help")
    t.write(x2, t.yMax, false, "Display this message.", "\n")
    t.write(x, t.yMax, true, "-i, --install <args>")
    t.write(x2, t.yMax, false, "Alias for --add", "\n")
    t.write(x, t.yMax, true, "-l, --list [options]")
    t.write(x2, t.yMax, false, "List installed addons sorted by name.", "\n")
    t.write(x, t.yMax, true, "    --pin <ids>")
    t.write(x2, t.yMax, false, "Pin addon to current version. Addon will not be updated until unpinned.", "\n")
    t.write(x, t.yMax, true, "-r, --remove <ids>")
    t.write(x2, t.yMax, false, "Remove installed addons by id number", "\n")
    t.write(x, t.yMax, true, "    --restore <ids>")
    t.write(x2, t.yMax, false, "Restore addons to the version prior to last update.", "\n")
    t.write(x, t.yMax, true, "    --unpin")
    t.write(x2, t.yMax, false, "Unpin addon to restore updates.", "\n")
    t.write(x, t.yMax, true, "-u, --update")
    t.write(x2, t.yMax, false, "Update installed addons. Default if no arguments are given.", "\n")
    quit()
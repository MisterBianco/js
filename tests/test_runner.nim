import
    os, strutils, unittest

import ../src/js

proc testCommandize() =
    suite "Commandize | Simple Command Tests":
        test "Single Command: ls":
            var cstr = parseCmdLine("ls")
            let command = commandize(cstr)
            check command.len == 1
            check command[0].len() == 1
            check command == @[@["ls"]]

        test "Single Command: ls > /dev/null":
            var cstr = parseCmdLine("ls > /dev/null")
            let command = commandize(cstr)
            check command.len == 1
            check command[0].len() == 3
            check command == @[@["ls", ">", "/dev/null"]]

        test "Single Command: ls | wc":
            var cstr = parseCmdLine("ls | wc")
            let command = commandize(cstr)
            check command.len == 1
            check command[0].len() == 3
            check command == @[@["ls", "|", "wc"]]

        test "Single Command: ls 2> /dev/null | wc":
            var cstr = parseCmdLine("ls 2> /dev/null | wc")
            let command = commandize(cstr)
            check command.len == 1
            check command[0].len() == 5
            check command == @[@["ls", "2>", "/dev/null", "|", "wc"]]



when isMainModule:
    testCommandize()
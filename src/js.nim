#[
Copyright (c) 2019 Jarad Dingman

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]#

#[
    Features:
        [*] Pipes 
        [*] Chaining
        [*] Redirects
        [*] Aliases
        [*] Builtins
        [*] $ get Environment variables
        [] Set environment variables
        [] Args parsing
]#

# --[ Imports ]----- #
import os
import noise
import posix
import tables
import strutils
import sequtils

import builtins

# --[ Type Aliases ]------ #
type
    Descriptors = array[2, cint]

# --[ Converter ]------------------------- #
converter toCint(_: int): cint = _.cint
converter toPid(_: int): Pid = _.toPid

# --[ Globals ]----------- #
let
    ProcessID:Pid = getCurrentProcessId()

var 
    Status:cint = QuitSuccess

const 
    HOME_DIRECTORY = getHomeDir()
    FILE_DESCRIPTORS = [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO]
    FILE_PERMISSIONS = S_IRUSR or S_IWUSR or S_IRGRP or S_IWGRP or S_IROTH or S_IWOTH

    ALIASES = {
        "ls": "ls --color=always".splitWhiteSpace(),
        "wc": @["wc", "-l"]
    }.toTable


# --[ Iterators ]------------------------- #
iterator getCommands(command: seq[string]): seq[string] =
    var commands = command
    var idx = command.find("&&")
    while idx != -1:
        yield commands[0..idx-1]
        commands = commands[idx+1..commands.len-1]
        idx = commands.find("&&")
    yield commands

# --[ Forward Declarations ]-------------- #
proc shell_loop()
proc init_shell(): Noise
proc run_shell(noise: var Noise)
proc execute(command: seq[string]): Pid
proc getPipes(command: seq[string]): seq[seq[string]]
proc spawn(stdin, stdout: cint, command: seq[string]): Pid

# --[ Helpers ]--------------------------- #
proc relative_tilde(): string {.inline.}
proc prompt(): Styler {.inline.}

# --[ Functions ]------------------------- #
proc init_shell(): Noise =
    # Initialization code should go here
    result = Noise.init()

proc run_shell(noise: var Noise) =
    noise.setPrompt(prompt())
    if not noise.readLine():
        quit("Failed to readline.", QuitFailure)

    let line = noise.getLine
    if line.len < 1:
        return

    for command in getCommands(parseCmdLine(line)):
        discard posix.waitpid(execute(command), Status, 0)
    # quit(0)

proc shell_loop() =
    var noise = init_shell()
    while true:
        run_shell(noise)

proc parse_aliases_builtins(command: var seq[string]): int =
    if ALIASES.hasKey(command[0]):
        command = ALIASES[command[0]] & command[1..<command.len]

    # Builtins
    # Define additional builtins here.
    # ----------------------------------------------------
    case command[0]:
        of "cd":
            if command.len == 1:
                setCurrentDir(HOME_DIRECTORY)
            elif command.len == 2:
                if command[1] == "-":
                    echo "SET to last dir"
                elif dirExists(command[1]):
                    setCurrentDir(command[1])
                else:
                    echo "Dir doesn't exist"
            return 1
        of "quit", "exit", "q":
            builtins.die(ProcessID)
            return 1
        of "pwd":
            echo getCurrentDir()
            return 1
        else:
            return 0
    # -----------------------------------------------------

proc execute(command : seq[string]): Pid =
    var stdin:cint
    var compipe:seq[string]
    var fd:Descriptors
    var commands = getPipes(command)
    
    for subcomm in commands[0..<commands.len-1]:
        compipe = subcomm
        if parse_aliases_builtins(compipe) == 1:
            return -1
        
        if pipe(fd) == -1:
            echo "Pipe creation failed."
            return -1

        discard waitpid(
            spawn(stdin, fd[1], compipe),
            Status, 0
        )

        discard close(fd[1])
        stdin = fd[0]

    # Try to make the following lines reusable...
    compipe = commands[commands.len-1]
    if parse_aliases_builtins(compipe) == 1:
        return -1
    return spawn(stdin, 1, compipe)

proc spawn(stdin, stdout: cint, command: seq[string]): Pid =
    var pid:Pid = fork()
    var index = 0

    if pid < 0:
        echo "Forking Failure ;)"
        return -1

    #[ CHILD ]#
    elif pid == 0:
        
        var stdarr = [stdin, stdout, STDERR_FILENO]
        var command_sequence:seq[string] = @[]

        while index < command.len:
            if command[index] == "2>" and command.len-1 > index:
                stdarr[2] = posix.creat(command[index+1], FILE_PERMISSIONS)
                index += 1
                
            elif command[index] == ">" and command.len-1 > index:
                stdarr[1] = posix.creat(command[index+1], FILE_PERMISSIONS)
                index += 1

            elif command[index] == "<" and command.len-1 > index:
                stdarr[0] = posix.open(command[index+1], O_RDWR)
                index += 1

            elif command[index].startsWith("$"):
                command_sequence.add(getEnv(command[index][1..<command[index].len]))

            elif command[index].contains("~"):
                command_sequence.add(command[index].replace("~", HOME_DIRECTORY))

            else:
                command_sequence.add(command[index])
            
            index += 1

        for index in 0..<stdarr.len:
            if stdarr[index] != FILE_DESCRIPTORS[index]:
                discard posix.dup2(stdarr[index], FILE_DESCRIPTORS[index])
                discard posix.close(stdarr[index])

        let csarr = allocCStringArray(command_sequence)

        let return_status = execvp(
            command_sequence[0].cstring, 
            csarr
        )

        deallocCStringArray(csarr)

        # This is why error checking is important kiddo's
        if return_status == -1:
            echo "ERROR"
            Status = -1
            quit(return_status)

        return return_status
    return pid

proc getPipes(command: seq[string]): seq[seq[string]] =
    var idx = command.find("|")
    var commands = command

    while idx != -1:
        result.add(commands[0..idx-1])
        commands = commands[idx+1..commands.len-1]
        idx = commands.find("|")

    result.add(@[commands[0..commands.len-1]])

# --[ Helpers ]---------------------------- #
proc prompt(): Styler =
    let color = if Status != 0: fgRed
        else: fgGreen
    result = Styler.init(color, " ", fgCyan, relative_tilde(), fgGreen, "  ")

proc relative_tilde(): string =
    result = getCurrentDir()
    if result.startsWith(HOME_DIRECTORY):
        result = "~/" & result.split(HOME_DIRECTORY)[1]

# --[ define ]------------------------------- #
when isMainModule:
    when declared(commandLineParams):
        if "--version" in commandLineParams():
            echo "0.0.1"
            quit(0)
        
    shell_loop()
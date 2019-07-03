import os
import posix

proc die*(process : Pid) =
    quit(0)
    # discard posix.kill(process, SIGKILL)
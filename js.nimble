# Package

version       = "0.0.1"
author        = "jacobsin"
description   = "A custom shell written in nim"
license       = "MIT"
srcDir        = "src"
bin           = @["js"]

# Dependencies
requires "nim >= 0.20.0"
requires "noise"

# Needs mo tests
task test, "Run test suite.":
    exec "nimble c -y -r tests/test_runner"
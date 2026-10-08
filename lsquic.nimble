packageName = "lsquic"
version = "0.11.0"
author = "Status Research & Development GmbH"
description = "Nim wrapper around the lsquic library"
license = "MIT"
installDirs = @["libs", "scripts"]
installFiles = @["lsquic.nim"]

requires "nim >= 2.0.0"
requires "zlib"
requires "stew >= 0.4.0"
requires "chronos >= 4.0.4"
requires "unittest2"
requires "chronicles >= 0.11.0"
requires "https://github.com/vacp2p/nim-boringssl >= 0.0.11"

import std/[os, strutils, sequtils]

var flags = getEnv("NIMFLAGS", "") # Extra flags for the compiler

task format, "Format nim code using nph":
  exec "nph ./. *.nim"

task test, "Run tests":
  var nimc = "nim c -d:fast --threads:on " & flags

  when defined(windows):
    nimc &= " -d:nimDebugDlOpen"

  exec nimc & " tests/test_all.nim"
  exec "./tests/test_all --output-level=VERBOSE"

task test_no_asm, "Run tests without BoringSSL assembly":
  flags = flags & " -d:BORINGSSL_USE_ASM=false "
  testTask()

task test_release, "Run tests - release":
  flags = flags & " -d:release "
  testTask()

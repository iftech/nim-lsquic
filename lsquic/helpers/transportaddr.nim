# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH 

import chronos
import chronos/osdefs
import ../lsquic_ffi

# up until nim 2.2.6, AF_INET6 const had wrong value. 
# that's why this const is defiend here to have backwards compatability with older versions of nim.
# commit fix: https://github.com/nim-lang/Nim/commit/248850a0ce869c15fea16a35e248850d2df47c8d
const fixed_AF_INET6 =
  when defined(macosx):
    30
  elif defined(windows):
    23
  else:
    10

proc sockAddrLen*(family: int): SockLen {.inline.} =
  case family
  of AF_INET.int:
    sizeof(Sockaddr_in).uint32
  of fixed_AF_INET6.int: # use fixed const
    sizeof(Sockaddr_in6).uint32
  else:
    raiseAssert "invalid socket address family"

proc toTransportAddress*(sock: ptr SockAddr): TransportAddress =
  # `fromSAddr` only reads through the pointer, so the sockaddr does not need
  # to be copied into a Sockaddr_storage first.
  var taddr: TransportAddress
  fromSAddr(cast[ptr Sockaddr_storage](sock), sockAddrLen(sock.sa_family.int), taddr)
  taddr

proc isIPv6Family*(sock: ptr SockAddr): bool {.inline.} =
  sock.sa_family.int == fixed_AF_INET6

proc isIPv4Family*(sock: ptr SockAddr): bool {.inline.} =
  sock.sa_family.int == AF_INET.int

func matchSocketFamily*(address, bound: TransportAddress): TransportAddress {.inline.} =
  if bound.family == AddressFamily.IPv6 and address.family == AddressFamily.IPv4:
    address.toIPv6()
  else:
    address

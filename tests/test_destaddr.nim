# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.used.}

import unittest2
import chronos, chronos/osdefs
import ../lsquic/context/io
import ../lsquic/endpoint
import ./helpers/[address, trackers]

proc prepared(local, dest: string): TransportAddress =
  var
    localStorage = toSockaddrStorage(initTAddress(local))
    destStorage = toSockaddrStorage(initTAddress(dest))
    outStorage: Sockaddr_storage
    outLen: SockLen
  prepareDestAddrForTest(
    cast[ptr SockAddr](addr localStorage),
    cast[ptr SockAddr](addr destStorage),
    outStorage,
    outLen,
  )
  fromSAddr(addr outStorage, outLen, result)

suite "destination address preparation":
  teardown:
    checkTrackers()

  test "IPv4 local keeps an IPv4 destination":
    check prepared("192.168.1.10:1000", "192.168.1.20:4433") ==
      initTAddress("192.168.1.20:4433")

  test "IPv6 local keeps an IPv6 destination":
    check prepared("[::1]:1000", "[2001:db8::2]:4433") ==
      initTAddress("[2001:db8::2]:4433")

  test "IPv6 local maps an IPv4 destination into IPv6":
    # A dual-stack `::` socket cannot sendmsg to a bare AF_INET destination.
    let mapped = prepared("[::]:1000", "192.168.1.20:4433")
    check mapped.family == AddressFamily.IPv6
    check mapped.port == Port(4433)
    check mapped == initTAddress("192.168.1.20:4433").toIPv6()

  test "IPv4 local leaves an IPv6 destination alone":
    check prepared("192.168.1.10:1000", "[2001:db8::2]:4433") ==
      initTAddress("[2001:db8::2]:4433")

proc received(address: TransportAddress): TransportAddress =
  var storage = toSockaddrStorage(address)
  receivedAddress(cast[ptr SockAddr](addr storage))

suite "received peer addresses":
  test "mapped IPv4 matches the Chronos callback representation":
    let peer = initTAddress("192.0.2.1:4433")
    check received(peer.toIPv6()) == peer

  test "native IPv4 preserves address and port":
    let peer = initTAddress("192.0.2.1:4433")
    check received(peer) == peer

  test "native IPv6 preserves address and port":
    let peer = initTAddress("[2001:db8::1]:4433")
    check received(peer) == peer

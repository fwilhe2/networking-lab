# Exercises

Practice tasks for the demo topology. Load it with **Load Demo** in the primary menu, press
**Run**, and wait until the status bar says `Lab running: 4 devices`.

```
pc1 ── sw1 ── r1 ══ r2 ── sw2 ── srv1
     10.0.1.0/24   10.0.3.0/24   10.0.2.0/24
     .10     .1    .1     .2     .1     .10
```

Every command below has been run against this lab, so if one behaves differently, that is
worth investigating rather than working around.

## Before you start

**Getting a prompt.** Double-click a device on the canvas. A router opens `vtysh`, FRR's
configuration shell; a host opens `sh`. To get a *shell* on a router instead — for `ip`,
`ping`, `traceroute` — run `podman exec -it r1 sh` yourself, and from there any FRR command
is `vtysh -c '<command>'`. Both work at once; the tabs are independent.

**Three house rules of this lab:**

- **There is no internet.** The lab is generated with `isolated: true`, so `apk add` will
  not work. Everything here uses what the images already carry: busybox (`ip`, `ping`,
  `arp`, `nc`, `wget`, `netstat`) on the hosts, `vtysh`, `ip`, `ping`, `traceroute` and `ss`
  on the routers, plus `python3` on srv1.
- **Nothing inside a container survives Stop.** `Stop` runs `compose down -v`. Anything
  configured with `ip` or in `vtysh` and not written into the topology is gone. That is a
  feature while you are practising: to undo an experiment, stop and start the lab.
- **A switch is not a container.** sw1 and sw2 are bridge networks, so there is nothing to
  log into and no MAC table to inspect. The learning about layer 2 happens on the hosts.

The container list behind the status-bar button shows what is actually up, including a
container that exited on boot and the exact `compose` command to reach the same lab from a
terminal.

---

## Warm up — read what is already there

### 1. Count the routers without traceroute

`traceroute` needs a raw socket, and the hosts in this lab are given `NET_ADMIN` but not
`NET_RAW`, so it fails on pc1 with `Operation not permitted`. Count the hops with TTL
instead:

```sh
ping -c1 -t1 -W2 10.0.2.10     # dies at r1
ping -c1 -t2 -W2 10.0.2.10     # dies at r2
ping -c1 -t3 -W2 10.0.2.10     # arrives
```

**Check:** the first two report 100% packet loss, the third replies.
**Why:** every router decrements the TTL and discards the packet at zero. The lowest TTL
that works is the number of hops. From a *router* prompt, `traceroute -n 10.0.2.10` shows
the same two hops directly, because routers do have `NET_RAW`.

### 2. The same question asked of three devices

```sh
podman exec pc1 ip route                       # a default route and one connected subnet
podman exec r1 vtysh -c 'show ip route'        # connected, plus what OSPF learned
podman exec r1 vtysh -c 'show ip route ospf'   # only the learned half
```

**Check:** pc1 knows two things; r1 knows every subnet in the lab, and `10.0.2.0/24` is
marked `O>*` with metric `[110/20]`.
**Why:** a host does not participate in routing. It has a default route and a guess that
everything else is somebody else's problem — and the somebody is r1.

### 3. Take the default route away

```sh
podman exec pc1 sh -c 'ip route del default; ping -c1 -W2 10.0.2.10; ip route'
podman exec pc1 ip route add default via 10.0.1.1
```

**Check:** the ping fails with `Network unreachable` — a different failure from the silence
in exercise 1 — and the route comes back with the second command.
**Why:** "unreachable" is generated locally, before a packet is ever sent. Learning to tell
that apart from a packet that left and never came back is most of host-side debugging.

---

## Layer 2 and addressing

### 4. Watch ARP work

```sh
podman exec pc1 sh -c 'ping -c1 10.0.1.1 >/dev/null; arp -a; ip neigh'
podman exec pc1 ip neigh flush dev eth0
podman exec pc1 sh -c 'ping -c1 10.0.1.1 >/dev/null; ip neigh'
```

**Check:** the gateway appears with a MAC address; the flush reports how many entries it
deleted, and the next packet learns it again — usually before you can look, which is the
point.
**Why:** nothing on the wire is addressed by IP. Two things in that output are worth a
second look: srv1 never appears however often you ping it, because it is not on this segment
and pc1 only ever ARPs for the gateway; and `10.0.1.254` does appear, which is the engine's
DNS resolver sitting on the same bridge — the reason `ping r1` resolves at all.

### 5. Break the netmask, watch the symptom

Give pc1 a /16 instead of a /24, so it believes srv1 is a neighbour on its own wire:

```sh
podman exec pc1 sh -c '
  ip addr del 10.0.1.10/24 dev eth0
  ip addr add 10.0.1.10/16 dev eth0
  ip route
  ping -c1 -W2 10.0.2.10
  ip neigh'
```

**Check:** the routing table now says `10.0.0.0/16 dev eth0 scope link`, the ping fails, and
`ip neigh` shows `10.0.2.10 … INCOMPLETE`.
**Why:** this is the single most useful failure to recognise. The host is not routing to
srv1 at all — it is shouting for its MAC address on a segment srv1 is not attached to. A
wrong prefix length looks like a broken cable and is nothing of the kind.

Restore it:

```sh
podman exec pc1 sh -c '
  ip addr del 10.0.1.10/16 dev eth0
  ip addr add 10.0.1.10/24 dev eth0
  ip route add default via 10.0.1.1'
```

### 6. Why `ping srv1` does not work

```sh
podman exec pc1 ping -c1 srv1     # bad address
podman exec pc1 ping -c1 r1       # works
```

**Check:** the name r1 resolves, srv1 does not.
**Why:** the container engine's DNS answers per network. pc1 and r1 share sw1, so r1 is in
pc1's view; srv1 lives on sw2 and is not. Nothing is broken — this is what a name server
that only knows one segment looks like.

Fix it the old way, with a hosts file:

```sh
podman exec pc1 sh -c 'echo "10.0.2.10 srv1" >> /etc/hosts; ping -c1 srv1'
```

Note that `>>` works but `sed -i` does not: `/etc/hosts` is bind-mounted into the container,
so it can be appended to but not replaced. To undo, rewrite it in place:

```sh
podman exec pc1 sh -c 'grep -v " srv1$" /etc/hosts > /tmp/h && cat /tmp/h > /etc/hosts'
```

---

## Routing and OSPF

### 7. Meet the neighbours

```sh
podman exec r1 vtysh -c 'show ip ospf neighbor'
podman exec r1 vtysh -c 'show ip ospf interface eth1'
```

**Check:** one neighbour, state `Full`, with a dead timer counting down from 40 seconds.
**Why:** `Full` means the two routers have exchanged their whole link-state database. Any
other state — `Init`, `2-Way`, `ExStart`, `Loading` — is an adjacency that is stuck, and
which one it is stuck in tells you why.

### 8. Pull the link and time the recovery

```sh
podman exec r1 vtysh -c 'conf t' -c 'interface eth1' -c 'shutdown'
podman exec pc1 ping -c1 -W2 10.0.2.10                  # fails
podman exec r1 vtysh -c 'show ip route ospf'            # 10.0.2.0/24 is gone

podman exec r1 vtysh -c 'conf t' -c 'interface eth1' -c 'no shutdown'
```

**Check:** after `no shutdown` the neighbour goes `Init` → `Loading` → `Full` and the route
reappears; end-to-end reachability comes back half a minute or so later, and the wait is
worth timing rather than guessing at. Watch it happen:

```sh
watch -n1 "podman exec r1 vtysh -c 'show ip ospf neighbor'"
```

**Why:** convergence is not instant, and the delay is made of hello and dead intervals
rather than of anything being slow. Try `ip ospf hello-interval 1` and `ip ospf
dead-interval 4` on both ends of the r1–r2 link and measure the difference.

**Mind which interface.** The link is `eth1` on r1 but `eth0` on r2 — interfaces are
numbered in the order the links were added to each device, not symmetrically across one:

```sh
podman exec r2 vtysh -c 'show ip ospf interface' | grep -E '^eth|Internet Address'
```

Setting the timers on the wrong interface leaves one end at the default, and mismatched
hello and dead intervals mean the adjacency never forms at all — a realistic mistake with a
symptom (`Init`, forever) worth recognising once.

### 9. Make the router prefer a different path

```sh
podman exec r1 vtysh -c 'conf t' -c 'interface eth1' -c 'ip ospf cost 100'
podman exec r1 vtysh -c 'show ip route ospf'
podman exec r1 vtysh -c 'conf t' -c 'interface eth1' -c 'no ip ospf cost'
```

**Check:** the metric moves from `[110/20]` to `[110/110]` and back.
**Why:** 110 is OSPF's administrative distance and the second number is the path cost. With
only one path the traffic goes the same way regardless — which is the point of the next
exercise.

### 10. Give it a second path to choose from

In the app: add a router **r3**, link it to both r1 and r2, and give it the same extra
configuration the others carry:

```
router ospf
 network 10.0.0.0/8 area 0
```

Press Run again. Now raise the cost on r1's direct link to r2 above the two-hop path
through r3 and prove the traffic moved:

```sh
podman exec r1 vtysh -c 'show ip route 10.0.2.0/24'
```

**Check:** the next hop changes from r2's address to r3's.
**Why:** this is the whole reason to run a routing protocol instead of writing routes by
hand — the second path was there all along, and OSPF used it the moment the first became
expensive.

### 11. Do it without OSPF

Select each router in the app and delete `router ospf` and its `network` line from **Extra
FRR config**. Run the lab and confirm pc1 can no longer reach srv1. Then make it work with
static routes only:

```sh
podman exec r1 vtysh -c 'conf t' -c 'ip route 10.0.2.0/24 10.0.3.2'
podman exec r2 vtysh -c 'conf t' -c 'ip route 10.0.1.0/24 10.0.3.1'
podman exec pc1 ping -c2 10.0.2.10
```

**Check:** `show ip route static` lists the entry as `S>*`, and the ping succeeds.
**Why:** two routes for two routers is easy. Now imagine exercise 10's three routers, then
twenty — and notice you had to add the *return* route as well, which is the mistake
everyone makes once.

---

## Services

### 12. Talk to the server three ways

srv1 runs `python3 -m http.server` on port 80.

```sh
podman exec srv1 netstat -tln                       # 0.0.0.0:80 LISTEN
podman exec pc1 wget -qO- http://10.0.2.10/         # the directory listing
podman exec pc1 sh -c 'printf "GET / HTTP/1.0\r\n\r\n" | nc 10.0.2.10 80 | head -3'
```

**Check:** all three agree that the port is open, from both ends of the lab.
**Why:** `netstat` proves the server is listening, `wget` proves the path works end to end,
and `nc` proves it without a client that might be hiding a redirect or a proxy.

### 13. Run your own service

```sh
podman exec -d srv1 sh -c 'nc -l -p 8080 -e echo hello'
podman exec pc1 sh -c 'echo x | nc -w2 10.0.2.10 8080'
```

**Check:** pc1 prints `hello`.
**Why:** worth doing once, so that "the port is not open" stops being a mystery and starts
being something you can test in two commands. Add a device on sw2 and repeat: the same
service, one hop closer, behaves identically.

---

## Build your own

- **A second host on sw2.** Drag a PC onto the canvas, link it to sw2, give it
  `10.0.2.11` and the gateway `10.0.2.1`. Prove it reaches pc1 across both routers, and
  that it reaches srv1 without touching a router at all — the ARP table on each is the
  evidence.
- **A subnet that OSPF does not carry.** Add a router and a segment addressed
  `192.168.50.0/24`. The demo's `network 10.0.0.0/8 area 0` does not match it, so it will
  not be advertised — the route is missing everywhere but on the router that owns it.
  Find that in `show ip route` before you fix it.
- **Two areas.** Put the r1–r2 link in area 0 and everything behind r2 in area 1, with r2 as
  the border router. Compare `show ip ospf database` on r1 before and after: the individual
  links behind r2 stop appearing, and a summary takes their place.
- **A deliberate address conflict.** Give two devices the same address in the same subnet
  and watch what the ARP table does. Then find the error the app's compiler shows before you
  ever press Run.

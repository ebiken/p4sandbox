# p4alu ... Arithmetic Logic Unit in P4-14

This P4 program would parse UDP packet with payload in "p4alu header format" and apply calculation and set result based on the operand/opcode in the original packet.
This program is tested using BMv2 simple_switch P4 target.

- [Speaker Deck: p4alu: Arithmetic Logic Unit in P4](https://speakerdeck.com/ebiken/p4alu-arithmetic-logic-unit-in-p4)
- Backup: [Sldie Share](https://www.slideshare.net/kentaroebisawa/p4alu-arithmetic-logic-unit-in-p4)

## Compile, Run on BMv2 and Configure

* Compile P4 code (p4alu.p4)
* Run on BMv2
* Run CLI (on another terminal)
* Configure tables

```bash
$ p4c -x p4-14 p4alu.p4

$ sudo ~/p4lang/bmv2/targets/simple_switch/simple_switch p4alu.json \
-i 0@vtap0 -i 1@vtap1 --nanolog \
ipc:///tmp/bm-0-log.ipc --log-console -L debug --notifications-addr \
ipc:///tmp/bmv2-0-notifications.ipc

$ cd ~/p4lang/bmv2/targets/simple_switch
$ ./runtime_CLI

table_set_default t_fwd _drop
table_add t_fwd forward 0 => 1
table_add t_fwd forward 1 => 0

table_add t_p4alu p4alu_add 1 =>
table_add t_p4alu p4alu_sub 2 =>
```

## Sending / Receiving p4alu packets

* p4alu header format

```c
header_type p4alu_t {
    fields { // 14 bytes
        op1    : 32;
        opCode : 16;
        op2    : 32;
        result : 32;
    }
}
header p4alu_t p4alu;
```

* Run packet capturing tool on host1:veth1
```
# example using cuishark : https://github.com/slankdev/cuishark
$ sudo ip netns exec host1 ./cuishark -i veth1 udp
```

* Send packet from host0
```
# op1:0x10, opCode:0x01 (Add), op2: 0x02
echo -n -e "\x00\x00\x00\x10\x00\x01\x00\x00\x00\x02\x00\x00\x00\x00" | ip netns exec host0 nc -w1 -u 172.20.0.2 1600
# op1:0x10, opCode:0x02 (Sub), op2: 0x02
echo -n -e "\x00\x00\x00\x10\x00\x02\x00\x00\x00\x02\x00\x00\x00\x00" | ip netns exec host0 nc -w1 -u 172.20.0.2 1600
```

## Setup netns based hosts

Create hosts/interfaces to send/receive packet via P4 BMv2.

* Create namespace `host0`, `host1`
* Create veth/vtap pair.
* Create and assign `veth0`, `veth1` to namespace.
* Assign IP address to veth.

```bash
# Create namespace
ip netns add host0
ip netns add host1

# Create veth/vtap pairs
ip link add veth0 type veth peer name vtap0
ip link add veth1 type veth peer name vtap1

# Connect veth between host0 and host1
ip link set veth0 netns host0
ip link set veth1 netns host1
ip link set dev vtap0 up
ip link set dev vtap1 up

# Link up loopback and veth
ip netns exec host0 ip link set veth0 up
ip netns exec host0 ifconfig lo up
ip netns exec host1 ip link set veth1 up
ip netns exec host1 ifconfig lo up

# Set IP address
ip netns exec host0 ip addr add 172.20.0.1/24 dev veth0
ip netns exec host1 ip addr add 172.20.0.2/24 dev veth1
```

/* Copyright 2017-present Kentaro Ebisawa <ebiken.g@gmail.com> 
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* Written in P4_14 */

header_type intrinsic_metadata_t {
    fields {
        learn_id : 4;
        mgid : 4;
    }
}
metadata intrinsic_metadata_t intrinsic_metadata;

// Standard Headers
header_type ethernet_t {
    fields {
        dstAddr   : 48;
        srcAddr   : 48;
        etherType : 16;
    }
}
header ethernet_t ethernet;

header_type ipv4_t {
    fields {
        version : 4;
        ihl : 4;
        diffserv : 8;
        totalLen : 16;
        identification : 16;
        flags : 3;
        fragOffset : 13;
        ttl : 8;
        protocol : 8;
        hdrChecksum : 16;
        srcAddr : 32;
        dstAddr: 32;
    }
}
header ipv4_t ipv4;

header_type udp_t {
    fields {
        srcPort : 16;
        dstPort : 16;
        length_ : 16;
        checksum : 16;
    }
}
header udp_t udp;

/*** p4alu header ***/

/* Header format taken from P4-NetFPGA Tutorial Assignment 1
 * Note that actions in the Tutorial are not implemented.
 * https://github.com/NetFPGA/P4-NetFPGA-public/wiki/Tutorial-Assignments#assignment-1-switch-calculator
 */

header_type p4alu_t {
    fields { // 13 bytes
        op1    : 32;
        opCode : 16; // fit better to UDP than 8bit
        op2    : 32;
        result : 32;
    }
}
header p4alu_t p4alu;

/*** Parser and Control ***/

parser start {
    return parse_ethernet;
}
#define ETHERTYPE_IPV4 0x0800
parser parse_ethernet {
    extract(ethernet);
    return select(latest.etherType) {
        ETHERTYPE_IPV4 : parse_ipv4;
        default: ingress;
    }
}
#define IP_PROTOCOLS_ICMP 1
#define IP_PROTOCOLS_TCP 6
#define IP_PROTOCOLS_UDP 17
parser parse_ipv4 {
    extract(ipv4);
    return select(latest.protocol) {
        //IP_PROTOCOLS_ICMP : parse_icmp;
        //IP_PROTOCOLS_TCP : parse_tcp;
        IP_PROTOCOLS_UDP : parse_udp;
        default: ingress;
    }
}
#define UDP_PORT_P4ALU 1600 // 0x640
parser parse_udp {
    extract(udp);
    return select(latest.dstPort) {
        UDP_PORT_P4ALU : parse_p4alu;
        default: ingress;
    }
}
parser parse_p4alu {
    extract(p4alu);
    return ingress;
}
@pragma header_ordering ethernet ipv4 udp p4alu

action _drop() {
    drop();
}
action _nop() {
}
action p4alu_add() {
    modify_field(p4alu.result, p4alu.op1 + p4alu.op2);
}
action p4alu_sub() {
    modify_field(p4alu.result, p4alu.op1 - p4alu.op2);
}

action forward(port) {
    //modify_field(standard_metadata.egress_port, port);
    modify_field(standard_metadata.egress_spec, port);
}

table t_p4alu {
    reads {
        p4alu.opCode: exact;
    }
    actions {_drop; _nop; p4alu_add; p4alu_sub;}
    // size : 8
}

// table to simply forward packet based on ingress_port
table t_fwd {
    reads {
        standard_metadata.ingress_port: exact;
    }
    actions {forward; _drop;}
    // size : 8
}

control ingress{
    apply(t_p4alu);
    apply(t_fwd);
}

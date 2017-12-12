/* Copyright 2017-present Kentaro Ebisawa <ebiken.g@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *     http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* Written in P4_14 */

// required for simple_switch
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
        dstAddr : 32;
    }
}
header ipv4_t ipv4;
header_type icmp_t {
    fields {
        type_ : 8;
        code : 8;
        hdrChecksum : 16;
    }
}
header icmp_t icmp;
header_type udp_t {
    fields {
        srcPort : 16;
        dstPort : 16;
        length_ : 16;
        checksum : 16;
    }
}
header udp_t udp;

header_type frag_metadata_t {
    fields {
        srcl4port : 16;
        dstl4port : 16;
    }
}
metadata frag_metadata_t frag_metadata;

/*** parser *********************************/
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
parser parse_udp {
    extract(udp);
    set_metadata(frag_metadata.dstl4port, latest.dstPort);
    set_metadata(frag_metadata.srcl4port, latest.srcPort);
    return ingress;
}

/*** ACTION ***********************************************/
action _drop() {
    drop();
}
action _nop() {
}

field_list to_cpu_fields {
    standard_metadata;
}
#define CPU_MIRROR_SESSION_ID 253
action send_to_cpu() {
    clone_ingress_pkt_to_egress(CPU_MIRROR_SESSION_ID, to_cpu_fields);
    drop();
}
action copy_to_cpu() {
    clone_ingress_pkt_to_egress(CPU_MIRROR_SESSION_ID, to_cpu_fields);
    // would not be dropped.
}
action forward(port) {
    //modify_field(standard_metadata.egress_port, port);
    modify_field(standard_metadata.egress_spec, port);
}

action set_dip(dip) {
    modify_field(ipv4.dstAddr, dip);
}

field_list frag_learn_digest {
    ipv4.srcAddr;
    ipv4.dstAddr;
    ipv4.protocol;
    frag_metadata.dstl4port;
}
#define CPU_FRAGMENT_LEARN_SESSION_ID 254
action fragment_learn() {
    clone_ingress_pkt_to_egress(CPU_FRAGMENT_LEARN_SESSION_ID, frag_learn_digest);
    //generate_digest(FRAG_LEARN_RECEIVER, frag_learn_digest);
}
action fragment_true() {
    // move to table t_frag_id
}
action fragment_false() {
    // move to table t_pbr
}
/*** TABLE ************************************************/
// Table t_frag:
// flags (3bits) == Reserved|DF|MF
// fragment_learn = 1st fragment (FO=0, Re=0, DF=0, MF=1)
// fragment_true  = default
// fragment_false = not fragment (FO=0, flag=000 or 010)
table t_frag {
    reads {
        ipv4.fragOffset : exact;
        ipv4.flags      : exact;
    }
    actions {fragment_learn; fragment_true; fragment_false;}
    // size : 512
}
table t_pbr {
    reads {
        ipv4.protocol           : exact;
        frag_metadata.dstl4port : exact;
    }
    actions {set_dip; _nop;}
    // size : 512
}
table t_frag_id {
    reads {
        ipv4.identification : exact;
        ipv4.srcAddr        : exact;
        ipv4.dstAddr        : exact;
    }
    actions {set_dip; send_to_cpu; _nop;}
    // size : 
}

// table to simply forward packet based on ingress_port
table t_fwd {
    reads {
        standard_metadata.ingress_port: exact;
    }
    actions {forward; _drop;}
    // size : 8
}
// table to test send_to_cpu. Set entry only for debug.
table t_cpu {
    reads {
        standard_metadata.ingress_port: exact;
    }
    actions {send_to_cpu; fragment_learn; _drop;}
}

/*** CONTROL **********************************************/
control ingress{
    apply(t_cpu); // table to test send_to_cpu
    apply(t_frag) {
        fragment_learn { // 1st fragment packets
            apply(t_pbr);
        }
        fragment_true { // 2nd or later fragment packets
            apply(t_frag_id);
        }
        fragment_false { // non fragment packets
            apply(t_pbr);
        }
    }
    apply(t_fwd);
}

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

// Netcope NP4 metadata
header_type intrinsic_metadata_np4_t {
    fields {
		ingress_timestamp: 64;
		ingress_port: 8;
		egress_port: 8;
		packet_len: 16;
		hash: 4;
		user16: 16;
		user4: 4;
    }
}
metadata intrinsic_metadata_np4_t intrinsic_metadata;

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
parser parse_udp {
    extract(udp);
    return select(latest.dstPort) {
        default: ingress;
    }
}
@pragma header_ordering ethernet ipv4 udp

action _drop() {
    drop();
}
action _nop() {
}
action forward(port) {
	/// bmv2
    //modify_field(standard_metadata.egress_spec, port);
	/// Netcope NP4
    modify_field(intrinsic_metadata.egress_port, port);
}

// table to simply forward packet based on ingress_port
table t_fwd {
    reads {
		/// BMv2
        // standard_metadata.ingress_port: exact;
		/// Netcope NP4
		intrinsic_metadata.ingress_port: exact;
    }
    actions {forward; _drop;}
    // size : 8
}

control ingress{
    apply(t_fwd);
}

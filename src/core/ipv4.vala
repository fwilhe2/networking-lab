/* ipv4.vala
 *
 * The IPv4 helpers of SPEC section 3. All arithmetic is on unsigned 32-bit
 * integers, and every function here is pure.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    /* The usable range of a CIDR block.
     *
     * `first` and `last` exclude the network and broadcast addresses, and
     * docker claims `last` for its own gateway — see docker_gateway (). */
    public struct CidrInfo {
        public uint32 base_address;
        public uint32 broadcast;
        public int length;
        public uint32 first;
        public uint32 last;
    }

    public uint32 ip_to_int (string ip) {
        uint32 n = 0;
        foreach (var octet in ip.split (".")) {
            n = (n * 256) + (uint32) int.parse (octet);
        }
        return n;
    }

    public string int_to_ip (uint32 n) {
        return "%u.%u.%u.%u".printf ((n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255);
    }

    /* Mirrors /^(\d{1,3}\.){3}\d{1,3}$/ plus an octet range check, so leading
     * zeros are accepted but "10.0.0.256" and "10.0.0" are not. */
    public bool valid_ip (string ip) {
        var octets = ip.split (".");
        if (octets.length != 4) {
            return false;
        }

        foreach (var octet in octets) {
            if (octet.length < 1 || octet.length > 3) {
                return false;
            }
            for (var i = 0; i < octet.length; i++) {
                if (!octet[i].isdigit ()) {
                    return false;
                }
            }
            if (int.parse (octet) > 255) {
                return false;
            }
        }

        return true;
    }

    /* Prefix lengths below 8 or above 29 are rejected: docker's own gateway
     * plus two endpoints does not fit comfortably into a /30. */
    public bool valid_cidr (string cidr) {
        var parts = cidr.split ("/");
        if (parts.length != 2 || !valid_ip (parts[0])) {
            return false;
        }

        var length = parts[1];
        if (length.length < 1 || length.length > 2) {
            return false;
        }
        for (var i = 0; i < length.length; i++) {
            if (!length[i].isdigit ()) {
                return false;
            }
        }

        var bits = int.parse (length);
        return bits >= 8 && bits <= 29;
    }

    /* Defined for any syntactically well-formed CIDR, including the prefix
     * lengths valid_cidr () rejects — the compiler only ever hands it validated
     * input, but the tests exercise a /30. */
    public CidrInfo cidr_info (string cidr) {
        var parts = cidr.split ("/");
        var bits = parts.length > 1 ? int.parse (parts[1]) : 32;

        uint32 mask = bits == 0 ? 0 : (uint32) (0xffffffffu << (32 - bits));
        uint32 base_address = ip_to_int (parts[0]) & mask;
        uint32 broadcast = base_address | ~mask;

        return CidrInfo () {
            base_address = base_address,
            broadcast = broadcast,
            length = bits,
            first = base_address + 1,
            last = broadcast - 1,
        };
    }

    /* Network and broadcast addresses are outside the subnet. */
    public bool in_subnet (string ip, string cidr) {
        var info = cidr_info (cidr);
        var n = ip_to_int (ip);
        return n >= info.first && n <= info.last;
    }

    /* Docker needs a gateway on every network and takes the last usable
     * address; it must never be handed to a device. */
    public string docker_gateway (string cidr) {
        return int_to_ip (cidr_info (cidr).last);
    }
}

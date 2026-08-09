/* names.vala
 *
 * Device naming (SPEC section 4). Sanitising is what makes a name safe to use
 * as a docker service, container, hostname and network identifier all at once,
 * so every name that reaches the compiler has been through it.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace NetworkingLab.Core {

    /* Lowercase, drop everything outside [a-z0-9_-], strip leading separators,
     * fall back if nothing survives. Byte-wise iteration is safe here because
     * every allowed character is ASCII. */
    public string sanitize_name (string s, string fallback = "dev") {
        var lowered = s.down ();
        var result = new StringBuilder ();

        for (var i = 0; i < lowered.length; i++) {
            var c = lowered[i];
            if (c.isdigit () || (c >= 'a' && c <= 'z') || c == '_' || c == '-') {
                result.append_c (c);
            }
        }

        var trimmed = result.str;
        var start = 0;
        while (start < trimmed.length && (trimmed[start] == '_' || trimmed[start] == '-')) {
            start++;
        }
        trimmed = trimmed.substring (start);

        return trimmed == "" ? fallback : trimmed;
    }

    /* "r1" if free, otherwise "r12", "r13", … — a suffix, not an increment, so
     * a name is never silently turned into a different device's name. */
    public string unique_name (string base_name, GenericSet<string> taken) {
        if (!taken.contains (base_name)) {
            return base_name;
        }

        for (var i = 2; ; i++) {
            var candidate = "%s%d".printf (base_name, i);
            if (!taken.contains (candidate)) {
                return candidate;
            }
        }
    }

    public GenericSet<string> new_name_set () {
        return new GenericSet<string> (str_hash, str_equal);
    }
}

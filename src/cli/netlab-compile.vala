/* netlab-compile.vala
 *
 * Headless front end for the core library: reads a topology as JSON on stdin
 * and writes the docker compose file on stdout, with any validation warnings
 * on stderr. It exists so the compiler can be exercised — and diffed against
 * the golden fixture — without a display.
 *
 * Warnings never block generation, so a lab with faults still compiles and
 * still exits 0. Only an unreadable document is an error.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

private int usage (string program, int status) {
    unowned FileStream stream = status == 0 ? stdout : stderr;
    stream.printf ("Usage: %s [--demo] < topology.netlab.json > docker-compose.yml\n", program);
    stream.printf ("       %s --version\n", program);
    return status;
}

int main (string[] args) {
    var use_demo = false;

    for (var i = 1; i < args.length; i++) {
        switch (args[i]) {
            case "--version":
            case "-v":
                stdout.printf ("netlab-compile %s\n", Config.VERSION);
                return 0;
            case "--help":
            case "-h":
                return usage (args[0], 0);
            case "--demo":
                use_demo = true;
                break;
            default:
                stderr.printf ("netlab-compile: unknown argument \"%s\"\n", args[i]);
                return usage (args[0], 2);
        }
    }

    State state;

    if (use_demo) {
        state = demo_state ();
    } else {
        var document = new StringBuilder ();
        string? line = null;
        while ((line = stdin.read_line ()) != null) {
            document.append (line);
            document.append_c ('\n');
        }

        try {
            state = normalize_json (document.str);
        } catch (Error e) {
            stderr.printf ("netlab-compile: %s\n", e.message);
            return 1;
        }
    }

    var result = compile (state);

    for (var i = 0; i < result.warnings.length; i++) {
        var warning = result.warnings[i];
        stderr.printf ("%s %s\n", warning.is_error ? "error:" : "warning:", warning.message);
    }

    stdout.puts (result.yaml);
    return 0;
}

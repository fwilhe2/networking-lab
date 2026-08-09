/* netlab-compile.vala
 *
 * Headless front end for the core library: reads a topology as JSON on stdin
 * and writes the docker compose file on stdout. It exists so the compiler can
 * be exercised — and diffed against the golden fixture — without a display.
 *
 * The compiler itself arrives in Phase 4; until then this only proves that the
 * core library links without GTK.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

int main (string[] args) {
    if (args.length > 1 && (args[1] == "--version" || args[1] == "-v")) {
        stdout.printf ("netlab-compile %s\n", Config.VERSION);
        return 0;
    }

    if (args.length > 1 && (args[1] == "--help" || args[1] == "-h")) {
        stdout.printf ("Usage: %s < topology.netlab.json > docker-compose.yml\n", args[0]);
        return 0;
    }

    stderr.printf ("netlab-compile: the compiler is not implemented yet (PLAN.md phase 4)\n");
    return 1;
}

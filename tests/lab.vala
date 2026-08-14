/* lab.vala
 *
 * The lab layer of PLAN 9.1, driven against stub `podman` and `docker` scripts
 * placed earlier on PATH: they record every argument list they are given and
 * replay canned `ps` output, so the whole lifecycle — probe, up, poll, partial
 * start, down, and no engine at all — is exercised without a container engine
 * and therefore runs in CI. The one test that does need one is
 * tests/lab.integration.sh, which is not in this suite.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Lab;

/* ── the stub ───────────────────────────────────────────────────────── */

private string sandbox;         /* everything this test writes lives here */
private string stub_bin;        /* the directory that shadows the real engines */
private string call_log;

/* Behaviour is driven entirely by the environment so a test can change it
 * between calls without rewriting the script. */
private const string STUB = """#!/bin/sh
printf '%s\n' "$*" >> "$NETLAB_STUB_LOG"
# Overwritten every call, so a test can ask what PATH the engine was handed.
printf '%s\n' "$PATH" > "$NETLAB_STUB_LOG.path"

case " $* " in
  *" compose version --short "*)
    if [ -z "${NETLAB_STUB_COMPOSE_VERSION:-}" ]; then
      echo "docker: 'compose' is not a docker command." >&2
      exit 1
    fi
    echo "$NETLAB_STUB_COMPOSE_VERSION"
    exit 0 ;;
  *" compose ls "*)
    if [ -z "${NETLAB_STUB_DAEMON:-}" ]; then
      echo "Cannot connect to the daemon." >&2
      exit 1
    fi
    echo "$NETLAB_STUB_DAEMON"
    exit 0 ;;
esac

command=""
for word in "$@"; do
  case "$word" in
    up|down|ps|logs) command="$word"; break ;;
  esac
done

if [ "$command" = "${NETLAB_STUB_FAIL:-}" ]; then
  echo "stub: $command refused" >&2
  exit 1
fi

if [ "$command" = "ps" ] && [ -f "${NETLAB_STUB_PS:-}" ]; then
  cat "$NETLAB_STUB_PS"
fi

exit 0
""";

private void install_stub () {
    try {
        sandbox = DirUtils.make_tmp ("netlab-lab-XXXXXX");
    } catch (Error e) {
        error ("could not create a sandbox: %s", e.message);
    }

    stub_bin = Path.build_filename (sandbox, "bin");
    call_log = Path.build_filename (sandbox, "calls.log");
    DirUtils.create_with_parents (stub_bin, 0755);

    /* Both names, so the podman fallback and the NETLAB_ENGINE override can
     * be exercised without a second script. */
    foreach (var engine in Engine.CANDIDATES) {
        var path = Path.build_filename (stub_bin, engine);
        try {
            FileUtils.set_contents (path, STUB);
        } catch (Error e) {
            error ("could not write the stub: %s", e.message);
        }
        FileUtils.chmod (path, 0755);
    }

    /* The stub itself needs sh and cat, so the real PATH stays behind ours. */
    Environment.set_variable ("PATH", stub_bin + ":" + Environment.get_variable ("PATH"), true);

    /* Read once by GLib and cached, so it has to be set before anything asks
     * for the data directory — hence install_stub () running first in main. */
    Environment.set_variable ("XDG_DATA_HOME", Path.build_filename (sandbox, "data"), true);

    Environment.set_variable ("NETLAB_STUB_LOG", call_log, true);
    stub_reset ();
}

/* The default: a working engine with a new enough compose, reachable, and
 * nothing running. */
private void stub_reset () {
    Environment.set_variable ("NETLAB_STUB_COMPOSE_VERSION", "2.29.7", true);
    Environment.set_variable ("NETLAB_STUB_DAEMON", "27.1.1", true);
    Environment.unset_variable ("NETLAB_STUB_FAIL");
    Environment.unset_variable ("NETLAB_STUB_PS");
    Environment.unset_variable ("NETLAB_ENGINE");
    FileUtils.remove (call_log);
}

private void stub_ps (string json) {
    var path = Path.build_filename (sandbox, "ps.json");
    try {
        FileUtils.set_contents (path, json);
    } catch (Error e) {
        error ("could not write the canned ps output: %s", e.message);
    }
    Environment.set_variable ("NETLAB_STUB_PS", path, true);
}

private string calls () {
    string text;
    try {
        FileUtils.get_contents (call_log, out text);
    } catch (Error e) {
        /* No log yet means the engine was never called, which is an answer. */
        return "";
    }
    return text;
}

private void assert_called (string fragment) {
    var log = calls ();
    if (!(fragment in log)) {
        Test.fail_printf ("the engine was never called with \"%s\"; calls were:\n%s", fragment, log);
    }
}

/* ── waiting for an async call ──────────────────────────────────────── */

/* Turns a callback into a straight line: the test iterates the main context
 * until the call lands, then rethrows whatever it produced. */
private class Pending : Object {
    private bool done = false;
    private Error? failure = null;

    public void finish (Error? e) {
        failure = e;
        done = true;
    }

    public void wait () throws Error {
        var context = MainContext.default ();
        while (!done) {
            context.iteration (true);
        }
        if (failure != null) {
            throw failure;
        }
    }
}

private Engine probe_engine () throws Error {
    Engine? engine = null;
    var pending = new Pending ();

    Engine.probe.begin (null, (object, result) => {
        try {
            engine = Engine.probe.end (result);
            pending.finish (null);
        } catch (Error e) {
            pending.finish (e);
        }
    });

    pending.wait ();
    return (!) engine;
}

private Session session_for (string project) {
    try {
        return new Session (probe_engine (), project);
    } catch (Error e) {
        error ("the stub engine did not probe: %s", e.message);
    }
}

private void start (Session session, string yaml) throws Error {
    var pending = new Pending ();
    session.start.begin (yaml, null, (object, result) => {
        try {
            session.start.end (result);
            pending.finish (null);
        } catch (Error e) {
            pending.finish (e);
        }
    });
    pending.wait ();
}

private void stop (Session session) throws Error {
    var pending = new Pending ();
    session.stop.begin (null, (object, result) => {
        try {
            session.stop.end (result);
            pending.finish (null);
        } catch (Error e) {
            pending.finish (e);
        }
    });
    pending.wait ();
}

private void refresh (Session session) throws Error {
    var pending = new Pending ();
    session.refresh.begin (null, (object, result) => {
        try {
            session.refresh.end (result);
            pending.finish (null);
        } catch (Error e) {
            pending.finish (e);
        }
    });
    pending.wait ();
}

/* Canned `ps --format json` for the demo topology, in the array form. The
 * newline-delimited form is covered separately: both are seen in the wild. */
private const string PS_ALL_RUNNING = """
[{"Name":"pc1","Service":"pc1","State":"running","Health":"","ExitCode":0},
 {"Name":"r1","Service":"r1","State":"running","Health":"","ExitCode":0},
 {"Name":"r2","Service":"r2","State":"running","Health":"","ExitCode":0},
 {"Name":"srv1","Service":"srv1","State":"running","Health":"","ExitCode":0}]
""";

/* ── engine discovery ───────────────────────────────────────────────── */

void test_probe_reports_the_compose_version () {
    stub_reset ();

    try {
        var engine = probe_engine ();
        assert (engine.compose_version == "2.29.7");
        assert (engine.program.has_suffix ("/podman"));
        assert (engine.program.has_prefix (stub_bin));
    } catch (Error e) {
        Test.fail_printf ("probe failed: %s", e.message);
    }

    /* The engine is checked too: a client that cannot reach it is no use, and
     * it is checked through compose, which is the path every other call
     * takes — `podman info` answers even when that path is broken. */
    assert_called ("compose ls");
}

void test_probe_without_an_engine () {
    stub_reset ();

    var path = Environment.get_variable ("PATH");
    var empty = Path.build_filename (sandbox, "empty");
    DirUtils.create_with_parents (empty, 0755);
    Environment.set_variable ("PATH", empty, true);

    try {
        probe_engine ();
        Test.fail_printf ("expected NOT_INSTALLED with no engine on PATH");
    } catch (LabError.NOT_INSTALLED e) {
        /* The one outcome the application must survive gracefully. */
    } catch (Error e) {
        Test.fail_printf ("expected NOT_INSTALLED, got %s", e.message);
    }

    Environment.set_variable ("PATH", path, true);
}

/* docker is the fallback, not a second-class case: with no podman on PATH the
 * probe must find it rather than report NOT_INSTALLED. */
void test_probe_falls_back_to_docker () {
    stub_reset ();

    /* PATH is narrowed to the stub directory for this one test: a real podman
     * elsewhere on the developer's PATH would otherwise be found instead of the
     * absence this is about. The stub needs no PATH of its own — its shebang is
     * absolute and printf is a builtin. */
    var path = Environment.get_variable ("PATH");
    Environment.set_variable ("PATH", stub_bin, true);
    FileUtils.rename (Path.build_filename (stub_bin, "podman"),
                      Path.build_filename (sandbox, "podman.hidden"));

    try {
        var engine = probe_engine ();
        assert (engine.program.has_suffix ("/docker"));
    } catch (Error e) {
        Test.fail_printf ("probe did not fall back to docker: %s", e.message);
    }

    FileUtils.rename (Path.build_filename (sandbox, "podman.hidden"),
                      Path.build_filename (stub_bin, "podman"));
    Environment.set_variable ("PATH", path, true);
}

/* Whatever the engine was found through, it is run with its own directory on
 * PATH. `podman compose` is a lookup of an external provider on the PATH podman
 * is given, so an engine found outside PATH would otherwise be reported as
 * having no compose support. */
void test_engine_runs_with_its_own_directory_on_path () {
    stub_reset ();

    /* The engine is addressed by absolute path with its directory *not* on
     * PATH — what an app launched from Finder sees, and the only arrangement in
     * which this assertion can fail. */
    var path = Environment.get_variable ("PATH");
    var empty = Path.build_filename (sandbox, "empty");
    DirUtils.create_with_parents (empty, 0755);
    Environment.set_variable ("PATH", empty, true);
    Environment.set_variable ("NETLAB_ENGINE", Path.build_filename (stub_bin, "podman"), true);

    try {
        probe_engine ();
    } catch (Error e) {
        Environment.set_variable ("PATH", path, true);
        Test.fail_printf ("probe failed: %s", e.message);
        return;
    }

    Environment.set_variable ("PATH", path, true);

    string handed;
    try {
        FileUtils.get_contents (call_log + ".path", out handed);
    } catch (Error e) {
        Test.fail_printf ("the stub recorded no PATH: %s", e.message);
        return;
    }

    if (!handed.strip ().has_prefix (stub_bin + Path.SEARCHPATH_SEPARATOR_S)) {
        Test.fail_printf ("expected %s first on the child's PATH, got %s",
                          stub_bin, handed.strip ());
    }
}

/* An engine that is installed but not on PATH is still found. This is the macOS
 * case — a GUI application there inherits launchd's minimal PATH, not the shell's,
 * so Homebrew's bin directory is missing — exercised on any platform by pointing
 * the search at the sandbox. */
void test_find_program_outside_path () {
    stub_reset ();

    var elsewhere = Path.build_filename (sandbox, "opt");
    DirUtils.create_with_parents (elsewhere, 0755);
    var installed = Path.build_filename (elsewhere, "podman");
    try {
        FileUtils.set_contents (installed, STUB);
    } catch (Error e) {
        error ("could not write the out-of-PATH stub: %s", e.message);
    }
    FileUtils.chmod (installed, 0755);

    var path = Environment.get_variable ("PATH");
    var empty = Path.build_filename (sandbox, "empty");
    DirUtils.create_with_parents (empty, 0755);
    Environment.set_variable ("PATH", empty, true);

    assert (Engine.find_program ("podman", { elsewhere }) == installed);
    /* And the search is the only reason it was found: with nowhere to look
     * beyond an empty PATH there is no engine. */
    assert (Engine.find_program ("podman", {}) == null);

    Environment.set_variable ("PATH", path, true);
}

/* And NETLAB_ENGINE wins outright, which is the escape hatch on a machine that
 * has both installed. */
void test_engine_override () {
    stub_reset ();
    Environment.set_variable ("NETLAB_ENGINE", "docker", true);

    try {
        assert (probe_engine ().program.has_suffix ("/docker"));
    } catch (Error e) {
        Test.fail_printf ("NETLAB_ENGINE was not honoured: %s", e.message);
    }

    assert (Engine.program_name () == "docker");
}

void test_probe_without_the_compose_plugin () {
    stub_reset ();
    Environment.unset_variable ("NETLAB_STUB_COMPOSE_VERSION");

    try {
        probe_engine ();
        Test.fail_printf ("expected NO_COMPOSE");
    } catch (LabError.NO_COMPOSE e) {
    } catch (Error e) {
        Test.fail_printf ("expected NO_COMPOSE, got %s", e.message);
    }
}

void test_probe_with_an_old_compose_plugin () {
    stub_reset ();
    Environment.set_variable ("NETLAB_STUB_COMPOSE_VERSION", "2.20.3", true);

    try {
        probe_engine ();
        Test.fail_printf ("expected COMPOSE_TOO_OLD");
    } catch (LabError.COMPOSE_TOO_OLD e) {
        assert ("2.23.1" in e.message);
    } catch (Error e) {
        Test.fail_printf ("expected COMPOSE_TOO_OLD, got %s", e.message);
    }
}

void test_probe_without_a_daemon () {
    stub_reset ();
    Environment.unset_variable ("NETLAB_STUB_DAEMON");

    try {
        probe_engine ();
        Test.fail_printf ("expected UNAVAILABLE");
    } catch (LabError.UNAVAILABLE e) {
    } catch (Error e) {
        Test.fail_printf ("expected UNAVAILABLE, got %s", e.message);
    }
}

void test_version_comparison () {
    assert (Engine.version_at_least ("2.23.1", "2.23.1"));
    assert (Engine.version_at_least ("2.29.7", "2.23.1"));
    assert (Engine.version_at_least ("5.4.0", "2.23.1"));
    assert (Engine.version_at_least ("v2.24.0", "2.23.1"));
    assert (Engine.version_at_least ("2.29.7-desktop.1", "2.23.1"));

    assert (!Engine.version_at_least ("2.23.0", "2.23.1"));
    assert (!Engine.version_at_least ("2.6.0", "2.23.1"));
    assert (!Engine.version_at_least ("1.29.2", "2.23.1"));

    /* Component-wise, not lexicographic: "10" sorts before "9" as text. */
    assert (Engine.version_at_least ("10.0.0", "9.9.9"));
    assert (!Engine.version_at_least ("9.9.9", "10.0.0"));
}

/* ── where a lab lives ──────────────────────────────────────────────── */

void test_paths_are_under_the_data_directory () {
    var path = compose_path ("netlab-demo");

    assert (path.has_prefix (Environment.get_user_data_dir ()));
    assert (path.has_suffix ("networking-lab/labs/netlab-demo/docker-compose.yml"));

    /* The directory name is also the compose project name, so it goes through
     * the same sanitising as a device name. */
    assert (project_name_for ("My Lab!") == "mylab");
    assert (project_name_for ("***") == "netlab");
    assert (compose_path ("My Lab!").has_suffix ("labs/mylab/docker-compose.yml"));
}

void test_write_compose_creates_the_directory () {
    string path;
    try {
        path = write_compose ("write-test", "name: write-test\n");
    } catch (Error e) {
        Test.fail_printf ("could not write the compose file: %s", e.message);
        return;
    }

    string contents;
    try {
        FileUtils.get_contents (path, out contents);
    } catch (Error e) {
        Test.fail_printf ("could not read back %s: %s", path, e.message);
        return;
    }
    assert (contents == "name: write-test\n");

    /* Again, into a directory that now exists. */
    try {
        write_compose ("write-test", "name: write-test\n# second\n");
    } catch (Error e) {
        Test.fail_printf ("could not overwrite the compose file: %s", e.message);
    }
}

/* ── reading `ps` back ──────────────────────────────────────────────── */

void test_parse_ps_array_form () {
    var statuses = Compose.parse_ps (PS_ALL_RUNNING);

    assert (statuses.length == 4);
    assert (statuses[0].name == "pc1");
    assert (statuses[0].service == "pc1");
    assert (statuses[0].running);
}

void test_parse_ps_newline_delimited_form () {
    /* The form compose 5.4.0 actually prints here. Both have to be read: which
     * one produced the text is not visible in it. */
    var statuses = Compose.parse_ps (
        "{\"Name\":\"r1\",\"State\":\"running\"}\n" +
        "{\"Name\":\"r2\",\"State\":\"exited\",\"ExitCode\":1}\n");

    assert (statuses.length == 2);
    assert (statuses[0].name == "r1" && statuses[0].running);
    assert (statuses[1].name == "r2" && !statuses[1].running);
    assert (statuses[1].exit_code == 1);
}

void test_parse_ps_tolerates_junk () {
    assert (Compose.parse_ps ("").length == 0);
    assert (Compose.parse_ps ("   \n  ").length == 0);
    assert (Compose.parse_ps ("not json at all").length == 0);

    /* An entry without a name identifies nothing and is dropped; one bad line
     * costs one container, not the whole poll. */
    var statuses = Compose.parse_ps (
        "{\"State\":\"running\"}\n{\"Name\":\"r1\",\"State\":\"running\"}\n");
    assert (statuses.length == 1);
    assert (statuses[0].name == "r1");
}

/* ── the lifecycle ──────────────────────────────────────────────────── */

void test_session_starts_and_stops () {
    stub_reset ();
    var session = session_for ("netlab-demo");

    assert (session.state == LabState.DOWN);
    assert (session.container_count () == 0);

    stub_ps (PS_ALL_RUNNING);
    try {
        start (session, "name: netlab-demo\n");
    } catch (Error e) {
        Test.fail_printf ("start failed: %s", e.message);
        return;
    }

    /* The file it booted is the one on disk, addressed by project name. */
    assert (FileUtils.test (session.compose_file, FileTest.EXISTS));
    assert_called ("compose -p netlab-demo -f %s up -d --quiet-pull --remove-orphans"
                       .printf (session.compose_file));

    assert (session.state == LabState.UP);
    assert (session.container_count () == 4);
    assert (session.running_count () == 4);
    assert (!session.partially_running ());
    assert (session.is_running ("r1"));
    assert (!session.is_running ("r3"));

    /* Sorted, because hash order would reshuffle the list on every poll. */
    var containers = session.containers ();
    assert (containers.length == 4);
    assert (containers[0].name == "pc1" && containers[3].name == "srv1");

    /* Down: nothing left to report, so the state falls back on its own. */
    stub_ps ("[]");
    try {
        stop (session);
    } catch (Error e) {
        Test.fail_printf ("stop failed: %s", e.message);
        return;
    }

    assert_called ("down -v --remove-orphans");
    assert (session.state == LabState.DOWN);
    assert (session.container_count () == 0);
    assert (!session.is_running ("r1"));
}

void test_session_reports_a_partial_start () {
    stub_reset ();
    var session = session_for ("netlab-partial");

    /* srv1 exited on boot — the case a bare "running" indicator would hide. */
    stub_ps ("""
[{"Name":"pc1","Service":"pc1","State":"running","ExitCode":0},
 {"Name":"srv1","Service":"srv1","State":"exited","ExitCode":1}]
""");

    try {
        start (session, "name: netlab-partial\n");
    } catch (Error e) {
        Test.fail_printf ("start failed: %s", e.message);
        return;
    }

    assert (session.state == LabState.UP);
    assert (session.partially_running ());
    assert (session.running_count () == 1);
    assert (session.container_count () == 2);
    assert (session.is_running ("pc1"));
    assert (!session.is_running ("srv1"));
    assert (session.status_for ("srv1").exit_code == 1);
}

void test_session_reports_a_failed_up () {
    stub_reset ();
    Environment.set_variable ("NETLAB_STUB_FAIL", "up", true);

    var session = session_for ("netlab-fails");

    try {
        start (session, "name: netlab-fails\n");
        Test.fail_printf ("expected the failed up to be reported");
    } catch (LabError.FAILED e) {
        assert ("refused" in e.message);
    } catch (Error e) {
        Test.fail_printf ("expected FAILED, got %s", e.message);
    }

    /* Reported, not swallowed — and the session settled back rather than being
     * left in STARTING for ever. */
    assert (session.state == LabState.DOWN);
}

void test_session_adopts_a_lab_it_did_not_start () {
    stub_reset ();

    /* A lab left running by an earlier run of the application, or by a
     * terminal: the compose file is on disk and containers exist. */
    try {
        write_compose ("netlab-adopted", "name: netlab-adopted\n");
    } catch (Error e) {
        Test.fail_printf ("could not prepare the lab: %s", e.message);
        return;
    }
    stub_ps (PS_ALL_RUNNING);

    var session = session_for ("netlab-adopted");
    assert (session.state == LabState.DOWN);

    try {
        refresh (session);
    } catch (Error e) {
        Test.fail_printf ("refresh failed: %s", e.message);
        return;
    }

    assert (session.state == LabState.UP);
    assert (session.running_count () == 4);
}

void test_refresh_without_a_compose_file_asks_the_engine_nothing () {
    stub_reset ();
    stub_ps (PS_ALL_RUNNING);

    var session = session_for ("netlab-never-booted");

    try {
        refresh (session);
    } catch (Error e) {
        Test.fail_printf ("refresh failed: %s", e.message);
        return;
    }

    assert (session.state == LabState.DOWN);
    assert (session.container_count () == 0);

    /* `compose -f` on a file that is not there is an error, not an
     * empty answer, so the poll must not make the call at all. */
    if ("ps" in calls ()) {
        Test.fail_printf ("ps was called for a lab with no compose file:\n%s", calls ());
    }
}

int main (string[] args) {
    install_stub ();
    Test.init (ref args);

    Test.add_func ("/lab/engine/probe", test_probe_reports_the_compose_version);
    Test.add_func ("/lab/engine/absent", test_probe_without_an_engine);
    Test.add_func ("/lab/engine/docker", test_probe_falls_back_to_docker);
    Test.add_func ("/lab/engine/off-path", test_find_program_outside_path);
    Test.add_func ("/lab/engine/child-path", test_engine_runs_with_its_own_directory_on_path);
    Test.add_func ("/lab/engine/override", test_engine_override);
    Test.add_func ("/lab/engine/no-compose", test_probe_without_the_compose_plugin);
    Test.add_func ("/lab/engine/old-compose", test_probe_with_an_old_compose_plugin);
    Test.add_func ("/lab/engine/no-daemon", test_probe_without_a_daemon);
    Test.add_func ("/lab/engine/versions", test_version_comparison);

    Test.add_func ("/lab/paths/data-dir", test_paths_are_under_the_data_directory);
    Test.add_func ("/lab/paths/write", test_write_compose_creates_the_directory);

    Test.add_func ("/lab/ps/array", test_parse_ps_array_form);
    Test.add_func ("/lab/ps/ndjson", test_parse_ps_newline_delimited_form);
    Test.add_func ("/lab/ps/junk", test_parse_ps_tolerates_junk);

    Test.add_func ("/lab/session/lifecycle", test_session_starts_and_stops);
    Test.add_func ("/lab/session/partial", test_session_reports_a_partial_start);
    Test.add_func ("/lab/session/failed-up", test_session_reports_a_failed_up);
    Test.add_func ("/lab/session/adopt", test_session_adopts_a_lab_it_did_not_start);
    Test.add_func ("/lab/session/no-file", test_refresh_without_a_compose_file_asks_the_engine_nothing);

    var status = Test.run ();

    /* Only on success: a failed run's sandbox is the evidence. */
    if (status == 0) {
        try {
            new Subprocess (SubprocessFlags.NONE, "rm", "-rf", sandbox).wait (null);
        } catch (Error e) {
            /* A leftover temp directory is not worth failing the run over. */
        }
    } else {
        stderr.printf ("sandbox kept at %s\n", sandbox);
    }

    return status;
}

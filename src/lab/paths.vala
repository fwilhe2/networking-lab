/* paths.vala
 *
 * Where a lab lives on disk. One directory per project under the user's data
 * directory, holding the generated compose file:
 *
 *   $XDG_DATA_HOME/networking-lab/labs/<project>/docker-compose.yml
 *
 * The directory name is also the docker compose project name, which is what
 * makes `docker compose -p <project>` address a running lab — including one
 * this application did not start.
 *
 * Like everything else under src/lab/, this is GTK-free but not pure: it is
 * exactly the boundary src/core/ is not allowed to cross. Messages are not
 * translated here for the same reason they are not in core — the UI is what
 * presents them.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using NetworkingLab.Core;

namespace NetworkingLab.Lab {

    /* Compose accepts project names matching [a-z0-9][a-z0-9_-]*, which is a
     * subset of what sanitize_name () already produces for device names: it
     * lowercases, drops everything outside [a-z0-9_-] and strips leading
     * separators. Reusing it keeps one definition of "safe as a docker
     * identifier" rather than two that can drift apart. */
    public string project_name_for (string requested) {
        return sanitize_name (requested, DEFAULT_PROJECT_NAME);
    }

    public string labs_dir () {
        return Path.build_filename (Environment.get_user_data_dir (), "networking-lab", "labs");
    }

    public string lab_dir (string project_name) {
        return Path.build_filename (labs_dir (), project_name_for (project_name));
    }

    public string compose_path (string project_name) {
        return Path.build_filename (lab_dir (project_name), "docker-compose.yml");
    }

    /* Writes the generated file and returns its path. The directory is created
     * on demand: a lab that has never been booted does not have one. */
    public string write_compose (string project_name, string yaml) throws Error {
        var path = compose_path (project_name);

        var directory = File.new_for_path (Path.get_dirname (path));
        if (!directory.query_exists ()) {
            directory.make_directory_with_parents ();
        }

        FileUtils.set_contents (path, yaml);
        return path;
    }
}

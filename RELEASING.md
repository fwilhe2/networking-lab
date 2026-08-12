# Releasing

A release here is a git tag plus three built artifacts — a `.deb`, an `.rpm` and a Flatpak
bundle — attached to a GitHub release. There is no upstream tarball to upload anywhere and
no distribution to coordinate with, so the whole thing is a checklist rather than a process.

Everything below is done from a clean checkout of `main` with nothing uncommitted.

## 1. The version lives in five places

They are not generated from each other. All five have to be edited, and the first four have
to agree exactly:

| File | What to change |
| --- | --- |
| `meson.build` | `version: '0.1.0'` — the source of truth, and what `Config.VERSION` compiles to |
| `debian/changelog` | a new top entry: version, changes, maintainer, date |
| `networking-lab.spec` | `Version:` **and** a new `%changelog` entry |
| `data/io.github.fwilhe2.NetworkingLab.metainfo.xml.in` | a new `<release version="…" date="…">` |
| `README.md` | the package filenames in the *Install* section, which are quoted in full |

`tools/build-deb.sh` and `tools/build-rpm.sh` refuse to start when `meson.build` disagrees
with the changelog or the spec, so those two mismatches are caught in a second rather than
three minutes into a build. **The metainfo is not guarded** — `appstreamcli validate` checks
that the file is well formed, not that its newest release matches the project version. Check
it by eye, or add the guard.

The three date formats differ, which is the other easy mistake:

```sh
date -R                     # debian/changelog   Wed, 12 Aug 2026 19:22:27 +0200
date +"%a %b %d %Y"         # spec %changelog    Wed Aug 12 2026
date +%F                    # metainfo           2026-08-12
```

## 2. Check before you tag

A tag is cheap to make and annoying to move, so run the checks first.

```sh
meson setup _build --wipe                              # from scratch, not an incremental tree
meson compile -C _build
meson test -C _build --print-errorlogs                 # data, core and lab suites
meson test -C _build --setup docker --suite integration --print-errorlogs
```

The last one boots the demo topology under real docker and asserts that OSPF converges and
that the lab is isolated from the internet. It takes about 70 seconds warm, several minutes
on a cold image cache, and it is the only check that proves the generated file still works
rather than merely still matching the golden fixture.

Then build every artifact, because each one has its own way of breaking:

```sh
tools/build-deb.sh
tools/build-rpm.sh
flatpak-builder --user --force-clean _flatpak io.github.fwilhe2.NetworkingLab.json
```

- The **deb** and **rpm** builds run the test suite inside their distribution containers, so
  they also catch a dependency this repository has picked up without declaring.
- The **Flatpak** builds against the GNOME runtime, which has no `vte-2.91-gtk4` — verified
  by running `pkg-config` inside `org.gnome.Sdk//50`. It should therefore print
  `vte-2.91-gtk4 not found — building without the embedded terminal` and succeed. If it
  *fails*, the optional-dependency wiring in `src/ui/meson.build` broke. Needs
  `flatpak-builder` installed, which the development machine may not have; CI's Flatpak job
  covers the same ground on every push, so a green CI run is a fair substitute.

Finally, look at it. Layout and drawing bugs do not show up in any of the above:

```sh
tools/run-app.sh --x11 --demo &
tools/drive.py select drag palette link generate narrow
```

## 3. Tag

```sh
git commit -am "Release 0.1.1"
git tag -a v0.1.1 -m "Networking Lab 0.1.1"
git push origin main
git push origin v0.1.1
```

Annotated (`-a`), not lightweight: the tag carries a date and an author, which is what makes
`git describe` and the GitHub release page honest.

## 4. Build the artifacts from the tag

```sh
git checkout v0.1.1
rm -rf dist
tools/build-deb.sh
tools/build-rpm.sh
flatpak-builder --user --force-clean --repo=_repo _flatpak io.github.fwilhe2.NetworkingLab.json
flatpak build-bundle _repo networking-lab.flatpak io.github.fwilhe2.NetworkingLab \
    --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo
```

The Flatpak manifest's source is `{"type": "dir", "path": "."}`, so it builds whatever is
checked out — which is exactly why this step comes after checking the tag out, not before.

You end up with:

```
dist/networking-lab_0.1.1_amd64.deb
dist/networking-lab_0.1.1_amd64.buildinfo
dist/networking-lab_0.1.1_amd64.changes
dist/networking-lab-0.1.1-1.fc44.x86_64.rpm
dist/networking-lab-debuginfo-0.1.1-1.fc44.x86_64.rpm
dist/networking-lab-debugsource-0.1.1-1.fc44.x86_64.rpm
networking-lab.flatpak
```

CI builds the same `.deb` and `.rpm` on every push and uploads them as workflow artifacts.
Those are equally good; downloading them instead of building locally is a legitimate
shortcut, as long as the run is the one for the tagged commit.

## 5. Publish

```sh
gh release create v0.1.1 \
    --title "Networking Lab 0.1.1" \
    --notes-file /tmp/release-notes.md \
    dist/networking-lab_0.1.1_amd64.deb \
    dist/networking-lab-0.1.1-1.fc44.x86_64.rpm \
    networking-lab.flatpak
```

Write the notes from `git log --oneline v0.1.0..v0.1.1`. The `<release>` block you added to
the metainfo is what a software centre shows, so it should say the same thing in one
sentence — that is the description users actually read, not this one.

Attach the binary packages only. The debuginfo, buildinfo and changes files are build
by-products; nobody downloads them from a release page, and they can be rebuilt from the tag.

## 6. Afterwards

- Check the release page: the `.deb` and `.rpm` should be installable straight from their
  URLs, which is the only thing anyone will actually try.
- No version bump commit afterwards. `meson.build` keeps the released version until the next
  release changes it; nothing in the build depends on a `-dev` suffix, and an untagged commit
  is already identifiable by its hash.

## What is deliberately not automated

Nothing here is driven by a tag-triggered workflow. Publishing is the one step that cannot
be undone quietly — a bad tag can be moved before anyone notices, but a published release
with a broken package is visible immediately — so it stays a decision someone makes rather
than a consequence of pushing a tag. If that changes, the honest shape is a workflow that
builds on the tag and uploads to a **draft** release for a human to publish.

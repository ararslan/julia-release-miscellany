# Odds and ends for Julia releases

This repository is for notes, scripts, and whatever else I've found handy for making
Julia releases over the years.
Hopefully others who make releases will also find it handy.
Note that the contents here reflect the state of play as of 2022-08-17, where 1.6 is LTS
and 1.8.0 is coming out today, replacing 1.7 as stable.
If you're reading this and you haven't seen any commits since then, note that what you're
reading may be out of date.

## The release process

At a high level, these are the steps required to continue the release process after the
PR that bumps the version is merged.

1. Create and push the tag
2. Ensure a _tag build_ was triggered on both buildkite and buildbot
3. Build and GPG sign full and light source tarballs without BinaryBuilder dependencies
4. Check for existence of all binaries in `s3://julialangnightlies` (naming is version-dependent)
5. For earlier versions, e.g. 1.6, have Elliot notarize the macOS binaries
5. Move binaries to `s3://julialang2`
6. Compute and upload checksums
7. Trigger a build of `versions.json`
8. Trigger a build of the PDF documentation
9. Update the website
10. Announce on Discourse

### Creating the tag

```bash
git pull
git checkout release-1.x
git tag v$(cat VERSION)
git push origin --tags
git rev-parse HEAD  # you may need this
```

The tag event should trigger builds on both buildkite and buildbot.

### Build infrastructure wrangling

Depending on the version, some platforms will be built on buildkite and some will be
built on buildbot.
For Julia 1.6, _everything_ is built on buildbot, but most platforms have since migrated
to buildkite.
Windows (x86 and x86\_64) and FreeBSD (x86\_64) are still always built on buildbot.

Note that for 1.6, Elliot will need to notarize the macOS x86\_64 disk image file manually.
This happens automatically on buildkite for both x86\_64 and AArch64.

#### 1.6

Most buildbots have been turned off so building for 1.6 requires asking Elliot to turn
everything back on.
The buildbot web interface may show large backlogs of pending builds for platforms that
have migrated to buildkite; those can be safely canceled.

Trigger a manual build for each platform using the SHA of the tag.
Once the builds have completed, ask Elliot to turn the buildbots back off.
Ensure that the corresponding binaries exist in `s3://julialangnightlies`.
The naming scheme of the binaries is fully consistent for 1.6:

```
s3://julialangnightlies/pretesting/<os>/<arch>/1.6/julia-<hash>-<suffix>
```

Here, `hash` is the first 10 characters in the tag SHA and `suffix` is specific to the
OS, architecture, and file type.
These are handled by the script.

#### Later versions

The platforms on buildbot vs. buildkite are slightly different for 1.7 vs. 1.8+ but we'll
ignore 1.7 here.
We need only ensure that a tag build was properly captured on both buildkite and buildbot,
otherwise the directory inside an unpacked tarball as well as the REPL banner will be
incorrect.

The naming scheme for _most_ platforms after 1.6 is:

```
s3://julialangnightlies/bin/<os>/<arch>/1.x/julia-<version>-<suffix>
```

where `version` is the tag name (without a leading `v`) and `suffix` matches that for 1.6.
A better naming scheme is being put in place for recent versions but the old scheme is
implemented alongside of it.
Cases where the old scheme doesn't exist are technically bugs but they do exist.
I believe an example of that is Linux AArch64.

### Binary dance

Moving binaries from the `julialangnightlies` bucket to `julialang2` is handled by the
script, as is computing and uploading checksums.

### Source tarballs

We don't currently have a builder that produces source tarballs, so they must be made
manually via

```
make full-source-dist light-source-dist USE_BINARYBUILDER=0
```

I usually do this on antarctic with many concurrent jobs (the `-j` flag for `make`).
That command produces two tarballs in the root of the directory, the names of which must
be adjusted (IIRC it duplicates the version in the name).
The tarballs must then be GPG signed with the appropriate signing key:

```
gpg -u julia --armor --detach-sig julia-<version>.tar.gz
gpg -u julia --armor --detach-sig julia-<version>-full.tar.gz
```

### Creating a GitHub release

This is straightforward.
Just create a release associated with the tag, name it the same as the tag version, write
something in the description if you want, upload the source tarballs and .asc files as
release artifacts.
Check the prerelease box at the bottom for betas, RCs, etc. as applicable.

### Rebuilding versions.json

Go to <https://github.com/JuliaLang/VersionsJSONUtil.jl/actions/workflows/CI.yml> and
click "Run workflow," ensure "Branch: main" is selected, then hit the button.
This takes a bit under 2 hours to complete.

### Building the PDF documentation

Go to https://github.com/JuliaLang/docs.julialang.org/actions/workflows/PDFs.yml and
click "Run workflow", ensure "Branch: master" is selected, and then hit the button.
This takes at least 1 hour to complete.

### Updating the website

Edit <https://github.com/JuliaLang/www.julialang.org/blob/main/config.md> to reflect the
new version.
Use the date as shown in the REPL banner as the release date, which should be the date the
git tag was created.
Ensure that the platforms listed in the corresponding table on the [downloads
page](https://github.com/JuliaLang/www.julialang.org/blob/main/downloads/index.md)
reflect the available binaries for this release.
Add an entry to the [old releases
page](https://github.com/JuliaLang/www.julialang.org/blob/main/downloads/oldreleases.md)
if applicable.

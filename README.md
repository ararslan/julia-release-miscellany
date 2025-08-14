# Odds and ends for Julia releases

This repository is for notes, scripts, and whatever else I've found handy for making
Julia releases over the years.
Hopefully others who make releases will also find it handy.
Note that the contents here reflect the state of play as of 2025-08-14, where 1.10 is LTS
and 1.11.6 is the current stable version.
If you're reading this and you haven't seen any commits since then, note that what you're
reading may be out of date.

## The release process

At a high level, these are the steps required to continue the release process after the
PR that bumps the version is merged.

1. Create and push the tag
2. Ensure a _tag build_ was triggered on buildkite
3. Build and GPG sign full and light source tarballs without BinaryBuilder dependencies
4. Check for existence of all binaries in `s3://julialangnightlies` (naming is version-dependent)
5. Move binaries to `s3://julialang2`
6. Compute and upload checksums
7. Trigger a build of `versions.json`
8. Trigger a build of the JuliaUp versiondb
9. Update the website
10. Announce on Discourse

### Creating the tag

```bash
git pull
git checkout release-1.x
git tag v$(cat VERSION)
git push origin --tags
```

The tag event should trigger a build on buildkite.

### Binary dance

Moving binaries from the `julialangnightlies` bucket to `julialang2` is handled by the
script, as is computing and uploading checksums.
The code assumes you have a local AWS profile called `julia` with credentials obtained
from <https://d-906796850d.awsapps.com/start#/>.
Run the code with `AWS_PROFILE=julia` set in the environment, e.g.

```bash
AWS_PROFILE=julia julia --project=.
```

This ensures that the credentials are available to subprocesses, as the AWS interactions
in the script use the AWS CLI.

### Source tarballs

We don't currently have a builder that produces source tarballs, so they must be made
manually via

```
make full-source-dist light-source-dist USE_BINARYBUILDER=0
```

I usually do this on `cyclops` (a JuliaHub-provided server to which Base committers
generally have access) with a handful of concurrent jobs (the `-j` flag for `make`).
That command produces two tarballs in the root of the directory, the names of which must
be adjusted (it duplicates the version in the name).
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

### Updating the JuliaUp versiondb

Go to <https://github.com/JuliaLang/juliaup/actions/workflows/updateversiondb.yml> and
click "Run workflow," ensure "Branch: main" is select, then hit the button.
You'll need to approve each step of the build manually; check all of the boxes and approve.
A pull request will automatically be opened.
Check it for correctness, approve it, and merge it.

### Building the PDF documentation

> [!NOTE]
> I always forget to do this and no one has complained (to me, at least).

While the HTML documentation is updated regularly, the PDF version of the documentation
is only built once every 24 hours.
People often expect that the PDF version is available at the time the release is
announced, so it's worthwhile to build it prior to the announcement even though it would
be built eventually on CI anyway.

To do so, go to <https://github.com/JuliaLang/docs.julialang.org/actions/workflows/PDFs.yml>
and click "Run workflow", ensure "Branch: master" is selected, and then hit the button.
This takes at least 1 hour to complete.

If the PDF fails to build on CI but can still be compiled locally, the locally produced
PDF can be manually pushed to the
[`assets` branch](https://github.com/JuliaLang/docs.julialang.org/tree/assets)
of the repository.

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
if applicable using the script in the website repo.

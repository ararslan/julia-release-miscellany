# I apologize in advance for this code. I usually just run it piecemeal in the REPL
# and never quite bothered to polish it.

using AWS
using AWSS3
using Base.Threads
using MD5
using Pkg.BinaryPlatforms
using SHA

global_aws_config(; profile="julia", region="us-east-1")

version = v"1.8.5"

macos_already_notarized = false  # whether Elliot notarized manually and put in julialang2

destination = joinpath(homedir(), "Projects", "releases", string(version))

commit = cd(joinpath(homedir(), "Projects", "julia")) do
    run(`git fetch origin --tags --quiet`)
    return readchomp(`git rev-parse v$version`)[1:10]
end

short_version = string(version.major, '.', version.minor)

platforms = [
    FreeBSD(:x86_64),
    Linux(:x86_64),
    Linux(:i686),
    Linux(:aarch64),
    Linux(:armv7l),
    Linux(:ppc64le),
    Linux(:x86_64; libc=:musl),
    MacOS(:x86_64),
    MacOS(:aarch64),
    Windows(:x86_64),
    Windows(:i686),
]

builder(::FreeBSD) = :buildbot  # Until the julia-buildkite PR is merged
if version < v"1.7.0-"
    builder(::Any) = :buildbot  # Until 1.6 LTS moves to buildkite
else
    builder(::Any) = :buildkite
end

short_name(::FreeBSD) = "freebsd"
short_name(::Windows) = "winnt"
short_name(::MacOS) = "mac"
short_name(p::Linux) = libc(p) === :musl ? "musl" : "linux"

function short_arch(p)
    a = arch(p)
    return if a === :powerpc64le
        "ppc64le"
    elseif a === :aarch64 || a === :armv7l
        String(a)
    elseif a === :x86_64
        "x64"
    elseif a === :i686
        "x86"
    end
end

exts(::Union{Linux,FreeBSD}) = ["tar.gz", "tar.gz.asc"]
exts(::MacOS) = ["dmg", "tar.gz", "tar.gz.asc"]
exts(::Windows) = ["exe", "zip", "tar.gz"]

function nightly_name(platform, commit, version=version)
    a = arch(platform)
    suffix = if a === :x86_64 || a === :i686
        string(wordsize(platform))
    elseif builder(platform) === :buildkite && Sys.islinux(platform) && libc(platform) === :glibc
        '-' * String(a)
    else
        String(a)
    end
    os = short_name(platform)
    os == "winnt" && (os = "win")
    if v"1.6.0-" <= version < v"1.7.0-" || builder(platform) === :buildbot
        return string("julia-", commit, '-', os, suffix)
    else
        return string("julia-", version, '-', os, suffix)
    end
end

function nightly_url(platform, commit, ext)
    prefix = builder(platform) === :buildbot && version >= v"1.7.0-" ? "pretesting" : "bin"
    a = arch(platform) === :powerpc64le ? String(arch(platform)) : short_arch(platform)
    path = [prefix, short_name(platform), a, short_version, nightly_name(platform, commit)]
    return S3Path("julialangnightlies", join(path, '/') * '.' * ext)
end

function release_name(platform, version)
    os = short_name(platform)
    a = arch(platform)
    suffix = if os == "winnt" || (os == "mac" && a !== :aarch64)
        string(os[1:3], wordsize(platform))
    elseif os == "mac" && a === :aarch64
        string(os, a)
    else
        string(os, '-', a === :powerpc64le ? "ppc64le" : a)
    end
    return join(["julia", version, suffix], '-')
end

function release_url(platform, version, ext)
    path = ["bin", short_name(platform), short_arch(platform),
            short_version, release_name(platform, version)]
    return S3Path("julialang2", join(path, '/') * '.' * ext)
end

ispath(destination) || mkpath(destination)
for platform in platforms
    for ext in exts(platform)
        nightly = nightly_url(platform, commit, ext)
        release = release_url(platform, version, ext)
        @info platform ext nightly release
        if !success(```
                    aws s3api head-object
                        --bucket $(nightly.bucket)
                        --key $(join(nightly.segments, '/'))
                        --no-paginate
                        --no-cli-pager
                        --profile julia
                    ```)
            @warn "Skipping $nightly, does not exist"
            if !(Sys.isapple(platform) && macos_already_notarized)
                continue
            end
        end
        if !(Sys.isapple(platform) && macos_already_notarized && ext == "dmg")
            @info "Copying from nightly to release"
            # Don't inherit the source ACL to avoid having the release binaries publicly
            # visible before they're guaranteed "final"
            run(```
                aws s3api copy-object
                    --copy-source $(nightly.bucket)/$(join(nightly.segments, '/'))
                    --bucket $(release.bucket)
                    --key $(join(release.segments, '/'))
                    --acl bucket-owner-full-control
                    --no-paginate
                    --no-cli-pager
                    --profile julia
                ```)
        end
        # Download locally for checksumming, but skip .asc
        if !endswith(ext, ".asc")
            @info "Downloading release locally"
            if isfile(joinpath(destination, basename(release)))
                @info "Already downloaded, skipping"
                continue
            end
            try
                run(```
                    aws s3 cp
                        $release
                        $(joinpath(destination, basename(release)))
                        --profile julia
                    ```)
            catch ex
                @error "Oopsie poopsie" exception=(ex, catch_backtrace())
            end
        end
    end
end

files = filter!(readdir(destination; join=true)) do file
    isfile(file) || return false
    file == ".DS_Store" && return false  # 😑
    ext = last(splitext(file))
    return !(ext in [".sha256", ".md5", ".asc"])
end
checksums = map(files) do file
    bytes = read(file)
    return (basename(file), bytes2hex(sha256(bytes)), bytes2hex(md5(bytes)))
end
sort!(checksums; by=first)
for (i, ext) in enumerate(("sha256", "md5"))
    fname = joinpath(destination, "julia-$version.$ext")
    open(fname, "w") do io
        for t in checksums
            println(io, t[i + 1], "  ", t[1])
        end
    end
    run(```
        aws s3 cp
            $fname
            s3://julialang2/bin/checksums/
            --profile julia
            --acl public-read
        ```)
end

for platform in platforms, ext in exts(platform)
    release = release_url(platform, version, ext)
    @info "Processing" release
    if !success(```
                aws s3api head-object
                    --bucket $(release.bucket)
                    --key $(join(release.segments, '/'))
                    --no-paginate
                    --no-cli-pager
                    --profile julia
                ```)
        @warn "Skipping $release, does not exist"
        continue
    end
    run(pipeline(```
                 aws s3api put-object-acl
                     --bucket $(release.bucket)
                     --key $(join(release.segments, '/'))
                     --acl public-read
                     --profile julia
                 ```; stdout=devnull))
    parts = collect(release.segments)
    parts[end] = replace(parts[end], string(version) => "$short_version-latest")
    latest = join(parts, '/')
    run(```
        aws s3 cp
            $release
            s3://$(release.bucket)/$latest
            --acl public-read
            --profile julia
        ```)
    run(pipeline(`curl -s -X PURGE https://julialang-s3.julialang.org/$latest`;
                 stdout=devnull))
end

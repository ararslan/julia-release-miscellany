# Run this after `aws sso login --profile julia`

credentials = Dict{String,String}()

for line in eachline(`aws configure export-credentials --format env-no-export --profile julia`)
    k, v = split(line, '='; limit=2)
    if k != "AWS_CREDENTIAL_EXPIRATION"
        credentials[lowercase(k)] = v
    end
end

file = joinpath(homedir(), ".aws", "credentials")

contents = readlines(file)
yes = false
for i in eachindex(contents)
    line = contents[i]
    isempty(credentials) && break
    if line == "[julia]"
        global yes = true
        continue
    end
    yes || continue
    k = first(split(line, '='; limit=2))
    v = pop!(credentials, k)
    contents[i] = string(k, '=', v)
end

open(file, "w") do io
    join(io, contents, '\n')
    println(io)
    return nothing
end

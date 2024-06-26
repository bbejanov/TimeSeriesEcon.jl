# Copyright (c) 2020-2024, Bank of Canada
# All rights reserved.

import Dates

""" A structure for holding the results of an X13 run.

It contains the following fields:

* **spec** - The original spec file.
* **outfolder** - The output folder for the X13 run.
* **series** - TSeries and MVTSeries from the X13 output.
* **tables** - Workspace of outputs containing table data from the X13 output.
* **text** - Workspace of outputs with other structured data such as key/value pairs and model specifications.
* **other** - Workspace of outputs with other structured data such as key/value pairs and model specifications.
* **stdout** - A String containing the console output from calling X13 with the given spec.
* **errors** - A vector of error strings from the X13 output.
* **warnings** - A vector of warning strings from the X13 output.
* **notes** - A vector of note strings from the X13 output.

Descriptions of the series and tables can be found by calling `X13.descritions(res::X13result)`.
"""
mutable struct X13result
    spec::X13spec
    outfolder::String
    series::X13ResultWorkspace
    tables::X13ResultWorkspace
    text::X13ResultWorkspace
    other::X13ResultWorkspace
    stdout::String
    errors::Vector{String}
    warnings::Vector{String}
    notes::Vector{String}

    function X13.X13result(spec::X13spec, outfolder::String, stdout::String)
        res = new(spec, outfolder, X13ResultWorkspace(), X13ResultWorkspace(), X13ResultWorkspace(),  X13ResultWorkspace(), stdout, Vector{String}(), Vector{String}(), Vector{String}())
        f(t) = @async rm(outfolder; recursive=true)
        finalizer(f, res)
    end
end

""" A structure to hold location information for unloaded results."""
struct X13lazy
    file::String
    ext::Symbol
    freq::Type
end

function Base.getproperty(w::X13ResultWorkspace, sym::Symbol) 
    val =  sym === :_c ? getfield(w, :_c) : getindex(w, sym)
    if val isa X13lazy
        val = X13.loadresult(val.file, val.ext, val.freq)
        setindex!(w, val, sym)
    end
    return val
end



"""
`X13.run(spec::X13spec{F}; verbose::Bool=true, allow_errors::Bool=false, load::Union{Symbol, Vector{Symbol}}=:none)`
`X13.run(specstring::String; verbose::Bool=true, allow_errors::Bool=false, load::Union{Symbol, Vector{Symbol}}=:none)`

Run X13-ARIMA-SEATS with the provided spec structure or spec string. By default the results will not contain the actual TSeries and other objects,
but will contain X13laxy instances which will read the output and convert to the final object when accessed.

Keyword arguments:
* **verbose** (Bool) - Print any warnings and notes from the X13 log and err files to the REPL. Default is `true`.

* **allow_errors** (Bool) - When true, the process will not throw an error when encountering error messages in the X13 err file. Default is `false`.

* **load** (Symbol or Vector{Symbol}) - Specifies one or more result objects to load immediately. Valid entries are keys in the entries of `X13._output_descriptions`.

    Passing `:all` will load all results immediately. Default is `:none`.
"""
function run(spec::X13spec{F}; verbose::Bool=true, allow_errors::Bool=false, load::Union{Symbol, Vector{Symbol}}=:none) where F
    x13write(spec)
    _run(spec; verbose=verbose, allow_errors=allow_errors, load=load)
end
function run(specstring::String, freq::Type{F}; verbose::Bool=true, allow_errors::Bool=false, load::Union{Symbol, Vector{Symbol}}=:none) where F <: Frequency
    spec = newspec(TSeries(MIT{sanitize_frequency(freq)}(1)))
    spec.string= specstring
    spec.folder = mktempdir(; prefix="x13_", cleanup=true) # will be deleted when process exits
    open(joinpath(spec.folder, "spec.spc"), "w") do f
        println(f, spec.string)
    end
    _run(spec; verbose=verbose, allow_errors=allow_errors, load=load)
end
function _run(spec::X13spec{F}; verbose::Bool=true, allow_errors::Bool=false, load::Union{Symbol, Vector{Symbol}}=:none) where F

    _load = load isa Symbol ? Set([load]) : Set(load)

    gpath = joinpath(spec.folder, "graphics")
    if !ispath(gpath)
        mkdir(gpath)
    end

    stdin_buffer = IOBuffer()
    stdout_buffer = IOBuffer()
    stderr_buffer = IOBuffer()
    process = nothing
    try
        if TimeSeriesEcon.getoption(:x13path) !== ""
            c = `$(TimeSeriesEcon.getoption(:x13path)) -I "$(joinpath(spec.folder,"spec"))" -G "$(gpath)" -S`
        else
            c = `$(X13as_jll.get_x13as_ascii_path()) -I "spec"  -G "graphics" -S`
        end
        cd(spec.folder) do
           process = Base.run(pipeline(c, stdout=stdout_buffer, stderr=stderr_buffer))
        end
    catch err
        if err isa ProcessFailedException
            # just ignore this for now, catch it when reading the errors file or stderr.
        else
            rethrow()
        end
    end
    stdout = String(take!(stdout_buffer))
    stderr = String(take!(stderr_buffer))
    
    if length(stderr) > 0
        println(spec)
        println(stderr)
        error("running X13 failed. See above. Additional information may be available in $(spec.folder)")
    end
    stdout_lines = split(stdout, "\n")
    for (i,l) in enumerate(stdout_lines)
        # sometimes there's an error message but it doesn't get printed to the error file
        # this can happen if a line in the spec file is too long
        if occursin("ERROR:", l)
            error_msg = stdout_lines[i]
            for j in i+1:length(stdout_lines)
                if findfirst("     ", stdout_lines[j]) == 1:5
                    error_msg = error_msg*"\n"*stdout_lines[j]
                else
                    break
                end
            end
            if allow_errors
                @error error_msg
            else
                throw(error(error_msg))
            end
        end
    end
    
    res = X13.X13result(spec, spec.folder, stdout)

    main_objects = readdir(spec.folder, join=true)
    files = filter(obj -> !isdir(obj), main_objects)
    sub_folders = filter(obj -> isdir(obj), main_objects)
    for folder in sub_folders
         sub_folder_objects = readdir(folder, join=true)
         files = [files..., filter(obj -> !isdir(obj), sub_folder_objects)...]
    end
  

    freq = frequencyof(spec.series.data)
    for file in files
        ext = Symbol(splitext(file)[2][2:end])
        load isa Symbol && load == :all && push!(_load, ext)
        # println(ext)
        if ext in _series_extensions
            res.series[ext] = X13lazy(file,ext,freq)
        elseif ext in _probably_series_extensions
            try
                lazy = X13lazy(file,ext,freq)
                ts = loadresult(lazy)
                res.series[ext] = ts
            catch err
                @warn "Encountered an unknown output type: $(ext). Attempted to load it as a series but failed.
                
                Informing the developers of the TimeSeriesEcon package of this output type could help them improve the X13 module."
                continue
            end
            @warn "Encountered an unknown output type: $(ext). Loaded it as a series.
                
                Informing the developers of the TimeSeriesEcon package of this output type could help them improve the X13 module."
        elseif ext in _table_extensions
            res.tables[ext] = X13lazy(file,ext,freq)
        elseif ext in [:udg, _kv_list_extensions..., :est, :mdl, :ipc, :iac]
            res.other[ext] = X13lazy(file,ext,freq)
        elseif ext == :err
            x13read_err(file, res.warnings, res.notes, res.errors)
            res.text[ext] = read(file, String)
        elseif ext == :tbs || (ext == :OUT && split(file, "/")[end] ∈ ("TABLE-S.OUT","\\\\TABLE-S.OUT"))
            res.series.tbs = X13lazy(file,:tbs,freq)
            load isa Symbol && load == :all && push!(_load, :tbs)
        elseif ext == :rog || (ext == :OUT && split(file, "/")[end] ∈ ("ROGTABLE.OUT","\\\\ROGTABLE.OUT"))
            res.tables.rog = X13lazy(file,:rog,freq)
            load isa Symbol && load == :all && push!(_load, :rog)
        elseif ext ∈ _human_text_extensions
            res.text[ext] = X13lazy(file,ext,freq)
        elseif ext ∉ _human_text_extensions && ext !== :txt && ext !== :log
            println("=================================================================================================================")
            # println(ext)
            println(read(file, String))
            println(file)
        end
    end

    if load !== :none
        for key in intersect(_load, keys(res.series))
            res.series[key] = loadresult(res.series[key])
        end
        for key in intersect(_load, keys(res.tables))
            res.tables[key] = loadresult(res.tables[key])
        end
        for key in intersect(_load, keys(res.other))
            res.other[key] = loadresult(res.other[key])
        end
    end

    if verbose
        for w in res.warnings
            @warn w
        end

        for n in res.notes
            @info n
        end
    end

    if length(res.errors) > 0
        for err in res.errors
            @error err
        end
        if allow_errors
            @warn "There were errors in the specification file."
        else #if length(res.errors) > 1 || findfirst("span of data end date", res.errors[1]) !== 1:21
            error("There were errors in the specification file.")
        end
    end

    return res
    
end
export run

""" 
`loadresult(val::X13lazy)`
`loadresult(file::String, ext::Symbol, freq::Type{<:Frequency})`

Replaces an X13laxy object with the loaded data structure.
"""
loadresult(val::X13lazy) = loadresult(val.file, val.ext, val.freq)
function loadresult(file::String, ext::Symbol, freq::Type{<:Frequency})
    if ext in _series_extensions
        return x13read_series(file, freq)
    elseif ext in _table_extensions
        lines = split(read(file, String),"\n")
        return x13read_workspace_table(lines, ext=ext)
    elseif ext == :udg
        #TODO: make this meaningful
       return x13read_udg(file)
    elseif ext in _kv_list_extensions
        lines = split(read(file, String), "\n")
        return x13read_key_values(lines,  r"\s+")
    elseif ext == :est
        return x13read_estimates(file)
    elseif ext == :mdl
        return x13read_model(file)
    elseif ext ∈ (:ipc, :iac)
        return x13read_identify(file)
    elseif ext == :tbs #|| (ext == :OUT && split(file, "/")[end] == "TABLE-S.OUT")
        # SEATS output file
        lines = split(read(file, String),"\n")
        if length(lines) > 2
            return x13read_seatsseries(lines, freq)
        end
    elseif ext == :rog #|| (ext == :OUT && split(file, "/")[end] == "ROGTABLE.OUT")
        # SEATS output file
        lines = split(read(file, String),"\n")
        return x13read_workspace_table(lines, ext=ext)
    elseif ext ∈ _human_text_extensions
        return read(file, String)
    elseif ext ∉ _human_text_extensions && ext !== :txt && ext !== :log
        @warn "Encountered unknown output file. Contents and path below."
        println("=================================================================================================================")
        # println(ext)
        println(read(file, String))
        println(file)
    end
    return nothing
end

function x13read_err(file::AbstractString, warnings::Vector{String}, notes::Vector{String}, errors::Vector{String})
    # println(read(file, String))

    lines = split(read(file, String), r"\n")
    collected_lines = Vector{String}()
    for line in lines[1:end]
        if length(line) >= 11
            if line[1:9] == " WARNING:" || line[1:7] == " ERROR:" || line[1:6] == " NOTE:"
                push!(collected_lines, line)
            elseif length(collected_lines) > 0
                collected_lines[end] = collected_lines[end]*"\n$line"
            end
        elseif length(collected_lines) > 0
            collected_lines[end] = collected_lines[end]*"\n$line"
        end
    end

    for line in collected_lines
        if line[1:9] == " WARNING:"
            push!(warnings, line[11:end])
        elseif line[1:7] == " ERROR:"
            push!(errors, line[9:end])
        elseif line[1:6] == " NOTE:"
            push!(notes, line[8:end])
        end
    end
end

""" Read an X13 key/value output file """
function x13read_key_values(lines::Vector{<:AbstractString}, separator=r"[\t\:]")
    ws = Workspace()
    for line in lines
        if length(strip(line)) == 0
            continue
        end
        split_range = findfirst(separator, line)
        if split_range === nothing && separator == ": "
            split_range = findfirst(":", line)
        end
        if split_range === nothing
            @warn "Could not parse: $line"
            continue
        end
        split_point = split_range[begin]
        # split_point = findfirst(separator, line)[begin]
        if line[split_point] ∉ (':', '\t', ' ')
            println("OBS! ", line[split_point-1], ", ", line)
        end
        key = Symbol(line[1:split_point-1])
        val = strip(line[split_point+1:end])
        foundval = false
        if key == :date
            val = Dates.Date(replace(val, r"\s+"=>" "), Dates.DateFormat("u d, y"))
            foundval = true
        end
        if !foundval
            try 
                val = parse(Int64, val)
                foundval = true
            catch ArgumentError
            end
        end

        if !foundval
            try 
                val = parse(Float64, val)
                foundval = true
            catch ArgumentError
            end
        end

        if !foundval
            # could be a vector of numbers
            splitval = split(replace(val, "*******" => "NaN"), r"[\t\s]+")
            if length(splitval) > 1
                try 
                    val = [parse(Float64, strip(v)) for v in splitval]
                    foundval = true
                catch ArgumentError
                end
            end
        end

        if !foundval && val == "no"
            val = false
            foundval = true
        end

        if !foundval && val == "yes"
            val = true
            foundval = true
        end

        # if !foundval
        #     println(key, ": ", val)
        # end

        ws[key] = val
    end

    _add_layers!(ws)

    return ws
end

function x13read_udg(file)
    lines = split(read(file, String),"\n")
    return x13read_key_values(lines, ": ")
end
#TODO: deal with things like k.other.udf.roots.ar.nonseaonal.01 which can't be accessed without Symbol("01")

function x13read_workspace_table(lines::Vector{<:AbstractString}; ext=:nospecialrules)
    if strip(lines[end]) == ""
        lines=lines[1:end-1]
    end
    ws = WorkspaceTable()
    headers = _sanitize_colname.(split(strip(lines[1]), "\t"))
    if ext == :acm
        # this table is missing a header...
        insert!(headers, 2, "lag")
    elseif ext == :rog
        lines = map(l -> strip(replace(l, r"\s+:"=>":", r"\s\s+" => "\t")), lines[2:end])
        headers = [:measure, _sanitize_colname.(split(strip(lines[1]), "\t"))...]
    end

    vectors = Vector{Any}()
    numvals =  length(lines)-2
    for h in 1:length(headers)
        push!(vectors, fill("", numvals))
    end

    # put values in vectors
    for (i,line) in enumerate(lines[3:end])
        if length(strip(line)) == 0
            continue
        end
        for (j,val) in enumerate(split(line, "\t"))
            j > length(headers) && strip(val) == "" && continue
            vectors[j][i] = val
        end
    end
    
    # attempt to parse the vectors
    for (i,v) in enumerate(vectors)
        foundval = false

        if !foundval
            try
                vectors[i] = parse.(Int64, v)
                foundval = true
            catch ArgumentError
            end
        end
        if !foundval
            try
                vectors[i] = parse.(Float64, v)
                foundval = true
            catch ArgumentError
            end
        end
    end

    for (i,head) in enumerate(headers)
        ws[Symbol(head)] = vectors[i]
    end
    return ws
end

function x13read_series(file, F::Type{<:Frequency})
    # println(read(file, String))
    lines = split(read(file, String),"\n")
    headers = split(lines[1], "\t")[2:end]
    headers = _sanitize_colname.(headers)
    vals = Matrix{Float64}(undef, (length(lines)-3, length(headers)))
    

    # check first line
    _s = split(lines[3], "\t")
    lastcol = length(_s)
    if lastcol > length(headers) + 1 && strip(_s[end]) == ""
        lastcol = lastcol - 1
    end
    for (i, line) in enumerate(lines[3:end-1])
        vals[i,:] =  [_tryparse(Float64, v, NaN) for v in split(line, "\t")[2:lastcol]]
    end
    
    period_string = split(lines[3], "\t")[1]
    if length(period_string) > 2
        if lowercase(period_string[1:3]) in keys(_months_and_quarters)
            p = _months_and_quarters[lowercase(period_string[1:3])]
            y = 1
        else
            p = parse(Int64, period_string[end-1:end])
            y = parse(Int64, period_string[1:end-2])
        end
        
        if length(headers) > 1
            return MVTSeries(MIT{F}(y,p), headers, vals)
        elseif length(headers) == 0
            return TSeries(MIT{F}(y,p):(MIT{F}(y,p)+size(vals)[1] - 1))
        else
            return TSeries(MIT{F}(y,p), vals[:,1])
        end
    else
        throw(ArgumentError("Period string has an unexpected format: $(period_string)."))
    end
end

function x13read_seatsseries(lines::Vector{<:AbstractString}, F::Type{<:Frequency})
    # println(read(file, String))
    delim = r"\s\s+"
    headers_line = 2
    if !occursin(delim, lines[headers_line]) #&& headers_line < length(lines)
        headers_line = headers_line + 1
    end
    headers = split(lines[headers_line], delim)[3:end]
    headers = _sanitize_colname.(headers)
    vals = Matrix{Float64}(undef, (length(lines)-headers_line-2, length(headers)))

    # check first line
    _s = split(lines[headers_line+1], delim) 
    lastcol = length(_s)
    if lastcol > length(headers) + 1 && _s[end] == ""
        lastcol = lastcol - 1
    end
    for (i, line) in enumerate(lines[headers_line+1:end-2])
        vals[i,:] =  [_tryparse(Float64, v, NaN) for v in split(line, delim)[2:lastcol]]
    end
    date = split(split(lines[headers_line+1], delim)[1], "-")
    if length(date) > 1
        p = parse(Int64, strip(date[1]))
        y = parse(Int64, strip(date[2]))
    
        if length(headers) > 1
            return MVTSeries(MIT{F}(y,p), headers, vals)
        elseif length(headers) == 0
            return TSeries(MIT{F}(y,p):(MIT{F}(y,p)+size(vals)[1] - 1))
        else
            return TSeries(MIT{F}(y,p), vals[:,1])
        end
    else
        throw(ArgumentError("Period string has an unexpected format: $(period_string)."))
    end
end

function x13read_estimates(file)
    lines = split(read(file, String),"\n")
    # println(join(lines, '\n'))
    indices = Workspace()
    for (i,line) in enumerate(lines)
        if line == "\$arima:"
            indices.arima = i
        elseif line == "\$regression:"
                indices.regression = i
        elseif line == "\$arima\$estimates:"
            indices.arimaestimates = i
        elseif line == "\$regression\$estimates:"
            indices.regressionestimates = i
        elseif line == "\$variance:"
            indices.variance = i
        end
    end
    res = Workspace()
    if :arima ∈ keys(indices)
        # res.arima = Workspace()
        res.arima = x13read_workspace_table(lines[indices.arimaestimates+1:indices.variance-1])
        res.variance = x13read_key_values(lines[indices.variance+1:end])
    elseif :regression ∈ keys(indices)
        # res.regression = Workspace()
        res.regression = x13read_workspace_table(lines[indices.regressionestimates+1:indices.variance-1])
        res.variance = x13read_key_values(lines[indices.variance+1:end])
    end
    return res
end

function x13read_identify(file)
    res = Workspace()
    lines = split(read(file, String),"\n")
    
    # first two lines are diff/sdiff
    page_switches = findall(s -> length(s) > 4 && s[1:5] == "\$diff", lines)
    
    for (i, loc) in enumerate(page_switches)
        # loc2 = i < length(page_switches)
        sym = Symbol("$(replace(lines[loc], "\$" => "", "= " => ""))$(replace(lines[loc+1], "\$" => "", "= " => ""))")
        table_lines_end = i < length(page_switches) ? page_switches[i+1] - 1 : length(lines)
        res[sym] = x13read_workspace_table(lines[loc+2:table_lines_end])
    end
    
    return res
end

function x13read_model(file)
    # TODO: make sure we can read all model specs.
    # println(read(file, String))
    lines = split(read(file, String),"\n")
    res = Workspace()
    indices = Workspace()
    
    # find arima and regression
    for (i,l) in enumerate(lines)
        line = strip(l)
        if line == "arima{model=" || line =="arima{"
            indices.arima = i
        elseif line == "regression{"
            indices.regression = i
        end
    end

    if :arima in keys(indices)
        end_line = length(lines)
        if :regression in keys(indices)
            end_line = indices.arima > indices.regression ? length(lines) : indices.regression - 1
        end
        res.arima = _x13read_model(lines[indices.arima:end_line])
    end

    if :regression in keys(indices)
        end_line = length(lines)
        if :arima in keys(indices)
            end_line = indices.regression > indices.arima ? length(lines) : indices.arima - 1
        end
        res.regression = _x13read_model(lines[indices.regression:end_line])
    end

    return res
end

function _x13read_model(lines::Vector{<:AbstractString})
    res = Workspace()
    indices = Workspace()
    for (i,l) in enumerate(lines)
        line = strip(l)
        if line == "arima{model=" || line == "model="
            indices.model = i
        elseif line == "ar  =("
            indices.ar = i
        elseif line == "ma  =("
            indices.ma = i
        elseif line == "regression{"
            indices.regression = i
        elseif line == "variables=(" || line == "regression{variables=("
            indices.variables = i
        elseif line == "b=("
            indices.b = i
        end
    end

    ordered_keys = Vector{Symbol}()
    for key in keys(indices)
        if length(ordered_keys) == 0
            push!(ordered_keys, key)
        else
            did_add = false
            for i in 1:length(ordered_keys)
                if indices[key] < indices[ordered_keys[i]]
                    insert!(ordered_keys, key, i)
                    did_add = true
                end
            end
            if !did_add
                push!(ordered_keys, key)
            end
        end
    end

    for (i, key) in enumerate(ordered_keys)
        if key == :model 
            model_string = lines[indices[key]+1]
            split_string = split(model_string, "(")
            arima_specs = Vector{ArimaSpec}()
            for s in split_string
                if length(strip(s)) == 0
                    continue
                end
                _s = split(strip(replace(s, ")" => " ", "," => " ")), " ")
                if !occursin("[", s)
                    push!(arima_specs, ArimaSpec(parse.(Int64, _s)...))
                else
                    specvals = Vector{Union{Int64,Vector{Int64}}}()
                    for __s in _s
                        if __s[1] == '['
                            push!(specvals, parse(Int64, __s[begin+1:end-1]))
                        else
                            push!(specvals, parse(Int64, __s))
                        end
                    end
                    push!(arima_specs, ArimaSpec(specvals...))
                end
            end
            res.model = ArimaModel(arima_specs)
        elseif key ∈ (:ar, :ma, :b, :variables)
            if key !== ordered_keys[end]
                val_lines = lines[indices[key]+1:indices[ordered_keys[i+1]]-2]
            else
                val_lines = lines[indices[key]+1:end-3]
            end
            values = strip.(val_lines)
            values = string.(filter(v -> v ∉ ("", ")", "}"), values))
            if key ∈ (:ar, :ma, :b) # numbers
                fixed = repeat([false], length(values))
                parsed_vals = Vector{Float64}(undef, length(values))
                for (i,v) in enumerate(values)
                    if v[end] == 'f'
                        parsed_vals[i] = parse(Float64, v[1:end-1])
                        fixed[i] = true
                    else
                        parsed_vals[i] = parse(Float64, v)
                    end
                    values = parsed_vals
                end
                res[Symbol("fix$(key)")] = fixed
            end
            res[key] = values
        end
    end
    return res
end

# Replaces keys with periods in them with workspaces
function _add_layers!(ws::Workspace)
    keys_added = Vector{Symbol}()
    for key in collect(keys(ws))
        dotindex = findfirst('.', string(key))
        if dotindex isa Int64
            trunk = Symbol(string(key)[1:dotindex-1])
            leaf = Symbol(string(key)[dotindex+1:end])
            if trunk ∉ keys(ws)
                ws[trunk] = Workspace()
                push!(keys_added, trunk)
            elseif !(ws[trunk] isa Workspace)
                trunk = Symbol("$(string(trunk))_")
                ws[trunk] = Workspace()
                push!(keys_added, trunk)
            end
            # @show trunk
            # @show leaf
            # @show ws[key]
            # @show ws[trunk]
            ws[trunk][leaf] = ws[key]
            delete!(ws, key)
        end
    end
    for key in keys_added
        _add_layers!(ws[key])
    end
end

# Removes spaces and some characters from column names.
function _sanitize_colname(s::AbstractString)
    return replace(s, r"[\s\-\.]+" => "_")
end

# tryparse, but with a default.
function _tryparse(t::Type, s::AbstractString, default) 
    v = tryparse(t, s)
    v === nothing && return default
    return v
end

function Base.show(io::IO, ::MIME"text/plain", ws::WorkspaceTable)
    if length(keys(ws)) == 0
        print(io, "Empty WorkspaceTable");
        return
    end
    colwidths = [length(string(k)) + 1 for k in keys(ws)]
    numrows = maximum(length.(values(ws)))
    types = [typeof(v) for v in values(ws)]

    limit = get(io, :limit, true)
    dheight, dwidth = displaysize(io)

    if limit && numrows + 5 > dheight
        # we're printing some but not all rows (no room on the screen)
        top = div(dheight - 5, 2)
        bot = numrows - dheight + 7 + top
    else
        top, bot = numrows + 1, numrows + 1
    end

    stringvals = Vector{Vector{String}}()
    for (i,v) in enumerate(values(ws))
        vec = Vector{String}()
        for val in v
            push!(vec, sprint(print, val; context=:compact=>true))
        end
        push!(stringvals, vec)
    end
    for (i,v) in enumerate(stringvals)
        if length(v) == 0
            continue
        end
        colwidths[i] = max(colwidths[i], maximum(length.(v)))
    end
    if limit && sum(colwidths) + length(colwidths) > dwidth
        # print some but not all columns (no room on screen)
        leftcols = 1
        rightcols = length(colwidths)
        sumwidth = colwidths[1] + colwidths[end] + 3
        for i in 2:(floor(Int,length(colwidths)/2) + 1)
            if sumwidth + colwidths[i] + 1 < dwidth
                leftcols = i
                sumwidth += colwidths[i] + 1
            else
                break
            end
            if sumwidth + colwidths[end-(i-1)] + 1 < dwidth && i <= length(colwidths)/2
                rightcols = length(colwidths) - (i-1)
                sumwidth += colwidths[end-(i-1)] + 1
            else
                break
            end
        end
    else
        leftcols = length(colwidths)
        rightcols = length(colwidths)
    end
    # now print the thing
    numcols = length(colwidths)
    printed_filler_col = false
    for (j,h) in enumerate(keys(ws))
        leftcols < j < rightcols && printed_filler_col && continue
        if leftcols < j < rightcols
            print(io, " … ")
            printed_filler_col = true
            continue
        end
        if j == numcols
            print(io, rpad(h,colwidths[j], " "))
        else
            print(io, rpad(h,colwidths[j]+1, " "))
        end
    end
    print(io, "\n")
    printed_filler_col = false
    for (j,c) in enumerate(colwidths)
        leftcols < j < rightcols && printed_filler_col && continue
        if leftcols < j < rightcols
            print(io, " … ")
            printed_filler_col = true
            continue
        end
        print(io, "-"^c)
        j == numcols && continue
        print(io, " ")
    end
    print(io, "\n")
    printed_filler_row = false
    for i in 1:numrows
        printed_filler_col = false
        top < i < bot && printed_filler_row && continue
        if top < i < bot
            for (j,vec) in enumerate(stringvals)
                leftcols < j < rightcols && printed_filler_col && continue
                if leftcols < j < rightcols
                    print(io, " … ")
                    printed_filler_col = true
                    continue
                end
                print(io, lpad("⋮", colwidths[j], " "))
                j == numcols && continue
                print(io, " ")
            end
            print(io, "\n")
            printed_filler_row = true
            continue
        end
        for (j,vec) in enumerate(stringvals)
            leftcols < j < rightcols && printed_filler_col && continue
            if leftcols < j < rightcols
                print(io, " … ")
                printed_filler_col = true
                continue
            end
            if length(vec) >= i
                if types[j] == Vector{String}
                    print(io, rpad(vec[i], colwidths[j], " "))
                else
                    print(io, lpad(vec[i], colwidths[j], " "))
                end
                j == numcols && continue
                print(io, " ")
            else
                print(io, lpad(" ", colwidths[j], " "))
                j == numcols && continue
                print(io, " ")
            end
        end
        print(io, "\n")
    end
end

Base.show(io::IO, x::X13lazy) = show(io, MIME"text/plain"(), x)
function Base.show(io::IO, ::MIME"text/plain", x::X13lazy)
    print(io, x.file)
end

Base.show(io::IO, r::X13result) = show(io, MIME"text/plain"(), r)
function Base.show(io::IO, ::MIME"text/plain", r::X13result)
    print(io, "X13 results")

    limit = get(io, :limit, true)
    io = IOContext(io, :SHOWN_SET => r,
        :typeinfo => eltype(r),
        :compact => get(io, :compact, true),
        :limit => limit)


    dheight, dwidth = displaysize(io)
    nfields = 10

    if limit && nfields + 5 > dheight
        # we're printing some but not all rows (no room on the screen)
        top = div(dheight - 5, 2)
        bot = nfields - dheight + 7 + top
    else
        top, bot = nfields + 1, nfields + 1
    end

    max_align = 0
    prows = Vector{String}[]
    for (i, k) ∈ enumerate(fieldnames(X13result))
        v = getfield(r, k)
        top < i < bot && continue

        sk = sprint(print, k, context=io, sizehint=0)
        if k == :series
            # count series
            sv = "X13ResultWorkspace with $(length(keys(v))) TSeries/MVTSeries"
        elseif k == :tables
            # count series
            sv = "X13ResultWorkspace with $(length(keys(v))) tables"
        elseif k == :text || k == :other
            # count series
            sv = "X13ResultWorkspace with $(length(keys(v))) entries"
        elseif v isa Union{AbstractString,Symbol,AbstractRange,Dates.Date,Dates.DateTime}
            # It's a string or a Symbol
            sv = sprint(show, v, context=io, sizehint=0)
        elseif typeof(v) == eltype(v) || typeof(v) isa Type{<:DataType}
            #  it's a scalar value
            sv = sprint(print, v, context=io, sizehint=0)
        else
            sv = sprint(summary, v, context=io, sizehint=0)
        end
        max_align = max(max_align, length(sk))

        push!(prows, [sk, sv])
        i == top && push!(prows, ["⋮", "⋮"])
    end

    cutoff = dwidth - 5 - max_align

    for (sk, sv) ∈ prows
        lv = length(sv)
        sv = lv <= cutoff ? sv : sv[1:cutoff-1] * "…"
        print(io, "\n  ", lpad(sk, max_align), " ⇒ ", sv)
    end
end

function descriptions(res::X13result)
    desc = Workspace()
    desc.series = Workspace()
    desc.tables = Workspace()
    _spec = res.spec
    for key ∈ keys(res.series)
        for spec in keys(_output_descriptions)
            if getfield(_spec, spec) isa X13default 
                continue
            end
            if key ∈ keys(_output_descriptions[spec])
                desc.series[key] = "$(uppercase(string(spec))): " * _output_descriptions[spec][key]
            end
        end
    end 
    for key ∈ keys(res.tables)
        for spec in keys(_output_descriptions)
            if getfield(_spec, spec) isa X13default 
                continue
            end
            if key ∈ keys(_output_descriptions[spec])
                desc.tables[key] = "$(uppercase(string(spec))): " * _output_descriptions[spec][key]
            end
        end
    end 
    if :udg in keys(res.other)
        desc.other = Workspace()
        desc.other.udg = Workspace()
        for key in keys(res.other.udg)
            if key ∈ keys(_output_udg_description)
                desc.other.udg[key]  = _output_udg_description[key]
            end
        end
        if length(keys(desc.other.udg)) == 0
            delete!(desc.other, :udg)
        end
        if length(keys(desc.other)) == 0
            delete!(desc, :other)
        end
    end
    return desc
end

Base.show(io::IO, x::Union{X13arima,X13automdl,X13check,X13default,X13estimate,X13force,X13forecast,X13history,X13identify,X13metadata,X13outlier,X13pickmdl,X13regression,X13seats,X13slidingspans,X13spectrum,X13transform,X13x11,X13x11regression}) = show(io, MIME"text/plain"(), x)
function Base.show(io::IO, ::MIME"text/plain", spec::Union{X13arima,X13automdl,X13check,X13default,X13estimate,X13force,X13forecast,X13history,X13identify,X13metadata,X13outlier,X13pickmdl,X13regression,X13seats,X13slidingspans,X13spectrum,X13transform,X13x11,X13x11regression})
    print(io, "\n$(replace(string(typeof(spec)), "TimeSeriesEcon.X13."=>"", "X13" =>"")):")
    fields = collect(fieldnames(typeof(spec)))
    longest = maximum([length(string(x)) for x in fields])
    for field in fields
        v = getfield(spec, field)
        if v isa X13default
            continue
        end
        if v isa TSeries || v isa MVTSeries
            data = sprint(summary, v, context=io, sizehint=0)
            print(io, "\n    $(rpad(field, longest, " ")) => $(data)")
        else
            print(io, "\n    $(rpad(field, longest, " ")) => $(v)")
        end

    end
end
Base.show(io::IO, x::X13series) = show(io, MIME"text/plain"(), x)
function Base.show(io::IO, ::MIME"text/plain", spec::X13series)
    print(io, "\nseries:")
    data = sprint(summary, spec.data, context=io, sizehint=0)
    print(io, "\n    data: => $(data)")
    for field in fieldnames(X13series)
        v = getfield(spec, field)
        if v isa X13default || field == :data
            continue
        end
        print(io, "\n    $(field): => $(v)")
    end
end

Base.show(io::IO, x::X13spec) = show(io, MIME"text/plain"(), x)
function Base.show(io::IO, ::MIME"text/plain", spec::X13spec)
    print(io, "X13 spec")
    # series
    if !(spec.series isa X13default)
        show(io, spec.series)
    end
    #everything else
    for subspecname in fieldnames(X13spec)
        subspec = getfield(spec, subspecname)
        if !(subspec isa X13default) && subspecname ∉ (:series, :string, :folder)
            show(io, subspec)
        end
    end
end
# Copyright (c) 2020-2022, Bank of Canada
# All rights reserved.

using OrderedCollections

# -------------------------------------------------------------------------------
# MVTSeries -- multivariate TSeries
# -------------------------------------------------------------------------------

mutable struct MVTSeries{
    F<:Frequency,
    T<:Number,
    C<:AbstractMatrix{T}
} <: AbstractMatrix{T}

    firstdate::MIT{F}
    columns::OrderedDict{Symbol,TSeries{F,T}}
    values::C

    # inner constructor enforces constraints
    function MVTSeries(firstdate::MIT{F},
        names::NTuple{N,Symbol},
        values::AbstractMatrix
    ) where {F<:Frequency,N}
        if N != size(values, 2)
            ArgumentError("Number of names and columns don't match:" *
                          " $N ≠ $(size(values, 2)).") |> throw
        end
        columns = OrderedDict(nm => TSeries(firstdate, view(values, :, ind))
                              for (nm, ind) in zip(names, axes(values, 2)))
        new{F,eltype(values),typeof(values)}(firstdate, columns, values)
    end

end

@inline _names_as_tuple(names::Symbol) = (names,)
@inline _names_as_tuple(names::AbstractString) = (Symbol(names),)
@inline _names_as_tuple(names) = tuple((Symbol(n) for n in names)...)


# standard constructor with default empty values
MVTSeries(fd::MIT, names = ()) = (names = _names_as_tuple(names); MVTSeries(fd, names, zeros(0, length(names))))
MVTSeries(fd::MIT, names::Union{AbstractVector,Tuple,Base.KeySet{Symbol,<:OrderedDict}}, data::AbstractMatrix) = begin
    names = _names_as_tuple(names)
    MVTSeries(fd, names, data)
end

# MVTSeries(fd::MIT, names, data::MVTSeries) = begin
#     names = _names_as_tuple(names)
#     firstdate(data) == fd && colnames(data) == names ? data :
#         throw(ArgumentError("Failed to construct MVTSeries with $((fd, names)) from $(axes(data))"))
# end

# see more constructors below

# easy access to internals. 
@inline _vals(x::MVTSeries) = getfield(x, :values)
@inline _cols(x::MVTSeries) = getfield(x, :columns)
function _col(x::MVTSeries, col::Symbol)
    ret = get(getfield(x, :columns), col, nothing)
    if ret === nothing
        Base.throw_boundserror(x, [col,])
    end
    return ret
end

columns(x::MVTSeries) = getfield(x, :columns)

@inline colnames(x::MVTSeries) = keys(_cols(x))
@inline rawdata(x::MVTSeries) = _vals(x)

# some methods to make MVTSeries function like a Dict (collection of named of columns)
@inline Base.pairs(x::MVTSeries) = pairs(_cols(x))
@inline Base.keys(x::MVTSeries) = keys(_cols(x))
@inline Base.haskey(x::MVTSeries, sym::Symbol) = haskey(_cols(x), sym)
@inline Base.get(x::MVTSeries, sym::Symbol, default) = get(_cols(x), sym, default)
@inline Base.get(f::Function, x::MVTSeries, sym::Symbol) = get(f, _cols(x), sym)
# no get!() - can't add columns like this!!

# methods related to TSeries 
@inline firstdate(x::MVTSeries) = getfield(x, :firstdate)
@inline lastdate(x::MVTSeries) = firstdate(x) + size(_vals(x), 1) - one(firstdate(x))
@inline frequencyof(::Type{<:MVTSeries{F}}) where {F<:Frequency} = F
@inline rangeof(x::MVTSeries) = firstdate(x) .+ (0:size(_vals(x), 1)-1)

# -------------------------------------------------------------------------------
# Make MVTSeries work properly as an AbstractArray


@inline Base.size(x::MVTSeries) = size(_vals(x))
@inline Base.axes(x::MVTSeries) = (rangeof(x), tuple(colnames(x)...))
@inline Base.axes1(x::MVTSeries) = rangeof(x)

# the following are needed for copy() and copyto!() (and a bunch of Julia internals that use them)
@inline Base.IndexStyle(x::MVTSeries) = IndexStyle(_vals(x))
@inline Base.dataids(x::MVTSeries) = Base.dataids(_vals(x))

@inline Base.eachindex(x::MVTSeries) = eachindex(_vals(x))

# normally only the first of the following is sufficient.
# we add few other versions of similar below
@inline Base.similar(x::MVTSeries) = MVTSeries(firstdate(x), colnames(x), similar(_vals(x)))
@inline Base.similar(x::MVTSeries, ::Type{T}) where {T} = MVTSeries(firstdate(x), colnames(x), similar(_vals(x), T))

# -------------------------------------------------------------------------------
# Indexing with integers and booleans - same as matrices

# Indexing with integers falls back to AbstractArray
const _FallbackType = Union{Integer,Colon,AbstractUnitRange{<:Integer},AbstractArray{<:Integer},CartesianIndex}
@inline Base.getindex(sd::MVTSeries, i1::_FallbackType...) = getindex(_vals(sd), i1...)
@inline Base.setindex!(sd::MVTSeries, val, i1::_FallbackType...) = setindex!(_vals(sd), val, i1...)

# -------------------------------------------------------------
# Some other constructors
# -------------------------------------------------------------


# Empty from a list of variables and of specified type (first date must also be given, Frequency is not enough)
# @inline MVTSeries(fd::MIT, vars) = MVTSeries(Float64, fd, vars)
MVTSeries(T::Type{<:Number}, fd::MIT, vars) = MVTSeries(fd, vars, Matrix{T}(undef, 0, length(vars)))

# Uninitialized from a range and list of variables
@inline MVTSeries(rng::UnitRange{<:MIT}, vars) = MVTSeries(Float64, rng, vars, undef)
@inline MVTSeries(rng::UnitRange{<:MIT}, vars, ::UndefInitializer) = MVTSeries(Float64, rng, vars, undef)
@inline MVTSeries(T::Type{<:Number}, rng::UnitRange{<:MIT}, vars) = MVTSeries(T, rng, vars, undef)
MVTSeries(T::Type{<:Number}, rng::UnitRange{<:MIT}, vars, ::UndefInitializer) =
    MVTSeries(first(rng), vars, Matrix{T}(undef, length(rng), length(vars)))
MVTSeries(T::Type{<:Number}, rng::UnitRange{<:MIT}, vars::Symbol, ::UndefInitializer) =
    MVTSeries(first(rng), (vars,), Matrix{T}(undef, length(rng), 1))

# initialize with a function like zeros, ones, rand.
MVTSeries(rng::UnitRange{<:MIT}, vars, init::Function) = MVTSeries(first(rng), vars, init(length(rng), length(vars)))
# no type-explicit version because the type is determined by the output of init()

#initialize with a constant
MVTSeries(rng::UnitRange{<:MIT}, vars, v::Number) = MVTSeries(first(rng), vars, fill(v, length(rng), length(vars)))

# construct with a given range (rather than only the first date). We must check the range length matches the data size 1
function MVTSeries(rng::UnitRange{<:MIT}, vars, vals::AbstractMatrix{<:Number})
    lrng = length(rng)
    lvrs = length(vars)
    nrow, ncol = size(vals)
    if lrng != nrow || lvrs != ncol
        throw(ArgumentError("Number of periods and variables do not match size of data." *
                            " ($(lrng)×$(lvrs)) ≠ ($(nrow)×$(ncol))"
        ))
    end
    return MVTSeries(first(rng), vars, vals)
end

# construct if data is given as a vector (it must be exactly 1 variable)
MVTSeries(fd::MIT, vars, data::AbstractVector) = MVTSeries(fd, vars, reshape(data, :, 1))
MVTSeries(fd::MIT, vars::Union{Symbol,AbstractString}, data::AbstractVector) = MVTSeries(fd, (vars,), reshape(data, :, 1))
MVTSeries(rng::UnitRange{<:MIT}, vars, data::AbstractVector) = MVTSeries(rng, vars, reshape(data, :, 1))
MVTSeries(rng::UnitRange{<:MIT}, vars::Union{Symbol,AbstractString}, data::AbstractVector) = MVTSeries(rng, (vars,), reshape(data, :, 1))

# construct uninitialized by way of calling similar 
Base.similar(::Type{<:AbstractArray}, T::Type{<:Number}, shape::Tuple{UnitRange{<:MIT},NTuple{N,Symbol}}) where {N} = MVTSeries(T, shape[1], shape[2])
Base.similar(::Type{<:AbstractArray{T}}, shape::Tuple{UnitRange{<:MIT},NTuple{N,Symbol}}) where {T<:Number,N} = MVTSeries(T, shape[1], shape[2])
Base.similar(::AbstractArray, T::Type{<:Number}, shape::Tuple{UnitRange{<:MIT},NTuple{N,Symbol}}) where {N} = MVTSeries(T, shape[1], shape[2])
Base.similar(::AbstractArray{T}, shape::Tuple{UnitRange{<:MIT},NTuple{N,Symbol}}) where {T<:Number,N} = MVTSeries(T, shape[1], shape[2])

# construct from range and fill with the given constant or array
Base.fill(v::Number, rng::UnitRange{<:MIT}, vars::NTuple{N,Symbol}) where {N} = MVTSeries(first(rng), vars, fill(v, length(rng), length(vars)))

# Empty (0 variables) from range
@inline function MVTSeries(rng::UnitRange{<:MIT}; args...)
    isempty(args) && return MVTSeries(rng, ())
    keys, values = zip(args...)
    # figure out the element type
    ET = mapreduce(eltype, Base.promote_eltype, values)
    MVTSeries(ET, rng; args...)
end

function MVTSeries(; args...)
    isempty(args) && return MVTSeries(1U)
    keys, values = zip(args...)
    # range is the union of all ranges
    rng = mapreduce(rangeof, union, filter(v -> applicable(rangeof, v), values))
    return MVTSeries(rng; args...)
end

# construct from a collection of TSeries
function MVTSeries(ET::Type{<:Number}, rng::UnitRange{<:MIT}; args...)
    isempty(args) && return MVTSeries(1U)
    # allocate memory
    ret = MVTSeries(rng, keys(args), typenan(ET))
    # copy data
    for (key, value) in args
        ret[:, key] .= value
    end
    return ret
end

# -------------------------------------------------------------------------------
# Dot access to columns

Base.propertynames(x::MVTSeries) = tuple(colnames(x)...)

function Base.getproperty(x::MVTSeries, col::Symbol)
    col ∈ fieldnames(typeof(x)) && return getfield(x, col)
    return _col(x, col)
end

function Base.setproperty!(x::MVTSeries, name::Symbol, val)
    name ∈ fieldnames(typeof(x)) && return setfield!(x, name, val)
    col = try
        _col(x, name)
    catch e
        if e isa BoundsError
            error("Cannot append new column this way.\n" *
                  "\tUse hcat(x; $name = value) or push!(x; $name = value).")
        else
            rethrow(e)
        end
    end
    ####  Do we need this mightalias check here? I think it's done in copyto!() so we should be safe without it.
    # if Base.mightalias(col, val)
    #     val = copy(val)
    # end
    if val isa TSeries
        rng = intersect(rangeof(col), rangeof(val))
        return copyto!(col, rng, val)
    elseif val isa Number
        return fill!(col.values, val)
    else
        return copyto!(col.values, val)
    end
end

# -------------------------------------------------------------------------------
# Indexing other than integers 

# some check bounds that plug MVTSeries into the Julia infrastructure for AbstractArrays
@inline Base.checkbounds(::Type{Bool}, x::MVTSeries, p::MIT) = checkindex(Bool, rangeof(x), p)
@inline Base.checkbounds(::Type{Bool}, x::MVTSeries, p::UnitRange{<:MIT}) = checkindex(Bool, rangeof(x), p)
@inline Base.checkbounds(::Type{Bool}, x::MVTSeries, c::Symbol) = haskey(_cols(x), c)
@inline function Base.checkbounds(::Type{Bool}, x::MVTSeries, INDS::Union{Vector{Symbol},NTuple{N,Symbol}}) where {N}
    cols = _cols(x)
    for c in INDS
        haskey(cols, c) || return false
    end
    return true
end

@inline function Base.checkbounds(::Type{Bool}, x::MVTSeries, p::Union{MIT,UnitRange{<:MIT}}, c::Union{Symbol,Vector{Symbol},NTuple{N,Symbol}}) where {N}
    return checkbounds(Bool, x, p) && checkbounds(Bool, x, c)
end


# ---- single argument access

# single argument - MIT point - return the row as a vector (slice of .values)
Base.getindex(x::MVTSeries, p::MIT) = mixed_freq_error(x, p)
@inline function Base.getindex(x::MVTSeries{F}, p::MIT{F}) where {F<:Frequency}
    @boundscheck checkbounds(x, p)
    fi = firstindex(_vals(x), 1)
    getindex(_vals(x), fi + oftype(fi, p - firstdate(x)), :)
end

Base.setindex!(x::MVTSeries, val, p::MIT) = mixed_freq_error(x, p)
@inline function Base.setindex!(x::MVTSeries{F}, val, p::MIT{F}) where {F<:Frequency}
    @boundscheck checkbounds(x, p)
    fi = firstindex(_vals(x), 1)
    setindex!(_vals(x), val, fi + oftype(fi, p - firstdate(x)), :)
end

# single argument - MIT range
Base.getindex(x::MVTSeries, rng::UnitRange{MIT}) = mixed_freq_error(x, rng)
@inline function Base.getindex(x::MVTSeries{F}, rng::UnitRange{MIT{F}}) where {F<:Frequency}
    start, stop = _ind_range_check(x, rng)
    return MVTSeries(first(rng), axes(x, 2), getindex(_vals(x), start:stop, :))
end

Base.setindex!(x::MVTSeries, val, rng::UnitRange{MIT}) = mixed_freq_error(x, rng)
@inline function Base.setindex!(x::MVTSeries{F}, val, rng::UnitRange{MIT{F}}) where {F<:Frequency}
    start, stop = _ind_range_check(x, rng)
    setindex!(_vals(x), val, start:stop, :)
end

# single argument - variable - return a TSeries of the column
@inline Base.getindex(x::MVTSeries, col::AbstractString) = _col(x, Symbol(col))
@inline Base.getindex(x::MVTSeries, col::Symbol) = _col(x, col)

@inline Base.setindex!(x::MVTSeries, val, col::AbstractString) = setindex!(x, val, Symbol(col))
@inline function Base.setindex!(x::MVTSeries, val, col::Symbol)
    setproperty!(x, col, val)
end

# single argument - list/tuple of variables - return a TSeries of the column
@inline function Base.getindex(x::MVTSeries, cols::Union{Vector{Symbol},NTuple{N,Symbol}}) where {N}
    inds = [_colind(x, c) for c in cols]
    return MVTSeries(firstdate(x), cols, getindex(_vals(x), :, inds))
end

@inline function Base.setindex!(x::MVTSeries, val, cols::Union{Vector{Symbol},NTuple{N,Symbol}}) where {N}
    inds = [_colind(x, c) for c in cols]
    setindex!(x.values, val, :, inds)
end

# ---- two arguments indexing

const _SymbolOneOrCollection = Union{Symbol,Vector{Symbol},NTuple{N,Symbol}} where {N}
const _MITOneOrRange = Union{MIT,UnitRange{<:MIT}}

@inline Base.getindex(x::MVTSeries, p::_MITOneOrRange, c::_SymbolOneOrCollection) = mixed_freq_error(x, p)
@inline Base.setindex!(x::MVTSeries, val, p::_MITOneOrRange, c::_SymbolOneOrCollection) = mixed_freq_error(x, p)

# if one argument is Colon, fall back on single argument indexing
@inline Base.getindex(x::MVTSeries, p::_MITOneOrRange, ::Colon) = getindex(x, p)
@inline Base.getindex(x::MVTSeries, ::Colon, c::_SymbolOneOrCollection) = getindex(x, c)

@inline Base.setindex!(x::MVTSeries, val, p::_MITOneOrRange, ::Colon) = setindex!(x, val, p, axes(x, 2))
@inline Base.setindex!(x::MVTSeries, val, ::Colon, c::_SymbolOneOrCollection) = setindex!(x, val, axes(x, 1), c)

# 

# the index is stored as the second index in the view() object which is the
# values of the TSeries of the column. See the inner constructor of MVTSeries.
_colind(x, c::Symbol) = _col(x, c).values.indices[2]
_colind(x, cols::Union{Tuple,AbstractVector}) = Int[_colind(x, Symbol(c)) for c in cols]

# with a single MIT and single Symbol we return a number
# with a single MIT and multiple Symbol-s we return a Vector
# the appropriate dispatch is done in getindex on the values, so we wrap both cases in a single function
@inline function Base.getindex(x::MVTSeries{F}, p::MIT{F}, c::_SymbolOneOrCollection) where {F<:Frequency}
    # @boundscheck checkbounds(x, c)
    @boundscheck checkbounds(x, p)
    fi = firstindex(_vals(x), 1)
    i1 = oftype(fi, fi + (p - firstdate(x)))
    i2 = _colind(x, c)
    getindex(x.values, i1, i2)
end

# with an MIT range and a Symbol (single column) we return a TSeries
@inline function Base.getindex(x::MVTSeries{F}, p::UnitRange{MIT{F}}, c::Symbol) where {F<:Frequency}
    # @boundscheck checkbounds(x, c)
    @boundscheck checkbounds(x, p)
    start, stop = _ind_range_check(x, p)
    i1 = start:stop
    i2 = _colind(x, c)
    return TSeries(first(p), getindex(_vals(x), i1, i2))
end

# with an MIT range and a sequence of Symbol-s we return an MVTSeries
@inline function Base.getindex(x::MVTSeries{F}, p::UnitRange{MIT{F}}, c::Union{NTuple{N,Symbol},Vector{Symbol}}) where {F<:Frequency,N}
    # @boundscheck checkbounds(x, c)
    @boundscheck checkbounds(x, p)
    start, stop = _ind_range_check(x, p)
    i1 = start:stop
    i2 = _colind(x, c)
    return MVTSeries(first(p), axes(x, 2)[i2], getindex(_vals(x), i1, i2))
end

# assignments

# with a single MIT we assign a number or a row-Vector
@inline function Base.setindex!(x::MVTSeries{F}, val, p::MIT{F}, c::_SymbolOneOrCollection) where {F<:Frequency}
    # @boundscheck checkbounds(x, c)
    @boundscheck checkbounds(x, p)
    fi = firstindex(_vals(x), 1)
    i1 = oftype(fi, fi + (p - firstdate(x)))
    i2 = _colind(x, c)
    setindex!(x.values, val, i1, i2)
end

# with a range of MIT and a single column - we fall back on TSeries assignment
@inline function Base.setindex!(x::MVTSeries{F}, val, r::UnitRange{MIT{F}}, c::Symbol) where {F<:Frequency}
    setindex!(_col(x, c), val, r)
end

@inline function Base.setindex!(x::MVTSeries{F}, val, r::UnitRange{MIT{F}}, c::Union{Vector{Symbol},NTuple{N,Symbol}}) where {F<:Frequency,N}
    # @boundscheck checkbounds(x, c)
    @boundscheck checkbounds(x, r)
    start, stop = _ind_range_check(x, r)
    i1 = start:stop
    i2 = _colind(x, c)
    setindex!(_vals(x), val, i1, i2)
end

@inline Base.setindex!(x::MVTSeries, val, ind::Tuple{<:MIT,Symbol}) = setindex!(x, val, ind...)

@inline function Base.setindex!(x::MVTSeries{F}, val::MVTSeries{F}, r::UnitRange{MIT{F}}, c::Union{Vector{Symbol},NTuple{N,Symbol}}) where {F<:Frequency,N}
    @boundscheck checkbounds(x, r)
    # @boundscheck checkbounds(x, c)
    @boundscheck checkbounds(val, r)
    # @boundscheck checkbounds(val, c)
    start, stop = _ind_range_check(x, r)
    xi1 = start:stop
    xi2 = _colind(x, c)
    start, stop = _ind_range_check(val, r)
    vali1 = start:stop
    vali2 = _colind(val, c)
    _vals(x)[xi1, xi2] = _vals(val)[vali1, vali2]
end

# -------------------------------------------------------------------------------

Base.copyto!(dest::MVTSeries, src::AbstractArray) = (copyto!(dest.values, src); dest)
Base.copyto!(dest::MVTSeries, src::MVTSeries) = (copyto!(dest.values, src.values); dest)

# -------------------------------------------------------------------------------
# ways add new columns (variables)

function Base.hcat(x::MVTSeries; KW...)
    T = reduce(Base.promote_eltype, (x, values(KW)...))
    y = MVTSeries(rangeof(x), tuple(colnames(x)..., keys(KW)...), typenan(T))
    # copyto!(y, x)
    for (k, v) in pairs(x)
        setproperty!(y, k, v)
    end
    for (k, v) in KW
        setproperty!(y, k, v)
    end
    return y
end

function Base.vcat(x::MVTSeries, args::AbstractVecOrMat...)
    return MVTSeries(firstdate(x), colnames(x), vcat(_vals(x), args...))
end

####   Views

Base.fill!(x::MVTSeries, val) = fill!(_vals(x), val)

@inline Base.view(x::MVTSeries, I...) = view(_vals(x), I...)

@inline Base.view(x::MVTSeries, ::Colon, J::_SymbolOneOrCollection) = view(x, axes(x, 1), J)
@inline Base.view(x::MVTSeries, I::_MITOneOrRange, ::Colon) = view(x, I, axes(x, 2))
@inline Base.view(x::MVTSeries, ::Colon, ::Colon) = view(x, axes(x, 1), axes(x, 2))
function Base.view(x::MVTSeries, I::_MITOneOrRange, J::_SymbolOneOrCollection) where {F<:Frequency}
    @boundscheck checkbounds(x, I)
    @boundscheck checkbounds(x, J)
    start, stop = _ind_range_check(x, I)
    i1 = start:stop
    i2 = _colind(x, J)
    return MVTSeries(first(I), axes(x, 2)[i2], view(_vals(x), i1, i2))
end


####

include("mvtseries/mvts_broadcast.jl")
include("mvtseries/mvts_show.jl")

####  arraymath

@inline Base.promote_shape(x::MVTSeries, y::MVTSeries) =
    axes(x, 2) == axes(y, 2) ? (intersect(rangeof(x), rangeof(y)), axes(x, 2)) :
    throw(DimensionMismatch("Columns do not match:\n\t$(axes(x,2))\n\t$(axes(y,2))"))

@inline Base.promote_shape(x::MVTSeries, y::AbstractArray) =
    promote_shape(_vals(x), y)

@inline Base.promote_shape(x::AbstractArray, y::MVTSeries) =
    promote_shape(x, _vals(y))

@inline Base.LinearIndices(x::MVTSeries) = LinearIndices(_vals(x))

Base.:*(x::Number, y::MVTSeries) = copyto!(similar(y), *(x, y.values))
Base.:*(x::MVTSeries, y::Number) = copyto!(similar(x), *(x.values, y))
Base.:\(x::Number, y::MVTSeries) = copyto!(similar(y), \(x, y.values))
Base.:/(x::MVTSeries, y::Number) = copyto!(similar(x), /(x.values, y))

for func = (:+, :-)
    @eval function Base.$func(x::MVTSeries, y::MVTSeries)
        T = Base.promote_eltype(x, y)
        if axes(x) == axes(y)
            return copyto!(similar(x, T), $func(_vals(x), _vals(y)))
        else
            shape = promote_shape(x, y)
            return copyto!(similar(Matrix, T, shape), $func(_vals(x[shape[1]]), _vals(y[shape[1]])))
        end
    end
end

####  sum(x::MVTSeries; dims=2) -> TSeries

for func in (:sum, :prod, :minimum, :maximum)
    @eval @inline Base.$func(x::MVTSeries; dims) =
        dims == 2 ? TSeries(firstdate(x), $func(rawdata(x); dims = dims)[:]) : $func(rawdata(x); dims = dims)

    @eval @inline Base.$func(f, x::MVTSeries; dims) =
        dims == 2 ? TSeries(firstdate(x), $func(f, rawdata(x); dims = dims)[:]) : $func(f, rawdata(x); dims = dims)

end

####  reshape

# reshaped arrays are slow with MVTSeries. We must avoid them at all costs
@inline function Base.reshape(x::MVTSeries, args::Int...)
    ret = reshape(_vals(x), args...)
    if axes(ret) == axes(_vals(x))
        return x
    else
        @error("Cannot reshape MVTSeries!")
        return ret
    end
end

####  diff and cumsum

@inline shift(x::MVTSeries, k::Integer) = shift!(copy(x), k)
@inline shift!(x::MVTSeries, k::Integer) = (x.firstdate -= k; x)
@inline lag(x::MVTSeries, k::Integer = 1) = shift(x, -k)
@inline lag!(x::MVTSeries, k::Integer = 1) = shift!(x, -k)
@inline lead(x::MVTSeries, k::Integer = 1) = shift(x, k)
@inline lead!(x::MVTSeries, k::Integer = 1) = shift!(x, k)

@inline Base.diff(x::MVTSeries; dims = 1) = diff(x, -1; dims)
@inline Base.diff(x::MVTSeries, k::Integer; dims = 1) =
    dims == 1 ? x - shift(x, k) : diff(_vals(x); dims)

@inline Base.cumsum(x::MVTSeries; dims) = cumsum!(copy(x), _vals(x); dims)
@inline Base.cumsum!(out::MVTSeries, in::AbstractMatrix; dims) = (cumsum!(_vals(out), in; dims); out)

####  moving average


"""
    moving(x, n)

Compute the moving average of `x` over a window of `n` periods. If `n > 0` the
window is backward-looking `(-n+1:0)` and if `n < 0` the window is forward-looking
`(0:-n-1)`.
"""
function moving end
export moving

@inline _moving_mean!(x_ma::TSeries, x, t, window) = x_ma[t] = mean(x[t.+window])
@inline _moving_mean!(x_ma::MVTSeries, x, t, window) = x_ma[t, :] .= mean(x[t.+window, :]; dims = 1)

@inline _moving_shape(x::TSeries, n) = (rangeof(x, drop = n - copysign(1, n)),)
@inline _moving_shape(x::MVTSeries, n) = (rangeof(x, drop = n - copysign(1, n)), axes(x, 2))

function moving(x::Union{TSeries,MVTSeries}, n::Integer)
    window = n > 0 ? (-n+1:0) : (0:-n-1)
    x_ma = similar(x, _moving_shape(x, n))
    for t in rangeof(x_ma)
        _moving_mean!(x_ma, x, t, window)
    end
    return x_ma
end

####  undiff

"""
    undiff(dvar, [date => value])
    undiff!(var, dvar; fromdate=firstdate(dvar)-1)

Inverse of `diff`, i.e. `var` remains unchanged under `undiff!(var, diff(var))`
or `undiff(diff(var), firstdate(var)=>first(var))`. This is the same as
`cumsum`, but specific to time series.

In the case of `undiff` the second argument is an "anchor" `Pair` specifying a
known value at some time period. Typically this will be the period just before
the first date of `dvar`, but doesn't have to be. If the date falls outside the
`rangeof(dvar)` we extend dvar with zeros as necessary. If missing, this
argument defaults to `firstdate(dvar)-1 => 0`.

In the case of `undiff!`, the `var` argument provides the "anchor" value and the
storage location for the result. The `fromdate` parameter specifies the date of
the "anchor" and the anchor value is taken from `var`. See important note below.

The in-place version (`undiff!`) works only with `TSeries`. The other version
(`undiff`) works with `MVTSeries` as well as `TSeries`. In the case of
`MVTSeries` the anchor `value` must be a `Vector`, or a `Martix` with 1 row, of
the same length as the number of columns of `dvar`.

!!! note 

    In the case of `undiff!` the meaning of parameter `fromdate` is different
    from the meaning of `date` in the second argument of `undiff`. This only
    matters if `fromdate` falls somewhere in the middle of the range of `dvar`.

    In the case of `undiff!`, all values of `dvar` at, and prior to, `fromdate`
    are ignored (considered zero). Effectively, values of `var` up to, and
    including, `fromdate` remain unchanged. 

    By contrast, in `undiff` with `date => value` somewhere in the middle of the
    range of `dvar`, the operation is applied over the full range of `dvar`,
    both before and after `date`, and then the result is adjusted by adding or
    subtracting a constant such that in the end we have `result[date]=value`.

"""
function undiff end, function undiff! end
export undiff, undiff!

@inline undiff(dvar::TSeries) = undiff(dvar, firstdate(dvar) - 1 => zero(eltype(dvar)))
function undiff(dvar::TSeries, anchor::Pair{<:MIT,<:Number})
    fromdate, value = anchor
    ET = Base.promote_eltype(dvar, value)
    if fromdate ∉ rangeof(dvar)
        # our anchor is outside, extend with zeros
        dvar = overlay(dvar, fill(zero(ET), fromdate:lastdate(dvar)))
    end
    result = similar(dvar, ET)
    result .= cumsum(dvar)
    correction = value - result[fromdate]
    result .+= correction
    return result
end

function undiff!(var::TSeries, dvar::TSeries; fromdate = firstdate(dvar) - 1)
    if fromdate < firstdate(var)
        error("Range mismatch: `fromdate == $(fromdate) < $(firstdate(var)) == firstdate(var): ")
    end
    if lastdate(var) < lastdate(dvar)
        resize!(var, firstdate(var):lastdate(dvar))
    end
    for t = fromdate+1:lastdate(dvar) 
        var[t] = var[t-1] + dvar[t]
    end
    return var
end

# undiff(dvar::MVTSeries) = undiff(dvar, firstdate(dvar) - 1 => zeros(eltype(dvar), size(dvar, 2)))
undiff(dvar::MVTSeries, anchor_value::Number = 0) = undiff(dvar, firstdate(dvar) - 1 => fill(anchor_value, size(dvar, 2)))
function undiff(dvar::MVTSeries, anchor::Pair{<:MIT,<:AbstractVecOrMat})
    fromdate, value = anchor
    ET = Base.promote_eltype(dvar, value)
    if fromdate ∉ rangeof(dvar)
        # our anchor is outside, extend with zeros
        shape = axes(dvar)
        new_range = union(fromdate:fromdate, shape[1])
        tmp = dvar
        dvar = fill(zero(ET), new_range, shape[2])
        dvar .= tmp
    end
    result = similar(dvar, ET)
    result .= cumsum(dvar; dims = 1)
    correction = reshape(value .- result[fromdate], 1, :)
    result .+= correction
    return result
end
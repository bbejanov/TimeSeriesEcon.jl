# Copyright (c) 2020-2021, Bank of Canada
# All rights reserved.

# -------------------------------------------------------------------------------
# TSeries struct 
# -------------------------------------------------------------------------------

"""
    mutable struct TSeries{F, T, C} <: AbstractVector{T}
        firstdate::MIT{F}
        values::C
    end

Time series with frequency `F` with values of type `T` stored in a container of
type `C`. By default the type is `Float64` and the container is
`Vector{Float64}`.

Construction:
    ts = TSeries(args...)

    The standard construction is `TSeries(firstdate::MIT, values::AbstractVector)`

    If the first argument is an MIT-range (instead or an MIT), then the length
    of the `values` container must match the length of the given range.

    In the case of a range argument, the `values` can be omitted, in which case
    the container is initializes with `undef`. Or you can also pass a constant
    and then the `values` will be filled with that constant. To accomplish this,
    you can also use `fill`, e.g., `TSeries(20Q1:20Q4, 5)` is the same as
    `fill(5, 20Q1:20Q4)`.

    If only a `firstdate::MIT` is given, the `values` container is initialized
    to an empty `Vector`.

    If only an `n::Integer` is given, it is the same as passing the range
    `0U .+ (1:n)`. An initialization argument is not allowed in this case.

    A `TSeries` can also be constructed with `copy`, `similar`, and `fill`.

Indexing:

    Indexing with an `MIT` or a range of `MIT` works as you'd expect.

    Indexing with `Integer`s works the same as with `Vector`.

    Indexing with `Bool`-array works as you'd expect. For example,
    `s[s .< 0.0] .*= -1` multiplies in place the negative entries of `s` by -1,
    so effectively it's the same as `s .= abs.(s)`.

    There are important differences between indexing with MIT and not
    using MIT (i.e., using Integer or Bool-array).

    * with MIT-range we return a TSeries with the given range, otherwise we
      return a `Vector`

    * the range can be extended (the TSeries resized appropriately) by assigning
      outside the current range. This works only with MIT (you get a BoundsError
      if you try to assign outside the Integer range).

    * `begin` and `end` are MIT, so either use both or none of them. For example
      `s[2:end]` doesn't work because 2 is an `Int` and `end` is an `MIT`. You
      should use `s[begin+1:end]`.

"""
mutable struct TSeries{F<:Frequency,T<:Number,C<:AbstractVector{T}} <: AbstractVector{T}
    firstdate::MIT{F}
    values::C
end

Base.values(t::TSeries) = values(t.values)
@inline firstdate(t::TSeries) = t.firstdate
@inline lastdate(t::TSeries) = t.firstdate + length(t.values) - one(t.firstdate)

@inline frequencyof(::Type{<:TSeries{F}}) where {F<:Frequency} = F

"""
    rangeof(s)

Return the stored range of the given time series object.
"""
@inline rangeof(t::TSeries) = firstdate(t):lastdate(t)

"""
    firstdate(ts), lastdate(ts)

Return the first and last date of the allocated data for the given `TSeries`.
These are identical to `firstindex` and `lastindex`.
"""
firstdate, lastdate

# -------------------------------------------------------------------------------
# some methods that make the AbstractArray infrastructure of Julia work with TSeries

@inline Base.size(t::TSeries) = size(t.values)
@inline Base.axes(t::TSeries) = (firstdate(t):lastdate(t),)
@inline Base.axes1(t::TSeries) = firstdate(t):lastdate(t)

# the following are needed for copy() and copyto!() (and a bunch of Julia internals that use them)
Base.IndexStyle(::TSeries) = IndexLinear()
Base.dataids(t::TSeries) = Base.dataids(getfield(t, :values))

# normally only the first of the following is sufficient.
# we add few other versions of similar below
Base.similar(t::TSeries) = TSeries(t.firstdate, similar(t.values))

# -------------------------------------------------------------------------------
# Indexing with integers and booleans - same as vectors

# indexing with integers is plain and simple
Base.getindex(t::TSeries, i::Int) = getindex(t.values, i)
Base.setindex!(t::TSeries, v::Number, i::Int) = (setindex!(t.values, v, i); t)

# indexing with integer arrays, ranges of integers, and Bool arrays
Base.getindex(t::TSeries, i::AbstractRange{Int}) = getindex(t.values, i)
Base.getindex(t::TSeries, i::AbstractArray{Int}) = getindex(t.values, values(i))
Base.getindex(t::TSeries, i::AbstractArray{Bool}) = getindex(t.values, values(i))
Base.setindex!(t::TSeries, v, i::AbstractRange{Int}) = (setindex!(t.values, v, i); t)
Base.setindex!(t::TSeries, v, i::AbstractArray{Int}) = (setindex!(t.values, v, values(i)); t)
Base.setindex!(t::TSeries, v, i::AbstractArray{Bool}) = (setindex!(t.values, v, values(i)); t)


# -------------------------------------------------------------
# Some constructors
# -------------------------------------------------------------

# construct undefined from range
TSeries(T::Type{<:Number}, rng::UnitRange{<:MIT}) = TSeries(first(rng), Vector{T}(undef, length(rng)))
TSeries(rng::UnitRange{<:MIT}) = TSeries(Float64, rng)
TSeries(fd::MIT) = TSeries(fd .+ (0:-1))
TSeries(T::Type{<:Number}, fd::MIT) = TSeries(T, fd .+ (0:-1))
TSeries(n::Integer) = TSeries(1U:n*U)
TSeries(T::Type{<:Number}, n::Integer) = TSeries(T, 1U:n*U)
TSeries(rng::UnitRange{<:Integer}) = TSeries(0U .+ rng)
TSeries(T::Type{<:Number}, rng::UnitRange{<:Integer}) = TSeries(T, 0U .+ rng)
TSeries(rng::AbstractRange, ::UndefInitializer) = TSeries(Float64, rng)
TSeries(T::Type{<:Number}, rng::AbstractRange, ::UndefInitializer) = TSeries(T, rng)
TSeries(rng::UnitRange{<:MIT}, ini::Function) = TSeries(first(rng), ini(length(rng)))

Base.similar(::Type{<:AbstractArray}, T::Type{<:Number}, shape::Tuple{UnitRange{<:MIT}}) = TSeries(T, shape[1])
Base.similar(::Type{<:AbstractArray{T}}, shape::Tuple{UnitRange{<:MIT}}) where {T<:Number} = TSeries(T, shape[1])
Base.similar(::AbstractArray, T::Type{<:Number}, shape::Tuple{UnitRange{<:MIT}}) = TSeries(T, shape[1])
Base.similar(::AbstractArray{T}, shape::Tuple{UnitRange{<:MIT}}) where {T<:Number} = TSeries(T, shape[1])

# construct from range and fill with the given constant or array
Base.fill(v::Number, rng::UnitRange{<:MIT}) = TSeries(first(rng), fill(v, length(rng)))
TSeries(rng::UnitRange{<:MIT}, v::Number) = fill(v, rng)
TSeries(rng::UnitRange{<:MIT}, v::AbstractVector{<:Number}) =
    length(rng) == length(v) ? TSeries(first(rng), v) : throw(ArgumentError("Range and data lengths mismatch."))


# -------------------------------------------------------------
# Pretty printing
# -------------------------------------------------------------

function Base.summary(io::IO, t::TSeries)
    et = eltype(t) === Float64 ? "" : ",$(eltype(t))"
    ct = "" # ct = typeof(t.values) === Array{eltype(t),1} ? "" : ",$(typeof(t.values))"
    typestr = "TSeries{$(frequencyof(t))$(et)$(ct)}"
    if isempty(t)
        print(io, "Empty ", typestr, " starting ", t.firstdate)
    else
        print(IOContext(io, :compact => true), length(t.values), "-element ", typestr, " with range ", Base.axes1(t))
    end
end

Base.show(io::IO, ::MIME"text/plain", t::TSeries) = show(io, t)
function Base.show(io::IO, t::TSeries)
    summary(io, t)
    isempty(t) && return
    print(io, ":")
    limit = get(io, :limit, true)
    nval = length(t.values)
    from = t.firstdate
    nrow, ncol = displaysize(io)
    if limit && nval > nrow - 5
        top = div(nrow - 5, 2)
        bot = nval - nrow + 6 + top
        for i = 1:top
            print(io, "\n", lpad(from + (i - 1), 8), " : ", t.values[i])
        end
        print(io, "\n    ⋮")
        for i = bot:nval
            print(io, "\n", lpad(from + (i - 1), 8), " : ", t.values[i])
        end
    else
        for i = 1:nval
            print(io, "\n", lpad(from + (i - 1), 8), " : ", t.values[i])
        end
    end
end



# ------------------------------------------------------------------
# indexing with MIT
# ------------------------------------------------------------------

# this part is tricky! 
# - When querying an index that falls outside the allocated range we throw a
#   BoundsError
# - When setting a value at index outside the allocated range we resize the
#   allocation to include the given index (setting new locations to NaN)
#   

Base.getindex(t::TSeries, m::MIT) = mixed_freq_error(t, m)
@inline function Base.getindex(t::TSeries{F}, m::MIT{F}) where {F<:Frequency}
    @boundscheck checkbounds(t, m)
    fi = firstindex(t.values)
    getindex(t.values, fi + oftype(fi, m - firstdate(t)))
end

@inline _ind_range_check(x, rng::MIT) = _ind_range_check(x, rng:rng)
function _ind_range_check(x, rng::UnitRange{<:MIT})
    fi = firstindex(x.values, 1)
    fd = firstdate(x)
    stop = oftype(fi, fi + (last(rng)-fd))
    start = oftype(fi, fi + (first(rng)-fd))
    if start < fi || stop > lastindex(x.values, 1)
        Base.throw_boundserror(x, rng)
    end
    return (start, stop)
end

Base.getindex(t::TSeries, rng::AbstractRange{<:MIT}) = mixed_freq_error(t, rng)
function Base.getindex(t::TSeries{F}, rng::StepRange{MIT{F},Duration{F}}) where {F<:Frequency}
    start, stop = _ind_range_check(t, rng)
    step = oftype(stop-start, rng.step)
    return t.values[start:step:stop]
end
function Base.getindex(t::TSeries{F}, rng::UnitRange{MIT{F}}) where {F<:Frequency}
    start, stop = _ind_range_check(t, rng)
    return TSeries(first(rng), getindex(t.values, start:stop))
end

Base.setindex!(t::TSeries, ::Number, m::MIT) = mixed_freq_error(t, m)
function Base.setindex!(t::TSeries{F}, v::Number, m::MIT{F}) where {F<:Frequency}
    # @boundscheck checkbounds(t, m)
    if m ∉ rangeof(t)
        # !! resize!() doesn't work for TSeries out of the box. we implement it below. 
        resize!(t, union(m:m, rangeof(t)))
    end
    fi = firstindex(t.values)
    setindex!(t.values, v, fi + oftype(fi, m - firstdate(t)))
end

Base.setindex!(t::TSeries, ::AbstractVector{<:Number}, rng::AbstractRange{<:MIT}) = mixed_freq_error(t, rng)
function Base.setindex!(t::TSeries{F}, vec::AbstractVector{<:Number}, rng::AbstractRange{MIT{F}}) where {F<:Frequency}
    if !issubset(rng, rangeof(t))
        # !! resize!() doesn't work for TSeries out of the box. we implement it below. 
        resize!(t, union(rangeof(t), rng))
    end
    if rng isa AbstractUnitRange
        start, stop = _ind_range_check(t, rng)
        setindex!(t.values, vec, start:stop)
    elseif rng isa StepRange
        start, stop = _ind_range_check(t, rng)
        setindex!(t.values, vec, start:oftype(stop-start,rng.step):stop)
    else
        fd = firstdate(t)
        fi = firstindex(t.values, 1)
        inds = [oftype(fi, fi + (ind-fd)) for ind in rng]
        setindex!(t.values, vec, inds)
    end
end

Base.setindex!(t::TSeries{F1}, src::TSeries{F2}, rng::AbstractRange{MIT{F3}}) where {F1<:Frequency,F2<:Frequency,F3<:Frequency} = mixed_freq_error(t, src, rng)
@inline Base.setindex!(t::TSeries{F}, src::TSeries{F}, rng::AbstractRange{MIT{F}}) where {F<:Frequency} = copyto!(t, rng, src)

"""
    typenan(x), typenan(T)

Return a value that indicates Not-A-Number of the same type as the given `x` or
of the given type `T`.

For floating point types, this is the IEEE-defined NaN.
For integer types, we use typemax(). This is not ideal, but it'll do for now.
"""
function typenan end

typenan(x::T) where {T<:Real} = typenan(T)
typenan(T::Type{<:AbstractFloat}) = T(NaN)
typenan(T::Type{<:Integer}) = typemax(T)
typenan(T::Type{<:Union{MIT,Duration}}) = T(typemax(Int64))

istypenan(x) = false
istypenan(x::Integer) = x == typenan(x)
istypenan(x::AbstractFloat) = isnan(x)

# n::Integer - only the length changes. We keep the starting date 
function Base.resize!(t::TSeries, n::Integer)
    lt = length(t)  # the old length 
    if lt ≠ n
        resize!(t.values, Int64(n))
        # fill new locations with NaN
        t.values[lt+1:end] .= typenan(eltype(t))
    end
    return t
end

# if range is given
Base.resize!(t::TSeries, rng::UnitRange{<:MIT}) = mixed_freq_error(t, eltype(rng))
function Base.resize!(t::TSeries{F}, rng::UnitRange{MIT{F}}) where {F<:Frequency}
    orng = rangeof(t)  # old range
    if first(rng) == first(orng)
        # if the beginning doesn't change we fallback on resize!(t, n)
        return resize!(t, length(rng))
    end
    tvals = copy(t.values) # old values - keep them safe for now
    inds_to_copy = intersect(rng, orng)
    # nrng = min(first(rng), first(orng)):max(last(rng), last(orng))
    _do = convert(Int, first(inds_to_copy) - first(rng)) + 1
    _so = convert(Int, first(inds_to_copy) - first(orng)) + 1
    _n = length(inds_to_copy)
    resize!(t.values, length(rng))
    t.firstdate = first(rng)
    # t[begin:first(inds_to_copy) - 1] .= typenan(eltype(t))
    # t[last(inds_to_copy) + 1:end] .= typenan(eltype(t))
    fill!(t.values, typenan(eltype(t)))
    copyto!(t.values, _do, tvals, _so, _n)
    return t
end

#
Base.copyto!(dest::TSeries, src::TSeries) = mixed_freq_error(dest, src)
@inline Base.copyto!(dest::TSeries{F}, src::TSeries{F}) where {F<:Frequency} = copyto!(dest, rangeof(src), src)

#
Base.copyto!(dest::TSeries, drng::AbstractRange{<:MIT}, src::TSeries) = mixed_freq_error(dest, drng, src)
function Base.copyto!(dest::TSeries{F}, drng::AbstractRange{MIT{F}}, src::TSeries{F}) where {F<:Frequency}
    fullindex = union(rangeof(dest), drng)
    resize!(dest, fullindex)
    copyto!(dest.values, Int(first(drng) - firstindex(dest) + 1), src[drng].values, 1, length(drng))
    return dest
end

# nothing

# view with MIT indexing
Base.view(t::TSeries, I::AbstractRange{<:MIT}) = mixed_freq_error(t, I)
function Base.view(t::TSeries{F}, I::AbstractRange{MIT{F}}) where {F<:Frequency}
    fi = firstindex(t.values)
    TSeries(first(I), view(t.values, oftype(fi, first(I) - firstindex(t) + fi):oftype(fi, last(I) - firstindex(t) + fi)))
end

# view with Int indexing
function Base.view(t::TSeries, I::AbstractRange{<:Integer})
    fi = firstindex(t.values)
    TSeries(firstindex(t) + first(I) - one(first(I)), view(t.values, oftype(fi, first(I)):oftype(fi, last(I))))
end


@inline Base.diff(x::TSeries) = x - lag(x)

# """
#     pct(x::TSeries, shift_value::Int, islog::Bool)

# Calculate percentage growth in `x` given a `shift_value`.

# __Note:__ The implementation is similar to IRIS.

# Examples
# ```julia-repl
# julia> x = TSeries(yy(2000), Vector(1:4));

# julia> pct(x, -1)
# TSeries{Yearly} of length 3
# 2001Y: 100.0
# 2002Y: 50.0
# 2003Y: 33.33333333333333
# ```
# See also: [`apct`](@ref)
# """
function pct(ts::TSeries, shift_value::Int; islog::Bool = false)
    if islog
        a = exp.(ts);
        b = shift(exp.(ts), shift_value);
    else
        a = ts;
        b = shift(ts, shift_value);
    end

    result = @. ( (a - b)/b ) * 100

    TSeries(result.firstdate, result.values)
end
export pct

# """
#     apct(x::TSeries, islog::Bool)

# Calculate annualised percent rate of change in `x`.

# __Note:__ The implementation is similar to IRIS.

# Examples
# ```julia-repl
# julia> x = TSeries(qq(2018, 1), Vector(1:8));

# julia> apct(x)
# TSeries{Quarterly} of length 7
# 2018Q2: 1500.0
# 2018Q3: 406.25
# 2018Q4: 216.04938271604937
# 2019Q1: 144.140625
# 2019Q2: 107.35999999999999
# 2019Q3: 85.26234567901243
# 2019Q4: 70.59558517284461
# ```

# See also: [`pct`](@ref)
# """
# function apct(ts::TSeries, islog::Bool = false)
#     if islog
#         a = exp(ts);
#         b = shift(exp(ts), - 1);
#     else
#         a = ts;
#         b = shift(ts, -1);
#     end

#     values_change = a/b
#     firstdate = values_change.firstdate

#     values = (values_change.^ppy(ts) .- 1) * 100

#     TSeries( (a/b).firstdate, values)
# end


# function Base.cumsum(s::TSeries)
#     TSeries(s.firstdate, cumsum(s.values))
# end

# function Base.cumsum!(s::TSeries)
#     s.values = cumsum(s.values)
#     return s
# end


# """
#     leftcropnan!(x::TSeries)

# Remove `NaN` values from starting at the beginning of `x`, in-place.

# __Note__: an internal function.
# """
# function leftcropnan!(s::TSeries)
#     while isequal(s[firstdate(s)], NaN)
#         popfirst!(s.values)
#         s.firstdate = s.firstdate + 1
#     end
#     return s
# end

# """
# rightcropnan!(x::TSeries)

# Remove `NaN` values from the end of `x`

# __Note__: an internal function.
# """
# function rightcropnan!(s::TSeries)
#     while isequal(s[lastdate(s)], NaN)
#         pop!(s.values)
#     end
#     return s
# end


# """
#     nanrm!(s::TSeries, type::Symbol)

# Remove `NaN` values that are either at the beginning of the `s` and/or end of `x`.

# Examples
# ```
# julia> s = TSeries(yy(2018), [NaN, NaN, 1, 2, NaN]);

# julia> nanrm!(s);

# julia> s
# TSeries{Yearly} of length 2
# 2020Y: 1.0
# 2021Y: 2.0
# ```
# """
# function nanrm!(s::TSeries, type::Symbol=:both)
#     if type == :left
#         leftcropnan!(s)
#     elseif type == :right
#         rightcropnan!(s)
#     elseif type == :both
#         leftcropnan!(s)
#         rightcropnan!(s)
#     else
#         error("Please select between :left, :right, or :both.")
#     end
#     return s
# end


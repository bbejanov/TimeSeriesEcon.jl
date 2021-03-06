"""
    TimeSeriesEcon

This package is part of the StateSpaceEcon ecosystem.
TimeSeriesEcon.jl provides functionality to work with
low-Frequency discrete macroeconomic time-series data.

### Frequencies (abstract type):
 - Unit
 - Monthly
 - Quarterly
 - Yearly

### Types:

 - `MIT{Frequency}` (aka "Moment In Time")
     - a primitive type denoting monthly, quarterly, and yearly dates
 - `TSeries{Frequency}`
     - an `AbstractVector` that can be indexed using `MIT`

### Functions:

 - `MIT` Constructors/Functions
    - `mm(year::Int, period::Int)`: returns a monthly `MIT` type instance
    - `qq(year::Int, period::Int)`: returns a quarterly `MIT` type instance
    - `yy(year::Int)`: returns a yearly `MIT` type instance
    - `ii(x::Int)`: returns a unit `MIT` type instance
    - `year(x::MIT)`: returns a `Int64` year value associated with `x`
    - `period(x::MIT)`: returns a `Int64` period value associated with `x`
    - `frequencyof(x::MIT)`: returns `<: Frequency` assosicated wtih `x`


 - Functions operating on `TSeries`
    - `mitrange(x::TSeries)`: returns a `UnitRange{MIT{Frequency}}` for the given `x`
    - `firstdate(x::TSeries)`: returns `MIT{Frequency}` first date associated with `x`  
    - `lastdate(x::TSeries)`: returns `MIT{Frequency}` last date associated with `x`
    - `ppy(x::TSeries)`: returns the number of periods per year for `x::TSeries`. (`ppy` also accepts `x::MIT` and `x::Frequency`) 
    - `shift(x::TSeries, i::Int64)`: shifts the dates of `x` by `firstdate(x) - i`
    - `shift!`: in-place version of `shift`
    - `pct(x::TSeries, shift_value::Int64; islog::Bool = false)`: calculates percent rate of change of `x::TSeries`
    - `apct(x::TSeries, islog::Bool = false)`: calculates annualized percent rate of change of `x::TSeries`
    - `nanrm!(x::TSeries, type::Symbol=:both)`: removes `NaN` from `x::TSeries`
"""
module TimeSeriesEcon

include("momentintime.jl")
include("tseries.jl")
include("recursive.jl")
include("convert.jl")
include("plotrecipes.jl")

# Defined in src/momentintime.jl
export MIT
export mm, qq, yy, ii
export Monthly, Quarterly, Yearly, Frequency, Unit
export year, period

# Defined in src/TSeries.jl
export TSeries
export mitrange
export shift, shift!
export ppy
export pct, apct
export nanrm!
export firstdate, lastdate



end

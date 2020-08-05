
export SimData

"""
    SimData

Data structure containing the time series data for a simulation.

It is a collection of [`TSeries`](@ref) of the same frequency and containing
data for the same range. When used for simulation, the range must include the
initial conditions, the simulation range and the final conditions, although it
could extend beyond that. It must contain time series for all variables and
shocks in the model, although it might contain other time series.

"""
struct SimData{F <: Frequency,N <: NamedTuple,C <: AbstractMatrix{Float64}} <: AbstractMatrix{Float64}
    firstdate::MIT{F}
    columns::N
    values::C

    # inner constructor enforces constraints.
    function SimData(fd, names, values)
        if length(names) != size(values, 2)
            throw(ArgumentError("Number of names and columns don't match: $(length(names)) ≠ $(size(values, 2))."))
        end
        columns = NamedTuple{names}([TSeries(fd, view(values, :, i)) for i in 1:length(names) ])
        new{frequencyof(fd),typeof(columns),typeof(values)}(fd, columns, values)
    end
end

# External constructors
# Coming soon stay tuned

TimeSeriesEcon.firstdate(sd::SimData) = getfield(sd, :firstdate)
TimeSeriesEcon.lastdate(sd::SimData) = (firstdate(sd) - 1) + size(_values(sd), 1) 
TimeSeriesEcon.frequencyof(::SimData{F}) where F <: Frequency = F
TimeSeriesEcon.mitrange(sd::SimData) = (firstdate(sd) - 1) .+ Base.axes1(sd)

@inline _columns(sd::SimData) = getfield(sd, :columns)
@inline _names(sd::SimData) = keys(getfield(sd, :columns))
@inline _values(sd::SimData) = getfield(sd, :values)
@inline _values_view(sd::SimData, i1, i2) = view(getfield(sd, :values), i1, i2)
@inline _values_slice(sd::SimData, i1, i2) = getindex(getfield(sd, :values), i1, i2)

Base.size(sd::SimData) = size(_values(sd))
Base.IndexStyle(sd::SimData) = IndexStyle(_values(sd))
Base.getindex(sd::SimData, i1...) = getindex(_values(sd), i1...)
Base.setindex!(sd::SimData, val, i1...) = setindex!(_values(sd), val, i1...)

Base.similar(sd::SimData) = SimData(firstdate(sd), _names(sd), similar(_values(sd)))

Base.:(==)(a::SimData, b::SimData) = frequencyof(a) == frequencyof(b) && firstdate(a) == firstdate(b) && _values(a) == _values(b)

Base.dataids(sd::SimData) = Base.dataids(_values(sd))

# Define dot access to columns
Base.propertynames(sd::SimData) = _names(sd)
function Base.getproperty(sd::SimData, col::Symbol)
    if col in _names(sd)
        return getfield(_columns(sd), col)
    else
        throw(BoundsError(sd, [col,]))
    end
end

# Access to columns by [:xyz] notation
Base.getindex(sd::SimData, col::Symbol) = getproperty(sd, col)
Base.getindex(sd::SimData, col::AbstractString) = getproperty(sd, Symbol(col))

function Base.setproperty!(sd::SimData,  col::Symbol, val)
    try
        col = getproperty(sd, col)
    catch BoundsError
        error("Cannot assign new data column this way. Use hcat(sd, column=value, ...) instead")
    end
    if Base.mightalias(col, val)
        val = copy(val)
    end
    setindex!(col, val, :)
end

Base.getindex(sd::SimData, cols::AbstractArray{Symbol}) = getindex(sd, tuple(cols...))
function Base.getindex(sd::SimData, cols::NTuple{N,Symbol}) where N
    SimData(firstdate(sd), tuple(cols...), hcat((getproperty(sd, c) for c in cols)...))
end

function Base.hcat(sd::SimData; KW...)
    l1 = size(sd, 1)
    as_vect(v::Number) = fill(Float64(v), l1)
    as_vect(v) = v
    names = (_names(sd)..., keys(KW)...)
    vals = hcat(_values(sd), (as_vect(v) for v in values(KW))...)
    return SimData(firstdate(sd), names, vals)
end

# Indexing access with MIT

function check_frequency(a, b)
    Fa = frequencyof(a)
    Fb = frequencyof(b)
    Fa == Fb || throw(ArgumentError("wrong frequency: expected $Fa got $Fb."))
end

macro if_same_frequency(a, b, expr)
    :( frequencyof($a) == frequencyof($b) ? $(expr) : throw(ArgumentError("Wrong frequency")) ) |> esc
end

# A single MIT materializes as a NamedTuple (row of the matrix with column names attached to the values)
function Base.getindex(sd::SimData, i1::MIT) 
    check_frequency(sd, i1)
    if firstdate(sd) <= i1 <= lastdate(sd)
        return @inbounds NamedTuple{_names(sd)}(_values_view(sd, i1 - firstdate(sd) + 1, :))
    else
        throw(BoundsError(sd, i1))
    end
end

# Modifying a row in a table -> one must pass in a vector
function Base.setindex!(sd::SimData, val::AbstractVector{<:Real}, i1::MIT) 
    check_frequency(sd, i1)
    if firstdate(sd) <= i1 <= lastdate(sd)
        row = i1 - firstdate(sd) + 1
        setindex!(_values_view(sd, row, :), val, :)
        return _values(sd)[row,:]
    else
        throw(BoundsError(sd, i1))
    end
end

function Base.setindex!(sd::SimData, val::NamedTuple, i1::MIT)
    check_frequency(sd, i1)
    if firstdate(sd) <= i1 <= lastdate(sd)
        for (n, v) in pairs(val)
            setindex!(getproperty(sd, n), v, i1)
        end
        return sd[i1]
    else
        throw(BoundsError(sd, i1))
    end
    return sd[i1]
end

# A selection of several rows returns a slice from the original SimData
function Base.getindex(sd::SimData, i1::AbstractUnitRange{<:MIT})
    check_frequency(sd, i1)
    if firstdate(sd) <= minimum(i1) <= maximum(i1) <= lastdate(sd)
        return SimData(first(i1), _names(sd), _values_slice(sd, i1 .- firstdate(sd) .+ 1, :))
    else
        throw(BoundsError(sd, i1))
    end
end

function Base.setindex!(sd::SimData, val, i1::AbstractUnitRange{<:MIT})
    check_frequency(sd, i1)
    if firstdate(sd) <= minimum(i1) <= maximum(i1) <= lastdate(sd)
        rows = i1 .- firstdate(sd) .+ 1
        setindex!(_values_view(sd, rows, :), val, :, :)
        return sd[rows,:]
    else
        throw(BoundsError(sd, i1))
    end
end


Base.getindex(sd::SimData, r, c::Symbol) = getproperty(sd, c)[r]
Base.getindex(sd::SimData, r::MIT, c::NTuple{N,Symbol}) where N = (a = sd[r]; NamedTuple{c}([a[cc] for cc in c]))
Base.getindex(sd::SimData, r::MIT, c::AbstractVector{Symbol}) = (a = sd[r]; NamedTuple{tuple(c...)}([a[cc] for cc in c]))
Base.getindex(sd::SimData, r::AbstractUnitRange{<:MIT}, c::AbstractVector{Symbol}) = getindex(sd, r, tuple(c...))
function Base.getindex(sd::SimData, r::AbstractUnitRange{<:MIT}, c::NTuple{N,Symbol}) where N 
    check_frequency(sd, r)
    if firstdate(sd) <= first(r) <= last(r) <= lastdate(sd)
        col_inds = indexin(c, [_names(sd)...])
        for (cc, cn) in zip(c, col_inds)
            if cn === nothing
                throw(BoundsError(sd, [cc]))
            end
        end
        return SimData(first(r), c, _values_slice(sd, r .- firstdate(sd) .+ 1, col_inds))
    else
        throw(BoundsError(sd, r))
    end
end

Base.setindex!(sd::SimData, v, r, c::Symbol) = setindex!(getproperty(sd, c), v, r)
function Base.setindex!(sd::SimData, vals, r::MIT, c::NTuple{N,Symbol}) where N 
    for (cc, vv) in zip(c, vals)
        setindex!(sd, vv, r, cc)
    end
    return sd[r, c]
end
Base.setindex!(sd::SimData, vals, r::MIT, c::AbstractVector{Symbol}) = setindex!(sd, vals, r, tuple(c...))
Base.setindex!(sd::SimData, vals, r::AbstractUnitRange{<:MIT}, c::AbstractVector{Symbol}) = setindex!(sd, vals, r, tuple(c...))
function Base.setindex!(sd::SimData, vals, r::AbstractUnitRange{<:MIT}, c::NTuple{N,Symbol}) where N
    check_frequency(sd, r)
    if firstdate(sd) <= first(r) <= last(r) <= lastdate(sd)
        cols = indexin(c, [_names(sd)...])
        for (cc, cn) in zip(c, cols)
            if cn === nothing
                throw(BoundsError(sd, [cc]))
            end
        end
        rows = r .- firstdate(sd) .+ 1
        setindex!(_values_view(sd, rows, cols), vals, :, :)
        return 
    else
        throw(BoundsError(sd, r))
    end
end

#### Pretty printing

sprint_names(names) = length(names) > 10 ? "$(length(names)) variables" : "variables (" * join(names, ",") * ")"
Base.summary(io::IO, sd::SimData) = isempty(sd) ?
        print(IOContext(io, :limit => true), "Empty SimData with ", sprint_names(_names(sd)), " in ", mitrange(sd)) :
        print(IOContext(io, :limit => true), size(sd, 1), '×', size(sd, 2), " SimData with ", sprint_names(_names(sd)), " in ", mitrange(sd))


Base.show(io::IO, ::MIME"text/plain", sd::SimData) = show(io, sd)
function Base.show(io::IO, sd::SimData)
    summary(io, sd)
    isempty(sd) && return
    print(io, ":")
    limit = get(io, :limit, true)
    nval, nsym = size(sd)

    from = firstdate(sd)
    dheight, dwidth = displaysize(io)
    io = IOContext(io, :compact => true)
    dwidth -= 11

    sd1 = [reshape([_names(sd)...], 1, :); _values(sd)]
    A = Base.alignment(io, sd1, axes(sd1, 1), 1:nsym, dwidth, dwidth, 2)

    all_cols = true
    if length(A) ≠ nsym
        dwidth = div(dwidth - 1, 2)
        AL = Base.alignment(io, sd1, axes(sd1, 1), 1:nsym, dwidth, dwidth, 2)
        AR = reverse(Base.alignment(io, sd1, axes(sd1, 1), reverse(1:nsym), dwidth, dwidth, 2))
        Linds = [1:length(AL)...]
        Rinds = [nsym - length(AR) + 1:nsym...]
        all_cols = false
    end

    local vdots = "\u22ee"
    local hdots = " \u2026 "
    local ddots = " \u22f1 "

    print_aligned_val(io, v, (al, ar), showsep=true; sep=showsep ? "  " : "") = begin
        sv = sprint(print, v, context=io, sizehint=0)
        if v isa Number
            vl, vr = Base.alignment(io, v)
        else
            vl, vr = 0, length(sv)
        end
        if length(sv) > al + ar
            sv = sv[1:al + ar]
        end
        print(io, repeat(" ", al - vl), sv, repeat(" ", ar - vr), sep)
    end

    print_colnames(io, Lcols, LAligns, Rcols=[], RAligns=[]) = begin
        local nLcols = length(Lcols)
        local nRcols = length(Rcols)
        for (i, (col, align)) in enumerate(zip(Lcols, LAligns))
            print_aligned_val(io, names[col], align, i < nLcols)
        end
        nRcols == 0 && return
        print(io, hdots)
        for (i, (col, align)) in enumerate(zip(Rcols, RAligns))
            print_aligned_val(io, names[col], align, i < nRcols)
        end
    end

    print_rows(io, rows, Lcols, LAligns, Rcols=[], RAligns=[]) = begin
        local nLcols = length(Lcols)
        local nRcols = length(Rcols)
        for row in rows
            mit = from + (row - 1)
            print(io, '\n', lpad(mit, 8), " : ")
            for (i, (val, align)) in enumerate(zip(vals[row, Lcols], LAligns))
                print_aligned_val(io, val, align, i < nLcols)
            end
            nRcols == 0 && continue
            print(io, hdots)
            for (i, (val, align)) in enumerate(zip(vals[row, Rcols], RAligns))
                print_aligned_val(io, val, align, i < nRcols)
            end
        end
    end

    print_vdots(io, Lcols, LAligns, Rcols=[], RAligns=[]) = begin
        print(io, '\n', repeat(" ", 11))
        local nLcols = length(Lcols)
        local nRcols = length(Rcols)
        for (i, (col, align)) in enumerate(zip(Lcols, LAligns))
            print_aligned_val(io, vdots, align, i < nLcols)
        end
        nRcols == 0 && return
        print(io, ddots)
        for (i, (col, align)) in enumerate(zip(Rcols, RAligns))
            print_aligned_val(io, vdots, align, i < nRcols)
        end
    end

    names = _names(sd)
    vals = _values(sd)
    if !limit
        print(io, "\n", repeat(" ", 11))
        print_colnames(io, 1:nsym, A)
        print_rows(io, 1:nval, 1:nsym, A)
    elseif nval > dheight - 6 # all rows don't fit
                # unable to show all rows
        if all_cols
            print(io, "\n", repeat(" ", 11))
            print_colnames(io, 1:nsym, A)
            top = div(dheight - 6, 2)
            print_rows(io, 1:top, 1:nsym, A)
            print_vdots(io, 1:nsym, A)
            bot = nval - dheight + 7 + top
            print_rows(io, bot:nval, 1:nsym, A)
        else # not all_cols
            print(io, "\n", repeat(" ", 11))
            print_colnames(io, Linds, AL, Rinds, AR)
            top = div(dheight - 6, 2)
            print_rows(io, 1:top, Linds, AL, Rinds, AR)
            print_vdots(io, Linds, AL, Rinds, AR)
            bot = nval - dheight + 7 + top
            print_rows(io, bot:nval, Linds, AL, Rinds, AR)
        end # all_cols
    else # all rows fit
        if all_cols
            print(io, '\n', repeat(" ", 11))
            print_colnames(io, 1:nsym, A)
            print_rows(io, 1:nval, 1:nsym, A)
        else
            print(io, '\n', repeat(" ", 11))
            print_colnames(io, Linds, AL, Rinds, AR)
            print_rows(io, 1:nval, Linds, AL, Rinds, AR)
        end
    end
end



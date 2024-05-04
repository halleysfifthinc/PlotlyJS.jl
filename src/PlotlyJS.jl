module PlotlyJS

using Reexport
@reexport using PlotlyBase
using PlotlyKaleido: PlotlyKaleido
using JSON
using WebIO, Observables
using WebIO: @register_renderable
using Base64, REPL, LazyArtifacts, DelimitedFiles, UUIDs  # stdlib

# need to import some functions because methods are meta-generated
import PlotlyBase:
    restyle!, relayout!, update!, addtraces!, deletetraces!, movetraces!,
    redraw!, extendtraces!, prependtraces!, purge!, to_image, download_image,
    restyle, relayout, update, addtraces, deletetraces, movetraces, redraw,
    extendtraces, prependtraces, prep_kwargs, sizes, _tovec,
    react, react!, add_trace!

using JSExpr
using JSExpr: @var, @new
if !isdefined(Base, :get_extension)
    using Requires
end

export plot, dataset, list_datasets, make_subplots, savefig, mgrid

# globals for this package
const _pkg_root = dirname(dirname(@__FILE__))
const _js_path = joinpath(artifact"plotly-artifacts", "plotly.min.js")
const _js_version = include(joinpath(_pkg_root, "deps", "plotly_cdn_version.jl"))
const _js_cdn_path = "https://cdn.plot.ly/plotly-$(_js_version).min.js"
const _mathjax_cdn_path =
    "https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.1/MathJax.js?config=TeX-AMS-MML_SVG"

struct PlotlyJSDisplay <: AbstractDisplay end

# include the rest of the core parts of the package
include("display.jl")
include("util.jl")
include("kaleido.jl")

make_subplots(;kwargs...) = plot(Layout(Subplots(;kwargs...)))

@doc (@doc Subplots) make_subplots

list_datasets() = readdir(joinpath(artifact"plotly-artifacts", "datasets"))
function check_dataset_exists(name::String)
    ds = list_datasets()
    name_ext = Dict(name => strip(ext, '.') for (name, ext) in splitext.(ds))
    if !haskey(name_ext, name)
        error("Unknown dataset $name, known datasets are $(collect(keys(name_ext)))")
    end
    ds_path = joinpath(artifact"plotly-artifacts", "datasets", "$(name).$(name_ext[name])")
    return ds_path
end

function dataset(name::String)::Dict{String,Any}
    ds_path = check_dataset_exists(name)
    if endswith(ds_path, "csv")
        # if csv, use DelimitedFiles and convert to dict
        data = DelimitedFiles.readdlm(ds_path, ',')
        return Dict(zip(data[1, :], data[2:end, i] for i in 1:size(data, 2)))
    elseif endswith(ds_path, "json")
        # use json
        return JSON.parsefile(ds_path)
    end
    error("should not ever get here!!! Please file an issue")
end


function __init__()
    _build_log = joinpath(_pkg_root, "deps", "build.log")
    if isfile(_build_log) && occursin("Warning:", read(_build_log, String))
        @warn("Warnings were generated during the last build of PlotlyJS:  please check the build log at $_build_log")
    end

    if ccall(:jl_generating_output, Cint, ()) != 1
        # ensure precompilation of packages depending on PlotlyJS finishes
        @async PlotlyKaleido.start()
    end

    # set up display
    insert!(Base.Multimedia.displays, findlast(x -> x isa Base.TextDisplay || x isa REPL.REPLDisplay, Base.Multimedia.displays) + 1, PlotlyJSDisplay())

    atreplinit(i -> begin
        while PlotlyJSDisplay() in Base.Multimedia.displays
            popdisplay(PlotlyJSDisplay())
        end
        insert!(Base.Multimedia.displays, findlast(x -> x isa REPL.REPLDisplay, Base.Multimedia.displays) + 1, PlotlyJSDisplay())
    end)

    @static if !isdefined(Base, :get_extension)
        @require JSON3 = "0f8b85d8-7281-11e9-16c2-39a750bddbf1" include("../ext/JSON3Ext.jl")
        @require IJulia = "7073ff75-c697-5162-941a-fcdaad2a7d2a" include("../ext/IJuliaExt.jl")

        @require CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b" begin
            include("../ext/CSVExt.jl")
            @require DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0" begin
                include("../ext/DataFramesExt.jl")
            end
        end
    end
end

# for methods that update the layout, first apply to the plot, then let plotly.js
# deal with the rest via the react function
for (k, v) in vcat(PlotlyBase._layout_obj_updaters, PlotlyBase._layout_vector_updaters)
    @eval function PlotlyBase.$(k)(p::SyncPlot, args...;kwargs...)
        $(k)(p.plot, args...; kwargs...)
        send_command(p.scope, :react, p.plot.data, p.plot.layout)
    end
end

for k in [:add_hrect!, :add_hline!, :add_vrect!, :add_vline!, :add_shape!, :add_layout_image!]
    @eval function PlotlyBase.$(k)(p::SyncPlot, args...;kwargs...)
        $(k)(p.plot, args...; kwargs...)
        send_command(p.scope, :react, p.plot.data, p.plot.layout)
    end
end

end # module

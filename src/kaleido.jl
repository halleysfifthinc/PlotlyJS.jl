using PlotlyKaleido: kill, is_running, start, restart, ALL_FORMATS, TEXT_FORMATS

# start() is a no-op if kaleido is already running
_ensure_kaleido_running(; kwargs...) = start(;plotly_version=_js_version, plotlyjs=_js_path, kwargs...)

savefig(p::SyncPlot; kwargs...) = savefig(p.plot; kwargs...)

function savefig(
        p::Plot;
        width::Union{Nothing,Int}=nothing,
        height::Union{Nothing,Int}=nothing,
        scale::Union{Nothing,Real}=nothing,
        format::String="png"
    )::Vector{UInt8}
    if !(format in ALL_FORMATS)
        error("Unknown format $format. Expected one of $ALL_FORMATS")
    end

    # construct payload
    _get(x, def) = x === nothing ? def : x
    payload = Dict(
        # set `width` and `height` to kwarg, layout value, layout template value, or
        # default, in order of priority
        :width => _get(                               width,
            haskey(p.layout, :width) ?                p.layout.width :
            (haskey(p.layout, :template) &&
                haskey(p.layout.template, :width)) ?  p.layout.template.width :
                                                      700),

        :height => _get(                              height,
            haskey(p.layout, :height) ?               p.layout.height :
            (haskey(p.layout, :template) &&
                haskey(p.layout.template, :height)) ? p.layout.template.height :
                                                      500),
        :scale => _get(scale, 1),
        :format => format,
        :data => p
    )

    _ensure_kaleido_running()
    P = PlotlyKaleido.P
    # convert payload to vector of bytes
    bytes = transcode(UInt8, JSON.json(payload))
    write(P.stdin, bytes)
    write(P.stdin, transcode(UInt8, "\n"))
    flush(P.stdin)

    # read stdout and parse to json
    res = readline(P.stdout)
    js = JSON.parse(res)

    # check error code
    code = get(js, "code", 0)
    if code != 0
        msg = get(js, "message", nothing)
        error("Transform failed with error code $code: $msg")
    end

    # get raw image
    img = String(js["result"])

    # base64 decode if needed, otherwise transcode to vector of byte
    if format in TEXT_FORMATS
        return transcode(UInt8, img)
    else
        return base64decode(img)
    end
end


@inline _get_Plot(p::Plot) = p
@inline _get_Plot(p::SyncPlot) = p.plot

"""
    savefig(
        io::IO,
        p::Plot;
        width::Union{Nothing,Int}=nothing,
        height::Union{Nothing,Int}=nothing,
        scale::Union{Nothing,Real}=nothing,
        format::String="png"
    )

Save a plot `p` to the io stream `io`. They keyword argument `format`
determines the type of data written to the figure and must be one of
$(join(ALL_FORMATS, ", ")), or html. `scale` sets the
image scale. `width` and `height` set the dimensions, in pixels. Defaults
are taken from `p.layout`, or supplied by plotly
"""
function savefig(io::IO,
        p::Union{SyncPlot,Plot};
        width::Union{Nothing,Int}=nothing,
        height::Union{Nothing,Int}=nothing,
        scale::Union{Nothing,Real}=nothing,
        format::String="png")
    if format == "html"
        return show(io, MIME("text/html"), _get_Plot(p), include_mathjax="cdn", include_plotlyjs="cdn", full_html=true)
    end

    bytes = savefig(p, width=width, height=height, scale=scale, format=format)
    write(io, bytes)
end


"""
    savefig(
        p::Plot, fn::AbstractString;
        format::Union{Nothing,String}=nothing,
        width::Union{Nothing,Int}=nothing,
        height::Union{Nothing,Int}=nothing,
        scale::Union{Nothing,Real}=nothing,
    )

Save a plot `p` to a file named `fn`. If `format` is given and is one of
$(join(ALL_FORMATS, ", ")), or html; it will be the format of the file. By
default the format is guessed from the extension of `fn`. `scale` sets the
image scale. `width` and `height` set the dimensions, in pixels. Defaults
are taken from `p.layout`, or supplied by plotly
"""
function savefig(
        p::Union{SyncPlot,Plot}, fn::AbstractString;
        format::Union{Nothing,String}=nothing,
        width::Union{Nothing,Int}=nothing,
        height::Union{Nothing,Int}=nothing,
        scale::Union{Nothing,Real}=nothing,
    )
    ext = split(fn, ".")[end]
    if format === nothing
        format = String(ext)
    end

    open(fn, "w") do f
        savefig(f, p; format=format, scale=scale, width=width, height=height)
    end
    return fn
end

const _KALEIDO_MIMES = Dict(
    "application/pdf" => "pdf",
    "image/png" => "png",
    "image/svg+xml" => "svg",
    "image/eps" => "eps",
    "image/jpeg" => "jpeg",
    "image/jpeg" => "jpeg",
    "application/json" => "json",
    "application/json; charset=UTF-8" => "json",
)

for (mime, fmt) in _KALEIDO_MIMES
    @eval function Base.show(
        io::IO, ::MIME{Symbol($mime)}, plt::Plot,
        width::Union{Nothing,Int}=nothing,
        height::Union{Nothing,Int}=nothing,
        scale::Union{Nothing,Real}=nothing,
    )
        savefig(io, plt, format=$fmt)
    end

    @eval function Base.show(
        io::IO, ::MIME{Symbol($mime)}, plt::SyncPlot,
        width::Union{Nothing,Int}=nothing,
        height::Union{Nothing,Int}=nothing,
        scale::Union{Nothing,Real}=nothing,
    )
        savefig(io, plt.plot, format=$fmt)
    end
end

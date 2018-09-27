# Packages below used to plot results
using DataFrames
using JLD2
using PGFPlotsX
using Statistics

# TODO:

############
# Settings #
############
RESULTPATH = joinpath(@__DIR__, "results")
PLOTPATH = joinpath(@__DIR__, "plots")

# LinearSolvers #
#################
USE_PARDISO     = false # Requires Paridso.jl with Paridso Project support
USE_CHOLMOD     = true

# Meshes #
##########
const MESHES = ["EIFFEL_TOWER_TET10_220271.inp",
                #"EIFFEL_TOWER_TET10_376120.inp",
                "EIFFEL_TOWER_TET10_921317.inp"
               ]
# Download the meshes
for mesh in MESHES
    meshfile = joinpath(@__DIR__, mesh)
    if !isfile(meshfile)
        url = "http://jukka.kapsi.fi/eiffel/$mesh"
        @info "Downloading $url"
        download(url, meshfile)
    end
end

# Parallelization #
###################
N_THREADS = [4, 2, 1]

# Julia executable settings #
#############################
JULIA_COMMAND = `$(Base.julia_cmd()) --color=yes`

##########
# Driver #
##########
function run_experiment()
    for mesh in MESHES
        for n_threads in N_THREADS
            println("""
                    **************************************************
                        RUNNING ANALYSIS WITH
                            MESH   : $(mesh)
                            THREADS: $(n_threads)
                    **************************************************
                    """)
            withenv("OMP_NUM_THREADS"   => n_threads,
                    "JULIA_NUM_THREADS" => n_threads) do
                global pkg_setup = """
                    import Pkg
                    Pkg.activate($(repr(@__DIR__)))
                """
                global thread_setup = """
                    import LinearAlgebra
                    LinearAlgebra.BLAS.set_num_threads($n_threads)
                """
                code  =  """
                    $pkg_setup
                    $thread_setup
                    include("eifel_threaded_juafem.jl")
                    run_assemble($(repr(mesh)), $(repr(RESULTPATH)); use_pardiso=$USE_PARDISO)
                """
                run(`$JULIA_COMMAND -e $code`)
                print("\n\n")
                # Process data
            end
        end
    end
end

#run_experiment()

#################
# Data analysis #
#################

function plot_results()
    mkpath(PLOTPATH)
    result_files = joinpath.(RESULTPATH, filter!(x -> endswith(x, ".jld2"), readdir(RESULTPATH)))

    global dfs = DataFrame[]
    for result in result_files
        @load result df
        # TODO: Fix this when saving to JLD
        df.cholmod_times_mean = mean(collect(df.cholmod_times[1]))
        push!(dfs, df)
    end
    global df = vcat(dfs...)

    ndofs = unique(df.ndofs)
    for ndof in ndofs
        df_ndof = df[df.ndofs .== ndof, :]
        plot_speedup(df_ndof, ndof)
    end
end

function plot_speedup(df::DataFrame, ndofs)
    axis = @pgf Axis(
    {
        title = "Scaling for ndofs = $ndofs",
        xmajorgrids,
        ymajorgrids,
        legend_pos="outer north east",
        xlabel = "Number of threads",
        ylabel = "Speedup",
    }
   )
    plots = []
    for val in [:assembly_time, :total_time, :time_step, :post_process_time, :cholmod_times_mean]
        data = df[val]
        push!(plots,
            @pgf PlotInc(
                {
                },
                Coordinates(df.nthreads, data[1] ./ data)
                )
           )
        push!(plots, LegendEntry(replace(String(val), "_" => " ")))
    end
    push!(axis, plots...)
    pgfsave(joinpath(PLOTPATH, "scaling_$ndofs.pdf"), axis)
end

# plot_results()

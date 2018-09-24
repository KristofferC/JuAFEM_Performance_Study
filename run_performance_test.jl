module JuaFEMPerformance
############
# Settings #
############

# LinearSolvers #
#################
# TODO Integrate pardiso 
USE_MKL_PARDISO = false # Requires Pardiso,jl with MKL support
USE_PARDISO     = false # Requires Paridso.jl with Paridso Project support
USE_CHOLMOD     = true

# Meshes #
##########
# TODO: Add the other meshes
const MESHES = ["EIFFEL_TOWER_TET10_220271.inp"]
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
const N_THREADS = [1, 4]

# Julia executable settings #
#############################
const JULIA_COMMAND = `$(Base.julia_cmd()) --color=yes`


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
                    run_assemble($(repr(mesh)))
                """
                run(`$JULIA_COMMAND -e $code`)
                print("\n\n")
                # Process data
            end
        end
    end
end

end

#model = "EIFFEL_TOWER_TET10_220271"
ENV["LINES"] = 120
model, setup = ARGS
n_machines, n_threads = split(setup, 'x')
import LinearAlgebra
LinearAlgebra.BLAS.set_num_threads(parse(Int, n_threads))
ENV["USE_OPENMP"] = 1
ENV["OPENBLAS_NUM_THREADS"] = n_threads
ENV["JULIA_NUM_THREADS"] = n_threads


using JuliaFEM
using TimerOutputs
using JuliaFEM.Preprocess
using JuliaFEM.Postprocess
add_elements! = JuliaFEM.add_elements!

function run_simulation(mesh, results)
    println("running")
    isfile(mesh) || error("Mesh file $mesh not found!")

    @timeit "initialize model" begin

        @timeit "parse input data" mesh = abaqus_read_mesh(mesh)

        @timeit "initialize models" begin
            tower = Problem(Elasticity, "tower", 3)
            tower_elements = create_elements(mesh, "TOWER")
            update!(tower_elements, "youngs modulus", 210.0E3)
            update!(tower_elements, "poissons ratio", 0.3)
            update!(tower_elements, "density", 7.85E-9)
            update!(tower_elements, "displacement load 3", -9810.0)
            add_elements!(tower, tower_elements)
            support = Problem(Dirichlet, "fixed", 3, "displacement")
            support_elements = create_surface_elements(mesh, "SUPPORT")
            update!(support_elements, "displacement 1", 0.0)
            update!(support_elements, "displacement 2", 0.0)
            update!(support_elements, "displacement 3", 0.0)
            add_elements!(support, support_elements)
            analysis = Solver(Linear, tower, support)
            xdmf = Xdmf(results; overwrite=true)
            add_results_writer!(analysis, xdmf)
            time = analysis.properties.time
            initialize!(tower, time)
            initialize!(support, time)
        end
    end

    local K, f, C1, g
    @timeit "assemble" begin
        @timeit "assemble problems" for problem in get_problems(analysis)
            assemble!(problem, time)
        end
        @timeit "construct global assemblies" begin
            @timeit "get_field_assembly" M, K, Kg, f, fg = get_field_assembly(analysis)
            ndofs = size(K, 2)
            @timeit "get_boundary_assembly" Kb, C1, C2, D, fb, g = get_boundary_assembly(analysis, ndofs)
            @timeit "sum K" K = K + Kg + Kb
            @timeit "sum f" f = f + fg + fb
        end
    end

    @timeit "solution" begin
        # free up some memory before solution by emptying field assemblies from problems
        for problem in get_field_problems(analysis)
            empty!(problem.assembly)
        end
        # at this point we basically have [u,la] = [K C1; C2 D] \ [f,g]
        @timeit "eliminate boundary conditions using penalty method" begin
            Kb = 1.0e36*C1'*C1
            fb = 1.0e36*C1'*g
        end
        @timeit "create symmetric K" Ks = LinearAlgebra.Symmetric(K+Kb)
        @timeit "factorize K" F = LinearAlgebra.cholesky(Ks)
        @timeit "solve u" u = F \ (f+fb)
        @timeit "solve la" la = f - K*u
        @timeit "update solution" update!(analysis, vec(full(u)), vec(full(la)), time)
    end

    @timeit "postprocess" begin
        tower.postprocess_fields = ["strain", "stress"]
        @timeit "postprocess strain" postprocess!(tower, time, Val{:strain})
        @timeit "postprocess stress" postprocess!(tower, time, Val{:stress})
    end

    @timeit "write results to disk" write_results!(analysis, time)

    close(xdmf.hdf)
end

mesh = joinpath(@__DIR__, "EIFFEL_TOWER_$model.inp")
results = "$(model)_$(setup)"
@timeit "run simulation 1" run_simulation(mesh, results)
print_timer(compact=true)

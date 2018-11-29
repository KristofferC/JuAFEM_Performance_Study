ENV["LINES"] = 120
if !isempty(ARGS)
    model, setup = ARGS
    n_machines, n_threads = parse(Int.(split(setup, 'x')))
else
    model = "TET10_220271"
    n_machines=1; n_threads=4
end
import LinearAlgebra
LinearAlgebra.BLAS.set_num_threads(n_threads)
ENV["USE_OPENMP"] = 1
ENV["OPENBLAS_NUM_THREADS"] = n_threads
ENV["JULIA_NUM_THREADS"] = n_threads

NEW_CODE = true

using FileIO
using JLD2
using JuliaFEM
if NEW_CODE
    using FEMBase
end
using TimerOutputs
using SparseArrays, LinearAlgebra
# using AMD
# using Metis


"""
    fill_diagonal(A)

Return a diagonal matrix `D` having 1.0 in all zero rows of matrix `A`. Then,
one haves matrix `A + D` which should be invertible.
"""
function fill_diagonal!(A)
    for col in 1:size(A, 2)
        for r in nzrange(A, col)
            row = A.rowval[r]
            if col == row && A.nzval[r] == 0
                A.nzval[r] = 1
            end
        end
    end
end

function fill_diagonal(A)
    N = size(A, 2)
    zero_rows = ones(N)
    for j in rowvals(A)
        zero_rows[j] = 0.0
    end
    return dropzeros(spdiagm(0 => zero_rows))
end


function renumber_mesh!(mesh)
    # Renumber nodes and elements so they start at 1

    #########
    # Nodes #
    #########
    node_mapping = Dict{Int, Int}()
    nodes = Dict{Int, Vector{Float64}}()
    for (i, node_id) in enumerate(sort(collect(keys(mesh.nodes))))
        nodes[i] = mesh.nodes[node_id]
        node_mapping[node_id] = i
    end

    ############
    # Elements #
    ############
    elements = Dict{Int, Vector{Float64}}()
    # The same comment about storing element numbers from 1:n applies here
    element_mapping = Dict{Int, Int}()
    for (i, element_id) in enumerate(sort(collect(keys(mesh.elements))))
        elements[i] = [node_mapping[z] for z in mesh.elements[element_id]]
        element_mapping[element_id] = i
    end

    ########
    # Sets #
    ########
    # The nodesets need use the new node ordering
    nodesets = Dict{Symbol, Set{Int}}()
    for (name, nodes) in mesh.node_sets
        nodesets[name] = Set(node_mapping[z] for z in nodes)
    end

    # So does the cell cets (element sets)
    elementsets = Dict{Symbol, Set{Int}}()
    for (name, elements) in mesh.element_sets
        elementsets[name] = Set(element_mapping[z] for z in elements)
    end

   # So does the cell cets (element sets)
    elementtypes = Dict{Int, Symbol}()
    for (element_id, typ) in mesh.element_types
        elementtypes[element_mapping[element_id]] = typ
    end

    surfacesets = Dict{Symbol, Vector{Tuple{Int, Symbol}}}()
    for (name, surface) in mesh.surface_sets
        surfacesets[name] = [(element_mapping[z[1]], z[2]) for z in surface]
    end

    mesh.nodes = nodes
    mesh.elements = elements
    mesh.node_sets = nodesets
    mesh.element_sets = elementsets
    mesh.element_types = elementtypes
    mesh.surface_sets = surfacesets
    return mesh
end

function run_simulation(mesh, results)
    println("running")
    isfile(mesh) || error("Mesh file $mesh not found!")

    @timeit "initialize model" begin

        @timeit "parse input data" mesh = abaqus_read_mesh(mesh)
        renumber_mesh!(mesh)

        @timeit "initialize models" begin
            tower = Problem(Elasticity, "tower", 3)
            tower_elements = create_elements(mesh, "TOWER")
            update!(tower_elements, "youngs modulus", 210.0E3)
            update!(tower_elements, "poissons ratio", 0.3)
            update!(tower_elements, "density", 7.85E-9)
            update!(tower_elements, "displacement load 3", -9810.0)
            add_elements!(tower, tower_elements)
            if NEW_CODE
                @timeit "create coloring" begin
                    coloring = JuliaFEM.create_coloring(mesh)
                    FEMBase.assign_colors!(tower, coloring)
                    tower.assemble_csc = true
                    tower.assemble_parallel = true
                end
            end
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

    local perm
    @timeit "timeloop" for i in 1:10
        for problem in get_field_problems(analysis)
            empty!(problem.assembly)
        end
        global K, f, C1, g
        @timeit "assemble" begin
            @timeit "assemble problems" for problem in get_problems(analysis)
                println("start assemble")
                @time assemble!(problem, time)
                println("end assemble")
            end
            @timeit "construct global assemblies" begin
                @timeit "get_field_assembly" M, K, Kg, f, fg = get_field_assembly(analysis)
                ndofs = size(K, 2)
                @timeit "get_boundary_assembly" Kb, C1, C2, D, fb, g = get_boundary_assembly(analysis, ndofs)
                # Don't care about this here
   #             @timeit "sum K" K = K + Kg + Kb
   #             @timeit "sum f" f = f + fg + fb
            end
        end

        # TODO: Investigate this
        d = [438517, 438518, 438519]
        Kd = sparse(d, d, [1.0, 1.0, 1.0], size(K,1), size(K,2))

        if NEW_CODE == true && i == 1
            @info "Created sparsity pattern, total number of nonzeros: $(nnz(K)), size $(Base.summarysize(K) / (1024^2)) MB"
        end
        @timeit "solution" begin
            # free up some memory before solution by emptying field assemblies from problems
            # TODO: Make this not empty K in place

            # at this point we basically have [u,la] = [K C1; C2 D] \ [f,g]
            @timeit "eliminate boundary conditions using penalty method" begin
                Kb = 1.0e36*C1'*C1
                fb = 1.0e36*C1'*g
            end
            @timeit "create symmetric K" Ks = LinearAlgebra.Symmetric(K+Kb+Kd)

            if NEW_CODE && i == 1
                # AMD gives a crappy reordering for some reason...
                #perm = AMD.amd(Ks.data)
                #@assert isperm(perm)
                # Metis is disabled for now
                #g = Metis.graph(Ks.data; check_hermitian=false)
                #perm, iperm = Metis.permutation(g)
            end

            if NEW_CODE
                @timeit "factorize K" F = LinearAlgebra.cholesky(Ks) #; perm = Vector{Int64}(perm))
            else
                @timeit "factorize K" F = LinearAlgebra.cholesky(Ks)
            end
            @info "Created factorization pattern, total number of nonzeros: $(nnz(F))"

            @timeit "solve u" u = F \ (f+fb)
            @timeit "solve la" la = f - K*u
            @timeit "update solution" update!(analysis, vec(Array(u)), vec(Array(la)), time)
        end
    end
#    @timeit "postprocess" begin
#        tower.postprocess_fields = ["strain", "stress"]
#        @timeit "postprocess strain" postprocess!(tower, time, Val{:strain})
#        @timeit "postprocess stress" postprocess!(tower, time, Val{:stress})
#    end

    @timeit "write results to disk" JuliaFEM.write_results!(analysis, time)

    close(xdmf.hdf)
end

mesh = joinpath(@__DIR__, "EIFFEL_TOWER_$model.inp")
results = "$(model)_$(n_threads)x$(n_machines)"
TimerOutputs.reset_timer!()
@timeit "run simulation 1" run_simulation(mesh, results)
print_timer(compact=true)

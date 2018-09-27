using JuAFEM, SparseArrays, TimerOutputs
using AbaqusReader, Tensors
using LinearAlgebra
using DataFrames
using JLD2
using FileIO
using Pardiso
using Statistics
using StructArrays
using Metis

# TODO:
# Add integration with other direct solvers
# Add export of stress + strain
# Add time statements and export to file

# Uses AbaqusReader.jl to read in an input file
# And then convert it to the JuaFEM format.
function create_juafem_grid(inpfile::AbstractString)
    @timeit "reading input" inpmesh = abaqus_read_mesh(inpfile)
    # In JuaFEM nodes are from 1:to:N

    @timeit "converting input to JuAFEM mesh" begin
    #########
    # Nodes #
    #########
    inpnodes = inpmesh["nodes"]
    # JuaFEM stores nodes from 1:n while they are not necessarily continous
    # in the abaqus file, so we remap them to 1:n to store in JuAFEM
    node_mapping = Dict{Int, Int}()
    nodes = Vector{JuAFEM.Node{3,Float64}}(undef, length(inpnodes))
    for (i, node_id) in enumerate(sort(collect(keys(inpnodes))))
        node_mapping[node_id] = i
        nodes[i] = JuAFEM.Node(Vec{3}(inpnodes[node_id]))
    end

    ############
    # Elements #
    ############
    inpelements = inpmesh["elements"]
    # QuadraticTetrahedron is hardcoded here
    cells = Vector{JuAFEM.QuadraticTetrahedron}(undef, length(inpelements))
    # The same comment about storing element numbers from 1:n applies here
    cell_mapping = Dict{Int, Int}()
    for (i, cell_id) in enumerate(sort(collect(keys(inpelements))))
        cell_mapping[cell_id] = i
        cells[i] = JuAFEM.QuadraticTetrahedron(([node_mapping[z] for z in inpelements[cell_id]]...,))
    end

    ########
    # Sets #
    ########
    # The nodesets need use the new node ordering
    nodesets = Dict{String, Set{Int}}()
    for (name, nodes) in inpmesh["node_sets"]
        nodesets[name] = Set(map(z -> node_mapping[z], nodes))
    end

    # So does the cell cets (element sets)
    cellsets = Dict{String, Set{Int}}()
    for (name, cell) in inpmesh["element_sets"]
        cellsets[name] = Set(map(z -> cell_mapping[z], cell))
    end
    end

    return JuAFEM.Grid(cells, nodes; cellsets=cellsets, nodesets=nodesets)
end;


# Data prameters for the problem
struct ProblemData{ST <: SymmetricTensor}
    E::Float64 # Youngs modulus
    ν::Float64
    ρ::Float64 # Density
    g::Float64 # Gravity
    C::ST
end

function ProblemData(E::Number, ν::Number, ρ::Number, g::Number, dim)
    λ = E*ν / ((1+ν) * (1 - 2ν))
    μ = E / (2(1+ν))
    δ(i,j) = i == j ? 1.0 : 0.0
    fC(i,j,k,l) = λ*δ(i,j)*δ(k,l) + μ*(δ(i,k)*δ(j,l) + δ(i,l)*δ(j,k))
    C = SymmetricTensor{4, dim}(fC);
    return ProblemData(E, ν, ρ, g, C)
end


# Data defined in quadrature points
struct QuadratureData{ST <: SymmetricTensor}
    σ::ST
    ϵ::ST
end

# This contains all the datastructures each thread needs to do an assembly
# Includes, local stiffness matrix, local force, things for evaluating basis
# and some other cached things
struct ScratchValues{dim, T, CV <: CellValues, FV <: FaceValues, TT <: SymmetricTensor, Ti}
    Ke::Matrix{T}
    fe::Vector{T}
    u_element::Vector{T}
    cellvalues::CV
    facevalues::FV
    global_dofs::Vector{Int}
    δɛ::Vector{TT}
    coordinates::Vector{Vec{dim, T}}
    assembler::JuAFEM.AssemblerSparsityPattern{T, Ti}
end;

# This return an instance of ScratchValues if the thread has
# allocated it, otherwise make the thread allocate a new one
# It is apparently important thta the thread that runs the
# code also executes the scratch value (precents false sharing?)
@inline function get_scratchvalue!(scratchvalues, K, f, dh)
    tid = Threads.threadid()
    if isassigned(scratchvalues, tid)
        return scratchvalues[tid]
    end
    scratchvalues[tid] = create_scratchvalues(K, f, dh)
end

function create_scratchvalues(K, f, dh::DofHandler{dim}) where {dim}
    assembler = start_assemble(K, f)
    refshape = RefTetrahedron
    order = 2

    interpolation_space = Lagrange{dim, refshape, 2}()
    quadrature_rule = QuadratureRule{dim, refshape}(order)
    face_quadrature_rule = QuadratureRule{dim-1, refshape}(order)
    cellvalues = CellVectorValues(quadrature_rule, interpolation_space);
    facevalues = FaceVectorValues(face_quadrature_rule, interpolation_space)

    n_basefuncs = getnbasefunctions(cellvalues)
    global_dofs = zeros(Int, ndofs_per_cell(dh))

    fe = zeros(n_basefuncs)
    Ke = zeros(n_basefuncs, n_basefuncs)

    ɛs = [zero(SymmetricTensor{2, dim}) for i in 1:n_basefuncs]

    coordinates = [zero(Vec{dim}) for i in 1:length(dh.grid.cells[1].nodes)]

    u_element = zeros(n_basefuncs)

    return ScratchValues(Ke, fe, u_element, cellvalues, facevalues, global_dofs,
                         ɛs, coordinates, assembler)
end

function doassemble!(K::SparseMatrixCSC, f, colors, dh::DofHandler, prob_data::ProblemData,
                    quad_data::Matrix{<:QuadratureData}, scratchvalues, u=nothing)
    fill!(K, 0.0)
    fill!(f, 0.0)
    for color in colors
        # Each color is safe to assemble threaded
        Threads.@threads for i in 1:length(color)
            scratchvalue = get_scratchvalue!(scratchvalues, K, f, dh)
            assemble_cell!(scratchvalue, color[i], K, dh, prob_data, quad_data, u)
        end
    end
    return
end

function assemble_cell!(scratch::ScratchValues{dim}, cell::Int, K::SparseMatrixCSC,
                        dh::DofHandler, prob_data::ProblemData, quad_data::Matrix{<:QuadratureData}, u=nothing) where {dim}

    # Unpack our stuff from the scratch
    Ke, fe, u_element ,cellvalues, facevalues, global_dofs, δɛ, coordinates, assembler =
         scratch.Ke, scratch.fe, scratch.u_element, scratch.cellvalues, scratch.facevalues,
         scratch.global_dofs, scratch.δɛ, scratch.coordinates, scratch.assembler

    fill!(Ke, 0)
    fill!(fe, 0)

    n_basefuncs = getnbasefunctions(cellvalues)
    celldofs!(global_dofs, dh, cell)

    # Force from gravity, apply it to last component
    Fg = -Vec{3}(i -> i == dim ? prob_data.g : 0.0) #= * prob_data.ρ =# # Is this in JuliaFEM??
    # Fill up the coordinates
    nodeids = dh.grid.cells[cell].nodes # Ugly
    for j in 1:length(coordinates)
        coordinates[j] = dh.grid.nodes[nodeids[j]].x # Ugly
    end

    reinit!(cellvalues, coordinates)
    if u !== nothing
        u_element .= getindex.((u,), global_dofs)
    end
    @inbounds for q_point in 1:getnquadpoints(cellvalues)
        dΩ = getdetJdV(cellvalues, q_point)
        if u !== nothing
            ɛ = symmetric(function_gradient(cellvalues, q_point, u_element))
            σ = prob_data.C ⊡ ɛ
            # Store quadrature data for this quadrature point
            quad_data[q_point, cell] = QuadratureData(ɛ, σ)
        else
            for i in 1:n_basefuncs
                δɛ[i] = symmetric(shape_gradient(cellvalues, q_point, i))
            end
            for i in 1:n_basefuncs
                δu = shape_value(cellvalues, q_point, i)
                fe[i] += (δu ⋅ Fg) * dΩ
                δɛ_iC = δɛ[i] ⊡ prob_data.C
                for j in 1:n_basefuncs
                    Ke[i, j] += (δɛ_iC ⊡ δɛ[j]) * dΩ
                end
            end
        end
    end

    @inbounds assemble!(assembler, global_dofs, fe, Ke)
    return
end

# Returns a vector with the stress / strain in the element simply computed as an
# average in the quadrature points
function export_quadrature_data(vtkfile, quad_data::Matrix{<:QuadratureData})
    quad_data_soa = StructArray(quad_data)
    n_eles = size(quad_data, 2)
    cell_data_σ = [mean(quad_data_soa.σ[:, i]) for i in 1:n_eles]
    cell_data_ϵ = [mean(quad_data_soa.ϵ[:, i]) for i in 1:n_eles]
    # TODO: Hardcoded 6 (Fix)
    vtk_cell_data(vtkfile, reshape(reinterpret(Float64, cell_data_σ), (6, n_eles)), "Stress")
    vtk_cell_data(vtkfile, reshape(reinterpret(Float64, cell_data_σ), (6, n_eles)), "Strain")
end

function run_assemble(mesh::AbstractString, output_path::AbstractString; use_pardiso=false)
    TimerOutputs.reset_timer!()
    nt = Threads.nthreads()
    total_time = @elapsed begin @timeit "analysis" begin
        setup_cost = @elapsed begin @timeit "setup cost" begin
            E = 200e3
            ν = 0.3
            ρ = 7.85e-9
            g = 9810.0

            dim = 3
            data = ProblemData(E, ν, ρ, g, dim)

            grid = create_juafem_grid(mesh)
            @timeit "create coloring mesh" cell_colors, final_colors = JuAFEM.create_coloring(grid)
            @info "Colored the mesh, total number of colors: $(length(final_colors))"

            dh = DofHandler(grid)
            push!(dh, :u, dim) # Add a displacement field
            @timeit "creating dofs" close!(dh)
            @info "Created degrees of freedom, total number of dofs: $(ndofs(dh))"

            dbc = ConstraintHandler(dh)
            # Add a homogenoush boundary condition on the "clamped" edge
            add!(dbc, Dirichlet(:u, getnodeset(grid, "SUPPORT"), (x,t) -> zero(Vec{dim}), collect(1:dim)))
            close!(dbc)
            @info "Created boundary conditions"

            @timeit "create sparsity pattern" K = create_sparsity_pattern(dh);

            @timeit "find minimizing perm" begin
                S = Metis.graph(K; check_hermitian=false)
                perm, iperm = Metis.permutation(S)
            end

            f = zeros(ndofs(dh))
            @info "Created sparsity pattern, total number of nonzeros: $(nnz(K)), size $(Base.summarysize(K) / (1024^2)) MB"

            # The type of scratchvalues is a bit complicated so just create one
            # and use typeof to allocate the space for it.
            s = create_scratchvalues(K, f, dh)

            quad_data = [QuadratureData(zero(SymmetricTensor{2,dim}), zero(SymmetricTensor{2, dim}))
                                 for qp in 1:getnquadpoints(s.cellvalues), n_ele in 1:getncells(grid)]

            scratchvalues = Vector{typeof(s)}(undef, nt)
        end end # setup cost
        if use_pardiso
            ps = Pardiso.MKLPardisoSolver()
            set_nprocs!(ps, nt)
            set_matrixtype!(ps, Pardiso.REAL_SYM_POSDEF)
            pardisoinit(ps)
        end

        local assembly_time
        local output_time
        local post_process_time
        local time_step
        cholmod_times = Float64[]
        pardiso_times = Float64[]
        first_fact = true
        for t in 1:2
            time_step = @elapsed begin @timeit "timesteps" begin
                println("****Timestep $t ****")
                @timeit "update boundary conditions" update!(dbc, t)
                @info "Updated boundary conditions for this timestep"

                assembly_time = @elapsed @timeit "assemble" begin
                    doassemble!(K, f, final_colors, dh, data, quad_data, scratchvalues);
                end
                @show sum(abs2, K)
                @show sum(abs2, f)
                @info "Assembled sparse matrix"
                @timeit "apply boundary conditions" apply!(K, f, dbc)
                @info "Applied boundary conditions"

                @time cholmod_time = @elapsed @timeit "factorization backslash" begin
                    u = cholesky(Symmetric(K); perm = Vector{Int64}(perm) ) \ f;
                end
                push!(cholmod_times, cholmod_time)
                @show sum(abs2, u)

                @info "Factorized and solved system"

                post_process_time = @elapsed begin @timeit "post processing" begin
                    doassemble!(K, f, final_colors, dh, data, quad_data, scratchvalues, u)
                end end

                output_time = @elapsed begin @timeit "data output" begin
                    vtkpath = joinpath(@__DIR__, "eifel_$(ndofs(dh)).vtu")
                    vtkfile = vtk_grid(vtkpath, dh)
                    vtk_point_data(vtkfile, dh, u)
                    export_quadrature_data(vtkfile, quad_data)
                    vtk_save(vtkfile)
                    @info "Output results to $(abspath(vtkpath))"
                end end

                if use_pardiso
                    pardiso_time = @elapsed begin @timeit "pardiso" begin
                        if first_fact == true
                            first_fact = false
                            K_pardiso = get_matrix(ps, K, :N)
                            set_phase!(ps, Pardiso.ANALYSIS)
                            pardiso(ps, K_pardiso, f)
                        end
                        K_pardiso = get_matrix(ps, K, :N)
                        set_phase!(ps, Pardiso.NUM_FACT)
                        pardiso(ps, K_pardiso, f)
                        set_phase!(ps, Pardiso.SOLVE_ITERATIVE_REFINE)
                        u_pardiso = similar(u) # Solution is stored in u_pardiso
                        pardiso(ps, u_pardiso, K_pardiso, f)
                        @show sum(abs2, u_pardiso)
                    end end
                    push!(pardiso_times, pardiso_time)
                else
                    push!(pardiso_times, NaN)
                end
            end end
        end
    end end # @timeit
    TimerOutputs.print_timer()
    println()

    df = DataFrame(ndofs = ndofs(dh), mesh = mesh, setup_cost = setup_cost, assembly_time = assembly_time,
                   nthreads = nt, total_time = total_time, time_step = time_step,
                   pardiso_times = Tuple(pardiso_times), cholmod_times = Tuple(cholmod_times), post_process_time = post_process_time)
    mkpath(output_path)
    file = joinpath(output_path, "$(basename(mesh))_$(nt).jld2")
    # TODO: Export to JLD instead, exporting to CSV when some of the cells are vectors
    # is weird
    @save file df
    @info "Wrote results to $file"
    println()
    return
end

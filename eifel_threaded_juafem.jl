using JuAFEM, SparseArrays, TimerOutputs
using AbaqusReader, Tensors
using LinearAlgebra

# Uses AbaqusReader.jl to read in an input file
# And then convert it to the JuaFEM format.
function create_juafem_grid(inpfile::AbstractString)
    inpmesh = abaqus_read_mesh(inpfile)
    # In JuaFEM nodes are from 1:to:N

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

    return JuAFEM.Grid(cells, nodes; cellsets=cellsets, nodesets=nodesets)
end;

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



# This create the elastic tangent
function create_stiffness(E::Number, ν::Number, dim::Int)
    return C
end;


# This contains all the datastructures each thread needs to do an assembly
# Includes, local stiffness matrix, local force, things for evaluating basis
# and some other cached things
struct ScratchValues{dim, T, CV <: CellValues, FV <: FaceValues, TT <: SymmetricTensor, Ti}
    Ke::Matrix{T}
    fe::Vector{T}
    cellvalues::CV
    facevalues::FV
    global_dofs::Vector{Int}
    ɛ::Vector{TT}
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

    return ScratchValues(Ke, fe, cellvalues, facevalues, global_dofs,
                         ɛs, coordinates, assembler)
end;

function doassemble(K::SparseMatrixCSC, f, colors, dh::DofHandler, data::ProblemData,
                    scratchvalues)
    for color in colors
        # Each color is safe to assemble threaded
        @timeit "assemble color" Threads.@threads for i in 1:length(color)
            scratchvalue = get_scratchvalue!(scratchvalues, K, f, dh)
            assemble_cell!(scratchvalue, color[i], K, dh, data)
        end
    end

    return K, f
end

function assemble_cell!(scratch::ScratchValues{dim}, cell::Int, K::SparseMatrixCSC,
                        dh::DofHandler, data::ProblemData) where {dim}

    # Unpack our stuff from the scratch
    Ke, fe, cellvalues, facevalues, global_dofs, ɛ, coordinates, assembler =
         scratch.Ke, scratch.fe, scratch.cellvalues, scratch.facevalues,
         scratch.global_dofs, scratch.ɛ, scratch.coordinates, scratch.assembler

    fill!(Ke, 0)
    fill!(fe, 0)

    n_basefuncs = getnbasefunctions(cellvalues)

    # Force from gravity, apply it to last component
    Fg = -Vec{3}(i -> i == dim ? data.g : 0.0) #= * data.ρ =# # Is this in JuliaFEM??
    # Fill up the coordinates
    nodeids = dh.grid.cells[cell].nodes # Ugly
    for j in 1:length(coordinates)
        coordinates[j] = dh.grid.nodes[nodeids[j]].x # Ugly
    end

    reinit!(cellvalues, coordinates)
    Fg = - data.ρ * Vec{3}((0.0, 0.0, data.g))
    @inbounds for q_point in 1:getnquadpoints(cellvalues)
        for i in 1:n_basefuncs
            ɛ[i] = symmetric(shape_gradient(cellvalues, q_point, i))
        end
        dΩ = getdetJdV(cellvalues, q_point)
        for i in 1:n_basefuncs
            δu = shape_value(cellvalues, q_point, i)
            fe[i] += (δu ⋅ Fg) * dΩ
            ɛC = ɛ[i] ⊡ data.C
            for j in 1:n_basefuncs
                Ke[i, j] += (ɛC ⊡ ɛ[j]) * dΩ
            end
        end
    end

    celldofs!(global_dofs, dh, cell)
    @inbounds assemble!(assembler, global_dofs, fe, Ke)
end;

# MKL Pardiso
# Standard Pardiso
# IterativeSolvers
# MUMPS?

function run_assemble(mesh::AbstractString)
    TimerOutputs.reset_timer!()
    @timeit "analysis" begin
    E = 200e3
    ν = 0.3
    ρ = 7.85e-9
    g = 9810.0

    dim = 3
    data = ProblemData(E, ν, ρ, g, dim)


    @timeit "read_input_and_convert" grid = create_juafem_grid(mesh)
    @timeit "create coloring mesh" cell_colors, final_colors = JuAFEM.create_coloring(grid)
    @info "Colored the mesh, total number of colors: $(length(final_colors))"

    dh = DofHandler(grid)
    push!(dh, :u, dim) # Add a displacement field
    close!(dh)
    @info "Created degrees of freedom, total number of dofs: $(ndofs(dh))"

    dbc = ConstraintHandler(dh)
    # Add a homogenoush boundary condition on the "clamped" edge
    add!(dbc, Dirichlet(:u, getnodeset(grid, "SUPPORT"), (x,t) -> zero(Vec{3}), [1,2,3]))
    close!(dbc)

    @timeit "create sparsity pattern" K = create_sparsity_pattern(dh);
    f = zeros(ndofs(dh))
    @info "Created sparsity pattern, total number of nonzeros: $(nnz(K)), size $(Base.summarysize(K) / (1024^2)) MB"

    # The type of scratchvalues is a bit complicated so just create one
    # and use typeof to allocate the space for it.
    s = create_scratchvalues(K, f, dh)
    scratchvalues = Vector{typeof(s)}(undef, Threads.nthreads())

    @timeit "timesteps" for t in 1:2
        t = 0.0
        update!(dbc, t)
        @info "Created boundary conditions"

        @timeit "assemble" K, f = doassemble(K, f, final_colors, dh, data, scratchvalues);
        @info "Assembled sparse matrix"
        apply!(K, f, dbc)
        @info "Applied boundary conditions"

        @timeit "factorization backslash" u = Symmetric(K) \ f;

        @info "Factorized and solved system"
        vtkpath = "eifel"
        vtkfile = vtk_grid("eifel", dh)
        vtk_point_data(vtkfile, dh, u)
        vtk_save(vtkfile)
        @info "Output results to $(abspath(vtkpath))"
    end
    end # @timeit
    TimerOutputs.print_timer()
    return
end

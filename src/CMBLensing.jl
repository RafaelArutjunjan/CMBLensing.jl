module CMBLensing

using Adapt
using Base.Broadcast: AbstractArrayStyle, ArrayStyle, Broadcasted, broadcasted,
    DefaultArrayStyle, preprocess_args, Style, result_style
using Base.Iterators: flatten, product, repeated, cycle, countfrom
using Base.Threads
using Base: @kwdef, @propagate_inbounds, Bottom, OneTo, showarg, show_datatype,
    show_default, show_vector, typed_vcat
using Combinatorics
using DataStructures
using DelimitedFiles
using Distributed: pmap, nworkers, myid, workers, addprocs, @everywhere, remotecall_wait, @spawnat
using FileIO
using FFTW
using InteractiveUtils
using IterTools: flagfirst
using JLD2: jldopen, JLDWriteSession
import KahanSummation
using Loess
using LinearAlgebra
using LinearAlgebra: diagzero, matprod, promote_op
using MacroTools: @capture, combinedef, isdef, isexpr, postwalk, splitdef
using Match
using Markdown
using Measurements
using Memoization
using OptimKit
using Pkg
using Printf
using ProgressMeter
using Random
using Random: seed!, AbstractRNG
using Roots
using Requires
using Setfield
using SparseArrays
using StaticArrays: @SMatrix, @SVector, SMatrix, StaticArray, StaticArrayStyle,
    StaticMatrix, StaticVector, SVector, SArray, SizedArray
using Statistics
using StatsBase
using UnPack
using Zygote
using Zygote: unbroadcast, Numeric, @adjoint, @nograd


import Adapt: adapt_structure
import Base: +, -, *, \, /, ^, ~, ≈, <, <=, |, &, ==,
    abs, adjoint, all, any, axes, broadcast, broadcastable, BroadcastStyle, conj, copy, convert,
    copy, copyto!, eltype, eps, fill!, getindex, getproperty, hash, hcat, hvcat, inv, isfinite,
    iterate, keys, lastindex, length, literal_pow, mapreduce, materialize!,
    materialize, one, permutedims, print_array, promote, promote_rule,
    promote_rule, promote_type, propertynames, real, setindex!, setproperty!, show,
    show_datatype, show_vector, similar, size, sqrt, string, sum, summary,
    transpose, zero
import Base.Broadcast: instantiate, preprocess
import LinearAlgebra: checksquare, diag, dot, isnan, ldiv!, logdet, mul!, norm,
    pinv, StructuredMatrixStyle, structured_broadcast_alloc, tr
import Measurements: ±
import Statistics: std


export
    @BandpowerParamOp, @ismain, @namedtuple, @repeated, @unpack, animate,
    argmaxf_lnP, BandPassOp, BaseDataSet, batch, batchindex, batchsize, beamCℓs, cache,
    CachedLenseFlow, camb, cov_to_Cℓ, cpu, Cℓ_2D, Cℓ_to_Cov, DataSet, DerivBasis,
    diag, Diagonal, DiagOp, dot, EBFourier, EBMap, expnorm, Field, FieldArray, fieldinfo,
    FieldMatrix, FieldOrOpArray, FieldOrOpMatrix, FieldOrOpRowVector,
    FieldOrOpVector, FieldRowVector, FieldTuple, FieldVector, FieldVector,
    firsthalf, fixed_white_noise, Flat, FlatEB, FlatEBFourier, FlatEBMap, FlatField, 
    FlatFieldFourier, FlatFieldMap, FlatFourier, FlatIEBCov, FlatIEBFourier, FlatIEBMap,
    FlatIQUFourier, FlatIQUMap, FlatMap, FlatQU, FlatQUFourier, FlatQUMap, FlatS0,
    FlatS02, FlatS2, FlatS2Fourier, FlatS2Map, Fourier, fourier∂, FuncOp, get_Cℓ,
    get_Cℓ, get_Dℓ, get_αℓⁿCℓ, get_ρℓ, get_ℓ⁴Cℓ, gradhess, gradient, HighPass,
    IEBFourier, IEBMap, InterpolatedCℓs, IQUFourier, IQUMap,
    lasthalf, LazyBinaryOp, LenseBasis, LenseFlow, LinOp, lnP, load_camb_Cℓs,
    load_chains, load_sim, LowPass, make_mask, Map, MAP_joint, MAP_marg,
    map∂, mean_std_and_errors, MidPass, mix, nan2zero, new_dataset, noiseCℓs,
    OuterProdOp, ParamDependentOp, pixwin, PowerLens, QUFourier, QUMap, resimulate!,
    resimulate, RK4Solver, S0, S02, S2, sample_joint, seed_for_storage!, shiftℓ,
    simulate, SymmetricFuncOp, symplectic_integrate, Taylens, toCℓ, toDℓ,
    tuple_adjoint, ud_grade, unbatch, unmix, Ð, Ł, δfϕ_δf̃ϕ, ℓ², ℓ⁴, ∇, ∇², ∇¹, ∇ᵢ,
    ∇⁰, ∇ⁱ, ∇₀, ∇₁, ⋅, ⨳
    
# generic stuff
include("util.jl")
include("util_fft.jl")
include("numerical_algorithms.jl")
include("generic.jl")
include("cls.jl")
include("field_tuples.jl")
include("field_vectors.jl")
include("specialops.jl")
include("flowops.jl")

# lensing
include("lenseflow.jl")
include("powerlens.jl")

# flat-sky maps
include("flat_fftgrid.jl")
include("flat_s0.jl")
include("flat_s2.jl")
include("flat_s0s2.jl")
include("flat_generic.jl")
include("flat_batch.jl")
include("masking.jl")
include("taylens.jl")
include("bilinearlens.jl")

# plotting
function animate end
@init @require PyPlot="d330b81b-6aea-500a-939a-2ce795aea3ee" include("plotting.jl")

# sampling and maximizing the posteriors
include("dataset.jl")
include("posterior.jl")
include("maximization.jl")
include("sampling.jl")
include("chains.jl")

# other estimates
include("quadratic_estimate.jl")

# curved-sky
include("healpix.jl")

include("autodiff.jl")

# gpu
is_gpu_backed(x) = false
@init @require CUDA="052768ef-5323-5732-b1bb-66c8b64840ba" include("gpu.jl")

# misc init
# see https://github.com/timholy/ProgressMeter.jl/issues/71 and links therein
@init if ProgressMeter.@isdefined ijulia_behavior
    ProgressMeter.ijulia_behavior(:clear)
end

end

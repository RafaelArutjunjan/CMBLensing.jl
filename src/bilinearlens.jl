
export BilinearLens

@doc doc"""

    BilinearLens(ϕ)
    
BilinearLens is a lensing operator that computes lensing with bilinear
interpolation. The action of the operator, as well as its adjoint, inverse,
inverse-adjoint, and gradient w.r.t. ϕ can all be computed. The log-determinant
of the operation is non-zero and can't be computed. 

Internally, BilinearLens forms a sparse matrix with the interpolation weights,
which can be applied and adjoint-ed extremely fast (e.g. at least an order of
magnitude faster than LenseFlow). Inverse and inverse-adjoint lensing is
somewhat slower as it is implemented with several steps of the [preconditioned
generalized minimal residual](https://en.wikipedia.org/wiki/Generalized_minimal_residual_method)
algorithm, taking anti-lensing as the preconditioner.

!!! warning 

    Due to [this bug](https://github.com/JuliaLang/PackageCompiler.jl/issues/379)
    in PackageCompiler, currently you have to run `using SparseArrays` by hand
    in your Julia session before `BilinearLens` is available.

"""
mutable struct BilinearLens{Φ,S} <: ImplicitOp{Basis,Spin,Pix}
    ϕ :: Φ
    sparse_repr :: S
    anti_lensing_sparse_repr :: Union{S, Nothing}
end

function BilinearLens(ϕ::FlatS0)
    
    # if ϕ == 0 then just return identity operator
    if norm(ϕ) == 0
        return BilinearLens(ϕ,I,I)
    end
    
    @unpack Nx,Ny,Nside,Δx,T = fieldinfo(ϕ)
    
    # the (i,j)-th pixel is deflected to (ĩs[i],j̃s[j])
    j̃s,ĩs = getindex.((∇*ϕ)./Δx, :Ix)
    ĩs .=  ĩs  .+ (1:Ny)
    j̃s .= (j̃s' .+ (1:Nx))'
    
    # sub2ind converts a 2D index to 1D index, including wrapping at edges
    indexwrapi(i) = mod(i - 1, Ny) + 1
    indexwrapj(i) = mod(i - 1, Nx) + 1
    sub2ind(i,j) = Base._sub2ind((Ny,Nx),indexwrapi(i),indexwrapj(j))

    # compute the 4 non-zero entries in L[I,:] (ie the Ith row of the sparse
    # lensing representation, L) and add these to the sparse constructor
    # matrices, M, and V, accordingly. this function is split off so it can be
    # called directly or used as a CUDA kernel
    function compute_row!(I, ĩ, j̃, M, V)

        # (i,j) indices of the 4 nearest neighbors
        left,right = floor(Int,ĩ) .+ (0, 1)
        top,bottom = floor(Int,j̃) .+ (0, 1)
        
        # 1-D indices of the 4 nearest neighbors
        M[4I-3:4I] .= @SVector[sub2ind(left,top), sub2ind(right,top), sub2ind(left,bottom), sub2ind(right,bottom)]
        
        # weights of these neighbors in the bilinear interpolation
        Δx⁻, Δx⁺ = ((left,right) .- ĩ)
        Δy⁻, Δy⁺ = ((top,bottom) .- j̃)
        A = @SMatrix[
            1 Δx⁻ Δy⁻ Δx⁻*Δy⁻;
            1 Δx⁺ Δy⁻ Δx⁺*Δy⁻;
            1 Δx⁻ Δy⁺ Δx⁻*Δy⁺;
            1 Δx⁺ Δy⁺ Δx⁺*Δy⁺
        ]
        V[4I-3:4I] .= inv(A)[1,:]

    end
    
    # a surprisingly large fraction of the computation for large Nside, so memoize it:
    @memoize getK(Nx,Ny) = Int32.((4:4*Nx*Ny+3) .÷ 4)

    # CPU
    function compute_sparse_repr(is_gpu_backed::Val{false})
        K = Vector{Int32}(getK(Nx,Ny))
        M = similar(K)
        V = similar(K,T)
        for I in 1:length(ĩs)
            compute_row!(I, ĩs[I], j̃s[I], M, V)
        end
        sparse(K,M,V,Nx*Ny,Nx*Ny)
    end

    # GPU
    function compute_sparse_repr(is_gpu_backed::Val{true})
        K = CuVector{Cint}(getK(Nx,Ny))
        M = similar(K)
        V = similar(K,T)
        cuda(ĩs, j̃s, M, V; threads=256) do ĩs, j̃s, M, V
            index = threadIdx().x
            stride = blockDim().x
            for I in index:stride:length(ĩs)
                compute_row!(I, ĩs[I], j̃s[I], M, V)
            end
        end
        # remove once CuSparseMatrixCOO makes it into official CUDA.jl:
        if !Base.isdefined(CUSPARSE,:CuSparseMatrixCOO)
            error("To use BilinearLens on GPU, run `using Pkg; pkg\"add https://github.com/marius311/CUDA.jl#coo\"` and restart Julia.")
        end
        switch2csr(CUSPARSE.CuSparseMatrixCOO{T}(K,M,V,(Nx*Ny,Nx*Ny)))
    end
    
    
    BilinearLens(ϕ, compute_sparse_repr(Val(is_gpu_backed(ϕ))), nothing)

end


# lazily computing the sparse representation for anti-lensing

function get_anti_lensing_sparse_repr!(Lϕ::BilinearLens)
    if Lϕ.anti_lensing_sparse_repr == nothing
        Lϕ.anti_lensing_sparse_repr = BilinearLens(-Lϕ.ϕ).sparse_repr
    end
    Lϕ.anti_lensing_sparse_repr
end


getϕ(Lϕ::BilinearLens) = Lϕ.ϕ
(Lϕ::BilinearLens)(ϕ) = BilinearLens(ϕ)

# applying various forms of the operator

function *(Lϕ::BilinearLens, f::FlatS0{P}) where {N,D,P<:Flat{N,<:Any,<:Any,D}}
    Lϕ.sparse_repr===I && return f
    Łf = Ł(f)
    f̃ = similar(Łf)
    ds = (D == 1 ? ((),) : tuple.(1:D))
    for d in ds
        mul!(@views(f̃.Ix[:,:,d...][:]), Lϕ.sparse_repr, @views(Łf.Ix[:,:,d...][:]))
    end
    f̃
end

function *(Lϕ::Adjoint{<:Any,<:BilinearLens}, f::FlatS0{P}) where {N,D,P<:Flat{N,<:Any,<:Any,D}}
    parent(Lϕ).sparse_repr===I && return f
    Łf = Ł(f)
    f̃ = similar(Łf)
    ds = (D == 1 ? ((),) : tuple.(1:D))
    for d in ds
        mul!(@views(f̃.Ix[:,:,d...][:]), parent(Lϕ).sparse_repr', @views(Łf.Ix[:,:,d...][:]))
    end
    f̃
end

function \(Lϕ::BilinearLens, f̃::FlatS0{P}) where {N,D,P<:Flat{N,<:Any,<:Any,D}}
    Łf̃ = Ł(f̃)
    f = similar(Łf̃)
    ds = (D == 1 ? ((),) : tuple.(1:D))
    for d in ds
        @views(f.Ix[:,:,d...][:]) .= gmres(
            Lϕ.sparse_repr, @views(Łf̃.Ix[:,:,d...][:]),
            Pl = get_anti_lensing_sparse_repr!(Lϕ), maxiter = 5
        )
    end
    f
end

function \(Lϕ::Adjoint{<:Any,<:BilinearLens}, f̃::FlatS0{P}) where {N,D,P<:Flat{N,<:Any,<:Any,D}}
    Łf̃ = Ł(f̃)
    f = similar(Łf̃)
    ds = (D == 1 ? ((),) : tuple.(1:D))
    for d in ds
        @views(f.Ix[:,:,d...][:]) .= gmres(
            parent(Lϕ).sparse_repr', @views(Łf̃.Ix[:,:,d...][:]),
            Pl = get_anti_lensing_sparse_repr!(parent(Lϕ))', maxiter = 5
        )
    end
    f
end


# optimizations for BilinearLens(0ϕ)
\(Lϕ::BilinearLens{<:Any,<:UniformScaling}, f::FlatS0{P}) where {N,P<:Flat{N}} = f
*(Lϕ::BilinearLens{<:Any,<:UniformScaling}, f::FlatS0{P}) where {N,P<:Flat{N}} = f
\(Lϕ::Adjoint{<:Any,<:BilinearLens{<:Any,<:UniformScaling}}, f::FlatS0{P}) where {N,P<:Flat{N}} = f
*(Lϕ::Adjoint{<:Any,<:BilinearLens{<:Any,<:UniformScaling}}, f::FlatS0{P}) where {N,P<:Flat{N}} = f


for op in (:*, :\)
    @eval function ($op)(Lϕ::Union{BilinearLens, Adjoint{<:Any,<:BilinearLens}}, f::FieldTuple)
        Łf = Ł(f)
        F = typeof(Łf)
        F(map(f->($op)(Lϕ,f), Łf.fs))
    end
end


# gradients

@adjoint BilinearLens(ϕ) = BilinearLens(ϕ), Δ -> (Δ,)

@adjoint function *(Lϕ::BilinearLens, f::Field{B}) where {B}
    f̃ = Lϕ * f
    function back(Δ)
        (∇' * (Ref(tuple_adjoint(Ł(Δ))) .* Ł(∇*f̃))), B(Lϕ*Δ)
    end
    f̃, back
end


# gpu

adapt_structure(storage, Lϕ::BilinearLens) = BilinearLens(adapt(storage, fieldvalues(Lϕ))...)

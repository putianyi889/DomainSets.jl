
"""
A product map is diagonal and acts on each of the components of x separately:
`y = f(x)` becomes `y_i = f_i(x_i)`.
"""
abstract type ProductMap{T} <: CompositeLazyMap{T} end

components(m::ProductMap) = m.maps
factors(d::ProductMap) = components(d)

VcatMapElement = Union{Map{<:SVector},Map{<:Number}}

ProductMap(maps::Tuple) = ProductMap(maps...)
ProductMap(maps::SVector) = ProductMap(maps...)
ProductMap(maps...) = TupleProductMap(maps...)
ProductMap(maps::VcatMapElement...) = VcatMap(maps...)
ProductMap(maps::AbstractVector) = VectorProductMap(maps)

ProductMap{T}(maps...) where {T} = _TypedProductMap(T, maps...)
_TypedProductMap(::Type{T}, maps...) where {T<:Tuple} = TupleProductMap(maps...)
_TypedProductMap(::Type{SVector{N,T}}, maps...) where {N,T} = VcatMap{T}(maps...)
_TypedProductMap(::Type{T}, maps...) where {T<:AbstractVector} = VectorProductMap{T}(maps...)

compatibleproductdims(d1::ProductMap, d2::ProductMap) =
	mapsize(d1) == mapsize(d2) &&
		all(map(==, map(mapsize, components(d1)), map(mapsize, components(d2))))

isconstant(m::ProductMap) = mapreduce(isconstant, &, components(m))
islinear(m::ProductMap) = mapreduce(islinear, &, components(m))
isaffine(m::ProductMap) = mapreduce(isaffine, &, components(m))

matrix(m::ProductMap) = toexternalmatrix(m, map(matrix, components(m)))
vector(m::ProductMap) = toexternalpoint(m, map(vector, components(m)))
constant(m::ProductMap) = toexternalpoint(m, map(constant, components(m)))

jacobian(m::ProductMap, x) =
	toexternalmatrix(m, map(jacobian, components(m), tointernalpoint(m, x)))
function jacobian(m::ProductMap{T}) where {T}
	if isaffine(m)
		ConstantMap{T}(matrix(m))
	else
		LazyJacobian(m)
	end
end

# diffvolume(m::ProductMap) = multiply_map(map(diffvolume, factors(m))...)

similarmap(m::ProductMap, ::Type{T}) where {T} = ProductMap{T}(components(m))

tointernalpoint(m::ProductMap, x) = x
toexternalpoint(m::ProductMap, y) = y

applymap(m::ProductMap, x) =
	toexternalpoint(m, map(applymap, components(m), tointernalpoint(m, x)))

productmap(map1, map2) = productmap1(map1, map2)
productmap1(map1, map2) = productmap2(map1, map2)
productmap2(map1, map2) = ProductMap(map1, map2)
productmap(map1::ProductMap, map2::ProductMap) =
	ProductMap(components(map1)..., components(map2)...)
productmap1(map1::ProductMap, map2) = ProductMap(components(map1)..., map2)
productmap2(map1, map2::ProductMap) = ProductMap(map1, components(map2)...)

for op in (:inverse, :leftinverse, :rightinverse)
    @eval $op(m::ProductMap) = ProductMap(map($op, components(m)))
	@eval $op(m::ProductMap, x) = toexternalpoint(m, map($op, components(m), tointernalpoint(m, x)))
end

function composedmap(m1::ProductMap, m2::ProductMap)
	if compatibleproductdims(m1, m2)
		ProductMap(map(composedmap, components(m1), components(m2)))
	else
		ComposedMap(m1,m2)
	end
end

mapsize(m::ProductMap) = (sum(t->mapsize(t,1), components(m)), sum(t->mapsize(t,2), components(m)))

isequalmap(m1::ProductMap, m2::ProductMap) = all(map(isequalmap, components(m1), components(m2)))
map_hash(m::ProductMap, h::UInt) = hashrec("ProductMap", collect(components(m)), h)

Display.combinationsymbol(m::ProductMap) = Display.Symbol('⊗')
Display.displaystencil(m::ProductMap) = composite_displaystencil(m)
show(io::IO, mime::MIME"text/plain", m::ProductMap) = composite_show(io, mime, m)
show(io::IO, m::ProductMap) = composite_show_compact(io, m)

"""
A `VcatMap` is a product map with domain and codomain vectors
concatenated (`vcat`) into a single vector.
"""
struct VcatMap{T,M,N,DIM1,DIM2,MAPS} <: ProductMap{SVector{N,T}}
    maps    ::  MAPS
end

VcatMap(maps::Union{Tuple,Vector}) = VcatMap(maps...)
VcatMap(maps...) = VcatMap{numtype(maps...)}(maps...)

VcatMap{T}(maps::Union{Tuple,Vector}) where T = VcatMap{T}(maps...)
function VcatMap{T}(maps...) where T
	M = sum(t->mapsize(t,1), maps)
	N = sum(t->mapsize(t,2), maps)
	VcatMap{T,M,N}(maps...)
end

mapdim(map) = mapsize(map,2)

VcatMap{T,M,N}(maps::Union{Tuple,Vector}) where {T,M,N} = VcatMap{T,M,N}(maps...)
function VcatMap{T,M,N}(maps...) where {T,M,N}
	DIM1 = map(t->mapsize(t,1), maps)
	DIM2 = map(t->mapsize(t,2), maps)
	VcatMap{T,M,N,DIM1,DIM2}(convert_numtype.(maps, Ref(T))...)
end

VcatMap{T,M,N,DIM1,DIM2}(maps...) where {T,M,N,DIM1,DIM2} =
	VcatMap{T,M,N,DIM1,DIM2,typeof(maps)}(maps)

mapsize(m::VcatMap{T,M,N}) where {T,M,N} = (M,N)

tointernalpoint(m::VcatMap{T,M,N,DIM1,DIM2}, x) where {T,M,N,DIM1,DIM2} =
	convert_fromcartesian(x, Val{DIM2}())
toexternalpoint(m::VcatMap{T,M,N,DIM1,DIM2}, y) where {T,M,N,DIM1,DIM2} =
	convert_tocartesian(y, Val{DIM1}())

size_as_matrix(A::AbstractArray) = size(A)
size_as_matrix(A::Number) = (1,1)

# The Jacobian is block-diagonal
function toexternalmatrix(m::VcatMap{T,M,N}, matrices) where {T,M,N}
	A = zeros(T, M, N)
	k = 0
	l = 0
	for el in matrices
		m,n = size_as_matrix(el)
		A[k+1:k+m,l+1:l+n] .= el
		k += m
		l += n
	end
	SMatrix{M,N}(A)
end


"""
A `VectorProductMap` is a product map where all components are univariate maps,
with inputs and outputs collected into a `Vector`.
"""
struct VectorProductMap{T<:AbstractVector,M} <: ProductMap{T}
    maps    ::  Vector{M}
end

VectorProductMap(maps::AbstractMap...) = VectorProductMap(maps)
VectorProductMap(maps) = VectorProductMap(collect(maps))
function VectorProductMap(maps::Vector)
	T = mapreduce(numtype, promote_type, maps)
	VectorProductMap{Vector{T}}(maps)
end

VectorProductMap{T}(maps::AbstractMap...) where {T} = VectorProductMap{T}(maps)
VectorProductMap{T}(maps) where {T} = VectorProductMap{T}(collect(maps))
function VectorProductMap{T}(maps::Vector) where {T}
	Tmaps = convert.(Map{eltype(T)}, maps)
	VectorProductMap{T,eltype(Tmaps)}(Tmaps)
end

# the Jacobian is a diagonal matrix
toexternalmatrix(m::VectorProductMap, matrices) = Diagonal(matrices)

mapsize(m::VectorProductMap) = (length(m.maps), length(m.maps))

"""
A `TupleProductMap` is a product map with all components collected in a tuple.
There is no vector-valued function associated with this map.
"""
struct TupleProductMap{T,MM} <: ProductMap{T}
    maps    ::  MM
end

TupleProductMap(maps::Vector) = TupleProductMap(maps...)
TupleProductMap(maps...) = TupleProductMap(maps)
function TupleProductMap(maps::Tuple)
	T = Tuple{map(domaintype, maps)...}
	TupleProductMap{T}(maps)
end

TupleProductMap{T}(maps::Vector) where {T} = TupleProductMap{T}(maps...)
TupleProductMap{T}(maps...) where {T} = TupleProductMap{T}(maps)
function TupleProductMap{T}(maps::NTuple{N,<:AbstractMap}) where {N,T <: Tuple}
	Tmaps = map((t,d) -> convert(Map{t},d), tuple(T.parameters...), maps)
	TupleProductMap{T,typeof(Tmaps)}(Tmaps)
end
TupleProductMap{T}(maps) where {T <: Tuple} = TupleProductMap{T,typeof(maps)}(maps)

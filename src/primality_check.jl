# ------------------------------------------------------------------------------

function check_primality_zerodim(J::Array{fmpq_mpoly, 1})
    J = Groebner.groebner(J)
    basis = Groebner.kbase(J)
    dim = length(basis)
    S = Nemo.MatrixSpace(Nemo.QQ, dim, dim)
    matrices = []
    @debug "" J basis
    @debug "Dim is $dim"
    for v in gens(parent(first(J)))
        M = zero(S)
        for (i, vec) in enumerate(basis)
            image = Groebner.normalform(J, v * vec)
            for (j, base_vec) in enumerate(basis)
                M[i, j] = Nemo.QQ(coeff(image, base_vec))
            end
        end
        push!(matrices, M)
        @debug "Multiplication by $v" M
    end
    generic_multiplication = sum(Nemo.QQ(rand(1:100)) * M for M in matrices)
    @debug "" generic_multiplication
    
    R, t = Nemo.PolynomialRing(Nemo.QQ, "t")
    @debug "" Nemo.charpoly(R, generic_multiplication)
    
    return Nemo.isirreducible(Nemo.charpoly(R, generic_multiplication))
end

#------------------------------------------------------------------------------
"""
    check_primality(polys::Dict{fmpq_mpoly, fmpq_mpoly}, extra_relations::Array{fmpq_mpoly, 1})

The function checks if the ideal generated by the polynomials and saturated at
the leading coefficient with respect to the corresponding variables is prime
over rationals.

The `extra_relations` allows adding more polynomials to the generators (not affecting the saturation).
"""
function check_primality(
    polys::Dict{fmpq_mpoly, fmpq_mpoly},
    extra_relations::Array{fmpq_mpoly, 1},
)
    leaders = collect(keys(polys))
    ring = parent(leaders[1])

    Rspec, vspec = Nemo.PolynomialRing(Nemo.QQ, [var_to_str(l) for l in leaders])
    eval_point = [v in keys(polys) ? v : ring(rand(1:100)) for v in gens(ring)]
    all_polys = vcat(collect(values(polys)), extra_relations)
    runtime = @elapsed zerodim_ideal =
        collect(map(p -> parent_ring_change(evaluate(p, eval_point), Rspec), all_polys))
    _runtime_logger[:id_primality_evaluate] += runtime

    return check_primality_zerodim(zerodim_ideal)
end

#------------------------------------------------------------------------------
"""
    check_primality(polys::Dict{fmpq_mpoly, fmpq_mpoly})

The function checks if the ideal generated by the polynomials and saturated at
the leading coefficient with respect to the corresponding variables is prime
over rationals.
"""
function check_primality(polys::Dict{fmpq_mpoly, fmpq_mpoly})
    return check_primality(polys, Array{fmpq_mpoly, 1}())
end

# ------------------------------------------------------------------------------

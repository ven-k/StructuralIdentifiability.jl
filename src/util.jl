#------------------------------------------------------------------------------

function eval_at_dict(poly::P, d::Dict{P, <: RingElem}) where P <: MPolyElem
    """
    Evaluates a polynomial on a dict var => val
    missing values are replaced with zeroes
    """
    R = parent(first(values(d)))
    point = [get(d, v, zero(R)) for v in gens(parent(poly))]
    return evaluate(poly, point)
end

function eval_at_dict(rational::Generic.Frac{<: P}, d::Dict{P, <: RingElem}) where P <: MPolyElem
    f, g = unpack_fraction(rational)
    return eval_at_dict(f, d) * inv(eval_at_dict(g, d))
end

#------------------------------------------------------------------------------

function unpack_fraction(f::MPolyElem)
    return (f, one(parent(f)))
end

function unpack_fraction(f::Generic.Frac{<: MPolyElem})
    return (numerator(f), denominator(f))
end

#------------------------------------------------------------------------------

function simplify_frac(numer::P, denom::P) where P <: MPolyElem
    gcd_sub = gcd(numer, denom)
    sub_numer = divexact(numer, gcd_sub)
    sub_denom = divexact(denom, gcd_sub)
    return sub_numer, sub_denom
end

#------------------------------------------------------------------------------

function make_substitution(f::P, var_sub::P, val_numer::P, val_denom::P) where P <: MPolyElem
    """
    Substitute a variable in a polynomial with an expression
    Input:
        - f, the polynomial
        - var_sub, the variable to be substituted
        - var_numer, numerator of the substitution expression
        - var_denom, denominator of the substitution expression
    Output:
        polynomial, result of substitution
    """
    d = degree(f, var_sub)

    result = 0
    @debug "Substitution in a polynomial of degree $d"
    flush(stdout)
    for i in 0:d
        @debug "\t Degree $i"
        flush(stdout)
        result += coeff(f, [var_sub], [i]) * (val_numer ^ i) * (val_denom ^ (d - i))
        @debug "\t Intermediate result of size $(length(result))"
    end
    return result
end

#------------------------------------------------------------------------------

function (F::Nemo.GaloisField)(a::fmpq)
    den = denominator(a)
    if F(den) == 0
        throw(Base.ArgumentError("Denominator of $a vanishes in $F"))
    end
    return F(numerator(a)) // den
end

function parent_ring_change(poly::MPolyElem, new_ring::MPolyRing)
    """
    Converts a polynomial to a different polynomial ring
    Input
      - poly - a polynomial to be converted
      - new_ring - a polynomial ring such that every variable name
          appearing in poly appears among the generators
    Output: a polynomial in new_ring "equal" to poly
    """
    old_ring = parent(poly)
    # construct a mapping for the variable indices
    var_mapping = Array{Any, 1}()
    for u in symbols(old_ring)
        push!(
            var_mapping,
            findfirst(v -> (string(u) == string(v)), symbols(new_ring))
        )
    end
    builder = MPolyBuildCtx(new_ring)
    for term in zip(exponent_vectors(poly), coeffs(poly))
        exp, coef = term
        new_exp = [0 for _ in gens(new_ring)]
        for i in 1:length(exp)
            if exp[i] != 0
                if var_mapping[i] == nothing
                    throw(Base.ArgumentError("The polynomial contains a variable not present in the new ring $poly"))
                else
                    new_exp[var_mapping[i]] = exp[i]
                end
            end
        end
        push_term!(builder, new_ring.base_ring(coef), new_exp)
    end
    return finish(builder)
end

function parent_ring_change(f::Generic.Frac{<: MPolyElem}, new_ring::MPolyRing)
    n, d = unpack_fraction(f)
    return parent_ring_change(n, new_ring) // parent_ring_change(d, new_ring)
end
 
#------------------------------------------------------------------------------

function uncertain_factorization(f::MPolyElem{fmpq})
    """
    Input: polynomial f with rational coefficients
    Output: list of pairs (div, certainty) where
      - div's are divisors f such that f is their product with certain powers
      - if certainty is true, div is Q-irreducible
    """
    vars_f = vars(f)
    if isempty(vars_f)
        return Array{Tuple{typeof(f), Bool}, 1}()
    end
    main_var = vars_f[end]
    d = degree(f, main_var)
    lc_f = coeff(f, [main_var], [d])
    gcd_coef = lc_f
    for i in  (d - 1):-1:0
        gcd_coef = gcd(gcd_coef, coeff(f, [main_var], [i]))
    end
    f = divexact(f, gcd_coef)
    lc_f = coeff(f, [main_var], [d])

    is_irr = undef
    while true
        plugin = rand(5:10, length(vars_f) - 1)
        if evaluate(lc_f, vars_f[1 : end - 1], plugin) != 0
            f_sub = evaluate(f, vars_f[1 : end - 1], plugin)
            uni_ring, var_uni = PolynomialRing(base_ring(f), string(main_var))
            f_uni = to_univariate(uni_ring, f_sub)
            if !issquarefree(f_uni)
                f = divexact(f, gcd(f, derivative(f, main_var)))
            end
            is_irr = isirreducible(f_uni)
            break
        end
    end

    coeff_factors = uncertain_factorization(gcd_coef)
    push!(coeff_factors, (f, is_irr))
end

#------------------------------------------------------------------------------

function factor_via_singular(polys::Array{<: MPolyElem{fmpq}, 1})
    if isempty(polys)
        return []
    end
    original_ring = parent(polys[1])
    R_sing, var_sing = Singular.PolynomialRing(Singular.QQ, map(string, symbols(original_ring)))
    result = Array{typeof(polys[1]), 1}()
    for p in polys
        @debug "\t Factoring with Singular a polynomial of size $(length(p))"
        @debug p
        p_sing = parent_ring_change(p, R_sing)
        for f in Singular.factor_squarefree(p_sing)
            @debug f
            push!(result, parent_ring_change(f[1], original_ring))
        end
    end
    return result
end

#------------------------------------------------------------------------------

function fast_factor(poly::MPolyElem{fmpq})
    prelim_factors = uncertain_factorization(poly)
    cert_factors = map(pair -> pair[1], filter(f -> f[2], prelim_factors))
    uncert_factors = map(pair -> pair[1], filter(f -> !f[2], prelim_factors))
    append!(cert_factors, factor_via_singular(uncert_factors))
    return cert_factors
end

#------------------------------------------------------------------------------

function dict_to_poly(dict_monom::Dict{Array{Int, 1}, <: RingElem}, poly_ring::MPolyRing)
    builder = MPolyBuildCtx(poly_ring)
    for (monom, coef) in pairs(dict_monom)
        push_term!(builder, poly_ring.base_ring(coef), monom)
    end
    return finish(builder)
end

#------------------------------------------------------------------------------

function extract_coefficients(poly::P, variables::Array{P, 1}) where P <: MPolyElem
    """
    Intput:
        poly - multivariate polynomial
        variables - a list of variables from the generators of the ring of p
    Output:
        dictionary with keys being tuples of length len(variables) and values being 
        polynomials in the variables other than variables which are the coefficients
        at the corresponding monomials (in a smaller polynomial ring)
    """
    var_to_ind = Dict([(v, findfirst(e -> (e == v), gens(parent(poly)))) for v in variables])
    indices = [var_to_ind[v] for v in variables]

    coeff_vars = filter(v -> !(var_to_str(v) in map(var_to_str, variables)), gens(parent(poly)))
    new_ring, new_vars = PolynomialRing(base_ring(parent(poly)), map(var_to_str, coeff_vars))
    coeff_var_to_ind = Dict([(v, findfirst(e -> (e == v), gens(parent(poly)))) for v in coeff_vars])
    FieldType = typeof(one(base_ring(new_ring)))

    result = Dict{Array{Int, 1}, Dict{Array{Int, 1}, FieldType}}()

    for (monom, coef) in zip(exponent_vectors(poly), coeffs(poly))
        var_slice = [monom[i] for i in indices]
        if !haskey(result, var_slice)
            result[var_slice] = Dict{Array{Int, 1}, FieldType}()
        end
        new_monom = [0 for _ in 1:length(coeff_vars)]
        for i in 1:length(new_monom)
            new_monom[i] = monom[coeff_var_to_ind[coeff_vars[i]]]
        end
        result[var_slice][new_monom] = coef
    end

    return Dict(k => dict_to_poly(v, new_ring) for (k, v) in result)
end

#------------------------------------------------------------------------------

function str_to_var(s::String, ring::MPolyRing)
    ind = findfirst(v -> (string(v) == s), symbols(ring))
    if ind == nothing
        throw(Base.KeyError("Variable $s is not found in ring $ring"))
    end
    return gens(ring)[ind]
end

#------------------------------------------------------------------------------

function var_to_str(v::MPolyElem)
    ind = findfirst(vv -> vv == v, gens(parent(v)))
    return string(symbols(parent(v))[ind])
end

#------------------------------------------------------------------------------

function switch_ring(v::MPolyElem, ring::MPolyRing)
    """
    For a variable v, returns a variable in ring with the same name
    """
    ind = findfirst(vv -> vv == v, gens(parent(v)))
    return str_to_var(string(symbols(parent(v))[ind]), ring)
end

#------------------------------------------------------------------------------

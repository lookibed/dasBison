options gen2
options indenting = 4
options strict_smart_pointers = true

module prec shared public

require bison/lalr
require math

// Precedence and associativity as yacc declares them, kept in the builder's `prec_terms` and
// `prec_prods`; `build_lalr` never reads them.

//! How equal precedences break a shift/reduce tie: left reduces, right shifts, nonassoc errs.
enum PrecAssoc {
    left = 1
    right
    nonassoc
}

def private declare_level(var gb : LalrBuilder; terms : array<int>; assoc : PrecAssoc) {
    var level = 1
    for (p in gb.prec_terms) {
        level = max(level, p.x + 1)
    }
    for (term in terms) {
        if (term >= length(gb.prec_terms)) {
            gb.prec_terms |> resize(term + 1)
        }
        gb.prec_terms[term] = int2(level, int(assoc))
    }
}

//! `%left terms`: the terminals get the next precedence level, left-associative.
def prec_left(var gb : LalrBuilder; terms : array<int>) {
    declare_level(gb, terms, PrecAssoc.left)
}

//! `%right terms`: the terminals get the next precedence level, right-associative.
def prec_right(var gb : LalrBuilder; terms : array<int>) {
    declare_level(gb, terms, PrecAssoc.right)
}

//! `%nonassoc terms`: the terminals get the next precedence level, non-associative.
def prec_nonassoc(var gb : LalrBuilder; terms : array<int>) {
    declare_level(gb, terms, PrecAssoc.nonassoc)
}

//! `%prec term` on production `prod` (its index in `gb.prods`, `length(gb.prods) - 1` right after
//! `add_production`): the production takes the precedence of `term` instead of its last terminal's.
def prec_of_production(var gb : LalrBuilder; prod, term : int) {
    let from = length(gb.prec_prods)
    if (prod >= from) {
        gb.prec_prods |> resize(prod + 1)
        for (i in range(from, prod + 1)) {
            gb.prec_prods[i] = -1
        }
    }
    gb.prec_prods[prod] = term
}

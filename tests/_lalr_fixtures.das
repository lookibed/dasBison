options gen2
options indenting = 4

module _lalr_fixtures shared public

require bison/lalr
require daslib/strings_boost

//! `lhs ::= words` into `gb`: a word starting with an upper-case letter is a rule, any other a
//! terminal; the production's index in the builder
def prod(var gb : LalrBuilder; lhs : string; text : string) : int {
    var rhs : array<int>
    for (w in split(text, " ")) {
        continue if (empty(w))
        let c = first_character(w)
        rhs |> push(c >= 'A' && c <= 'Z' ? rule_sym(rule_id(gb, w)) : term_sym(term_id(gb, w)))
    }
    add_production(gb, rule_id(gb, lhs), rhs)
    return length(gb.prods) - 1
}

//! the terminal ids of the words of `text`: a word that is no terminal of `gb` is `num` when the
//! grammar has one, else -1
def tokens(gb : LalrBuilder; text : string) : array<int> {
    let unknown = gb.term_index?["num"] ?? -1
    return <- [for (w in split(text, " ")); gb.term_index?[w] ?? unknown; where !empty(w)]
}

//! `S ::= if C then S | if C then S else S | other`, `C ::= cond`
def dangling_else() : LalrBuilder {
    var gb : LalrBuilder
    prod(gb, "S", "if C then S")
    prod(gb, "S", "if C then S else S")
    prod(gb, "S", "other")
    prod(gb, "C", "cond")
    return <- gb
}

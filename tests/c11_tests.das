options gen2
options indenting = 4

require dastest/testing_boost public
require bison/bytes
require daslib/strings_boost
require _grammar_c11

// the C11 grammar with one terminal id per token and no byte layer: every byte set it uses is one
// byte, named by its token
def private c11_int_builder(t : T?; gb : GrammarBuilder) : LalrBuilder {
    var lb : LalrBuilder
    for (name in gb.rule_names) {
        rule_id(lb, name)
    }
    for (gp in gb.prods) {
        var inscope rhs : array<int>
        for (s in gp.rhs) {
            if (s.is_rule) {
                rhs |> push(rule_sym(s.rule))
                continue
            }
            var inscope bs <- [for (b in range(256)); b; where s.bytes[b]]
            t |> equal(length(bs), 1)
            let b = bs[0]
            rhs |> push(term_sym(term_id(lb, b >= 128 ? TOKEN_NAMES[b - 128] : "'{to_char(b)}'")))
        }
        add_production(lb, gp.lhs, rhs)
    }
    return <- lb
}

def private has_line(lines : array<string>; part1, part2 : string) : bool {
    for (l in lines) {
        return true if (find(l, part1) >= 0 && find(l, part2) >= 0)
    }
    return false
}

[test(description = "the C11 grammar builds through the byte adapter to dasLR1's counts: 479 states, 98 classes, the _Atomic ( and dangling-else conflicts", timeout = 1200)]
def test_c11_bytes(t : T?) {
    var gb : GrammarBuilder
    let root = build_c11(gb)
    t |> equal(length(gb.prods), 274)
    let g <- build_grammar(gb, root)
    t |> equal(g.tables.err, "")
    t |> equal(g.nclasses, 98)
    t |> equal(g.tables.nstates, 479)
    t |> equal(g.tables.conflicts, 2)
    t |> equal(length(g.tables.prods), 275)
    let lines <- describe_conflicts(g.tables)
    t |> equal(length(lines), 2)
    t |> success(has_line(lines, "on '(': shift", "reduce type_qualifier ::= byte 196"),
                 "_Atomic (")
    let if_reduce = "reduce selection_statement ::= byte 184 '(' expression ')' statement"
    t |> success(has_line(lines, "on byte 185: shift", if_reduce), "dangling else")
}

[test(description = "the C11 grammar with one integer terminal per token builds to the same 479 states and the same two conflicts", timeout = 1200)]
def test_c11_int(t : T?) {
    var gb : GrammarBuilder
    let root = build_c11(gb)
    let lb <- c11_int_builder(t, gb)
    let tb <- build_lalr(lb, root)
    t |> equal(tb.err, "")
    t |> equal(tb.nterms, length(lb.term_names) + 1)
    t |> equal(tb.nstates, 479)
    t |> equal(tb.conflicts, 2)
    let lines <- describe_conflicts(tb)
    t |> success(has_line(lines, "on '(': shift", "reduce type_qualifier ::= ATOMIC"), "_Atomic (")
    let if_reduce = "reduce selection_statement ::= IF '(' expression ')' statement"
    t |> success(has_line(lines, "on ELSE: shift", if_reduce), "dangling else")
}

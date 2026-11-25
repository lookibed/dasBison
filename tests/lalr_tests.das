options gen2
options indenting = 4

require dastest/testing_boost public
require bison/lalr
require daslib/strings_boost

// `lhs ::= words`: a word starting with an upper-case letter is a rule, any other a terminal
def private prod(var gb : LalrBuilder; lhs : string; text : string) {
    var rhs : array<int>
    for (w in split(text, " ")) {
        continue if (empty(w))
        let c = first_character(w)
        rhs |> push(c >= 'A' && c <= 'Z' ? rule_sym(rule_id(gb, w)) : term_sym(term_id(gb, w)))
    }
    add_production(gb, rule_id(gb, lhs), rhs)
}

def private tid(gb : LalrBuilder; name : string) : int => gb.term_index?[name] ?? -1

def private tokens(gb : LalrBuilder; text : string) : array<int> =>
    <- [for (w in split(text, " ")); gb.term_index?[w] ?? -1; where !empty(w)]

def private expr_grammar() : LalrBuilder {
    var gb : LalrBuilder
    prod(gb, "E", "E + T")
    prod(gb, "E", "T")
    prod(gb, "T", "T * F")
    prod(gb, "T", "F")
    prod(gb, "F", "( E )")
    prod(gb, "F", "id")
    return <- gb
}

def private dangling_else() : LalrBuilder {
    var gb : LalrBuilder
    prod(gb, "S", "if C then S")
    prod(gb, "S", "if C then S else S")
    prod(gb, "S", "other")
    prod(gb, "C", "cond")
    return <- gb
}

[test(description = "the textbook expression grammar builds to its twelve LALR(1) states with no conflict and parses by precedence")]
def test_expression_grammar(t : T?) {
    let gb <- expr_grammar()
    let tb <- build_lalr(gb, gb.rule_index?["E"] ?? -1)
    t |> equal(tb.err, "")
    t |> equal(tb.nstates, 12)
    t |> equal(tb.conflicts, 0)
    t |> equal(length(tb.alt), 0)
    t |> equal(tb.nterms, 6)
    t |> equal(tb.term_names[tb.eof], "<end>")
    {
        for (s in ["id", "id + id * id", "( id + id ) * id", "( ( id ) )"]) {
            let r <- lr_parse(tb, tokens(gb, s))
            t |> success(r.ok, s)
        }
    }
    {
        let r <- lr_parse(tb, tokens(gb, "id + id * id"))
        let names <- [for (p in r.reductions); describe_prod(tb, p)]
        t |> equal(names[length(names) - 2], "T ::= T * F")
        t |> equal(names[length(names) - 1], "E ::= E + T")
    }
    {
        let r <- lr_parse(tb, tokens(gb, "id + * id"))
        t |> success(!r.ok)
        t |> equal(r.pos, 2)
        t |> equal(r.token, tid(gb, "*"))
        t |> equal(r.expected, [tid(gb, "("), tid(gb, "id")])
    }
    {
        let r <- lr_parse(tb, tokens(gb, "( id +"))
        t |> success(!r.ok)
        t |> equal(r.pos, 3)
        t |> equal(r.token, tb.eof)
        t |> equal(length(r.expected), 2)
    }
    {
        let r <- lr_parse(tb, tokens(gb, "id id"))
        t |> success(!r.ok)
        t |> equal(r.pos, 1)
        t |> equal(r.expected, [tid(gb, "+"), tid(gb, "*"), tb.eof])
    }
}

// LALR merges the states after `a c` and `b c`, so `E ::= c` reduces on both `x` and `y` there
def private merged_lookaheads() : LalrBuilder {
    var gb : LalrBuilder
    prod(gb, "S", "a E x")
    prod(gb, "S", "b E y")
    prod(gb, "E", "c")
    prod(gb, "E", "c z")
    return <- gb
}

[test(description = "the expected set is the one of the stack the refused token was read on: after a merged state reduces on the doomed token, a terminal the reduce made unreachable stays expected")]
def test_expected_before_reduce(t : T?) {
    let gb <- merged_lookaheads()
    let tb <- build_lalr(gb, gb.rule_index?["S"] ?? -1)
    t |> equal(tb.err, "")
    let r <- lr_parse(tb, tokens(gb, "a c y"))
    t |> success(!r.ok)
    t |> equal(r.pos, 2)
    t |> equal(r.token, tid(gb, "y"))
    t |> equal(describe_prod(tb, r.reductions[0]), "E ::= c")
    t |> equal(r.expected, [tid(gb, "x"), tid(gb, "z")])
}

[test(description = "the dangling else keeps exactly one shift/reduce cell, both actions in it, and the primary shift binds else to the inner if")]
def test_dangling_else(t : T?) {
    let gb <- dangling_else()
    let tb <- build_lalr(gb, gb.rule_index?["S"] ?? -1)
    t |> equal(tb.err, "")
    t |> equal(tb.conflicts, 1)
    t |> equal(length(tb.alt), 1)
    let lines <- describe_conflicts(tb)
    t |> equal(length(lines), 1)
    t |> success(find(lines[0], "on else: shift to") >= 0, lines[0])
    t |> success(find(lines[0], "| reduce S ::= if C then S") >= 0, lines[0])
    t |> success(starts_with(tb.first_conflict, "shift/reduce conflict in state"),
                 tb.first_conflict)
    for (cell, extra in keys(tb.alt), values(tb.alt)) {
        t |> equal(cell % tb.nterms, tid(gb, "else"))
        t |> success(tb.action[cell] > 0, "the shift stays primary")
        t |> equal(length(extra), 1)
        t |> success(extra[0] < 0, "the reduce is kept in alt")
    }
    let r <- lr_parse(tb, tokens(gb, "if cond then if cond then other else other"))
    t |> success(r.ok)
    let ifs <- [for (p in r.reductions); describe_prod(tb, p);
                where tb.prods[p].lhs == (gb.rule_index?["S"] ?? -1) && length(tb.prods[p].rhs) > 1]
    t |> equal(ifs, ["S ::= if C then S else S", "S ::= if C then S"])
}

[test(description = "two rules deriving the same terminal keep a reduce/reduce cell with both reductions")]
def test_reduce_reduce(t : T?) {
    var gb : LalrBuilder
    prod(gb, "S", "A")
    prod(gb, "S", "B")
    prod(gb, "A", "x")
    prod(gb, "B", "x")
    let tb <- build_lalr(gb, rule_id(gb, "S"))
    t |> equal(tb.conflicts, 1)
    t |> success(starts_with(tb.first_conflict, "reduce/reduce conflict"), tb.first_conflict)
    let lines <- describe_conflicts(tb)
    t |> success(find(lines[0], "on <end>: reduce A ::= x | reduce B ::= x") >= 0, lines[0])
}

[test(description = "a reachable rule that derives no terminal string, or has no production, fails the build naming the rule; an unreachable one does not")]
def test_ill_formed(t : T?) {
    {
        var gb : LalrBuilder
        prod(gb, "S", "A x")
        prod(gb, "A", "A y")
        let tb <- build_lalr(gb, rule_id(gb, "S"))
        t |> equal(tb.err, "rule 'A' derives no terminal string")
        t |> equal(tb.err_rule, "A")
        t |> equal(tb.nstates, 0)
        t |> success(!lr_parse(tb, tokens(gb, "x")).ok)
    }
    {
        var gb : LalrBuilder
        prod(gb, "S", "x")
        prod(gb, "S", "Empty")
        let tb <- build_lalr(gb, rule_id(gb, "S"))
        t |> equal(tb.err, "rule 'Empty' derives no terminal string")
    }
    {
        var gb : LalrBuilder
        prod(gb, "S", "x")
        prod(gb, "Dead", "Dead y")
        let tb <- build_lalr(gb, rule_id(gb, "S"))
        t |> equal(tb.err, "")
        t |> success(lr_parse(tb, tokens(gb, "x")).ok)
    }
    {
        var gb : LalrBuilder
        declare_terms(gb, 2)
        add_production(gb, rule_id(gb, "S"), [term_sym(0), term_sym(2)])
        let tb <- build_lalr(gb, 0)
        t |> equal(tb.err, "production 0 of 'S' uses terminal 2, which is not declared")
        var gb2 : LalrBuilder
        add_production(gb2, rule_id(gb2, "S"), [rule_sym(5)])
        t |> equal(build_lalr(gb2, 0).err, "production 0 of 'S' uses rule 5, which is not declared")
        t |> equal(build_lalr(gb2, 3).err, "root rule 3 is not a declared rule")
    }
}

[test(description = "an epsilon production builds and parses the empty and non-empty sentence")]
def test_epsilon(t : T?) {
    var gb : LalrBuilder
    prod(gb, "L", "")
    prod(gb, "L", "L item")
    let tb <- build_lalr(gb, rule_id(gb, "L"))
    t |> equal(tb.err, "")
    t |> equal(tb.conflicts, 0)
    t |> success(lr_parse(tb, tokens(gb, "")).ok)
    t |> success(lr_parse(tb, tokens(gb, "item item item")).ok)
    let bad <- lr_parse(tb, [-1])
    t |> success(!bad.ok, "a negative token id is refused")
}

[test(description = "lookaheads 951 and 2999 of one item keep apart over 3000 terminals, and a 4096-terminal production ending in a rule parses: the item key packs no field of fixed width")]
def test_wide_grammar(t : T?) {
    {
        var gb : LalrBuilder
        declare_terms(gb, 3000)
        let s = rule_id(gb, "S")
        let a = rule_id(gb, "A")
        add_production(gb, s, [rule_sym(a), term_sym(951)])
        add_production(gb, s, [rule_sym(a), term_sym(2999)])
        add_production(gb, a, [term_sym(10)])
        add_production(gb, a, [term_sym(10), term_sym(11)])
        let tb <- build_lalr(gb, s)
        t |> equal(tb.err, "")
        t |> equal(tb.conflicts, 0)
        t |> equal(tb.nterms, 3001)
        for (k in [951, 2999]) {
            t |> success(lr_parse(tb, [10, k]).ok, "A ::= 10, then {k}")
            t |> success(lr_parse(tb, [10, 11, k]).ok, "A ::= 10 11, then {k}")
        }
        let r <- lr_parse(tb, [10, 1500])
        t |> success(!r.ok)
        t |> equal(r.expected, [11, 951, 2999])
    }
    {
        var gb : LalrBuilder
        declare_terms(gb, 2)
        let s = rule_id(gb, "S")
        let b = rule_id(gb, "B")
        var long_rhs <- [for (_ in range(4096)); term_sym(0)]
        long_rhs |> push(rule_sym(b))
        add_production(gb, s, long_rhs)
        add_production(gb, b, [term_sym(1)])
        let tb <- build_lalr(gb, s)
        t |> equal(tb.err, "")
        var input <- [for (_ in range(4096)); 0]
        input |> push(1)
        let r <- lr_parse(tb, input)
        t |> success(r.ok, r.err)
    }
}

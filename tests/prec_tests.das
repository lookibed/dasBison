options gen2
options indenting = 4

require dastest/testing_boost public
require bison/lalr
require bison/prec
require daslib/strings_boost

// `lhs ::= words`: a word starting with an upper-case letter is a rule, any other a terminal;
// returns the production's index in the builder
def private prod(var gb : LalrBuilder; lhs : string; text : string) : int {
    var rhs : array<int>
    for (w in split(text, " ")) {
        continue if (empty(w))
        let c = first_character(w)
        rhs |> push(c >= 'A' && c <= 'Z' ? rule_sym(rule_id(gb, w)) : term_sym(term_id(gb, w)))
    }
    add_production(gb, rule_id(gb, lhs), rhs)
    return length(gb.prods) - 1
}

def private terms(var gb : LalrBuilder; names : array<string>) : array<int> =>
    <- [for (n in names); term_id(gb, n)]

// a word that is a declared terminal is that terminal, any other is `num`
def private tokens(gb : LalrBuilder; text : string) : array<int> =>
    <- [for (w in split(text, " ")); gb.term_index?[w] ?? (gb.term_index?["num"] ?? -1); where !empty(w)]

// `E ::= E op E` per operator, `( E )` and `num`
def private arith(ops : array<string>) : LalrBuilder {
    var gb : LalrBuilder
    for (op in ops) {
        prod(gb, "E", "E {op} E")
    }
    prod(gb, "E", "( E )")
    prod(gb, "E", "num")
    return <- gb
}

def private expand(tb : LalrTables; words : array<string>; reductions : array<int>; var ri : int&;
                   var wi : int&) : string {
    ri--
    let rhs & = unsafe(tb.prods[reductions[ri]].rhs)
    var parts : array<string>
    parts |> resize(length(rhs))
    for (k in range(length(rhs))) {
        let i = length(rhs) - 1 - k
        if (rhs[i] < 0) {
            parts[i] = expand(tb, words, reductions, ri, wi)
        } else {
            wi--
            parts[i] = words[wi]
        }
    }
    if (length(parts) == 1) {
        return parts[0]
    } elif (length(parts) == 2) {
        return "{parts[0]}{parts[1]}"
    } elif (parts[0] == "(") {
        return parts[1]
    }
    return "{parts[1]}({parts[0]}, {parts[2]})"
}

// the parse of `text` in prefix form, read from `lr_parse`'s reductions backwards as a rightmost
// derivation; "error" when the parse fails
def private parse_tree(tb : LalrTables; gb : LalrBuilder; text : string) : string {
    let r <- lr_parse(tb, tokens(gb, text))
    return "error" if (!r.ok)
    let words <- [for (w in split(text, " ")); w; where !empty(w)]
    var ri = length(r.reductions)
    var wi = length(words)
    return expand(tb, words, r.reductions, ri, wi)
}

[test(description = "%left on + and * resolves the four shift/reduce cells of the ambiguous expression grammar into a copy: * binds tighter, + associates left")]
def test_left(t : T?) {
    var gb <- arith(["+", "*"])
    let e = rule_id(gb, "E")
    let tb <- build_lalr(gb, e)
    t |> equal(tb.conflicts, 4)
    prec_left(gb, terms(gb, ["+"]))
    prec_left(gb, terms(gb, ["*"]))
    let res <- resolve_precedence(tb, gb)
    t |> equal(res.report.by_precedence, 4)
    t |> equal(res.report.by_default, 0)
    t |> equal(res.report.nonassoc_errors, 0)
    t |> equal(length(res.report.cells), 4)
    t |> equal(res.tables.conflicts, 0)
    t |> equal(length(res.tables.alt), 0)
    t |> equal(res.tables.first_conflict, "")
    t |> equal(tb.conflicts, 4)
    t |> equal(length(tb.alt), 4)
    t |> equal(parse_tree(res.tables, gb, "1 + 2 * 3"), "+(1, *(2, 3))")
    t |> equal(parse_tree(res.tables, gb, "1 * 2 + 3"), "+(*(1, 2), 3)")
    t |> equal(parse_tree(res.tables, gb, "1 + 2 + 3"), "+(+(1, 2), 3)")
    t |> equal(parse_tree(res.tables, gb, "( 1 + 2 ) * 3"), "*(+(1, 2), 3)")
    t |> equal(parse_tree(tb, gb, "1 * 2 + 3"), "*(1, +(2, 3))")
    {
        var gb2 <- arith(["+", "*"])
        prec_left(gb2, terms(gb2, ["*"]))
        prec_left(gb2, terms(gb2, ["+"]))
        let res2 <- resolve_precedence(build_lalr(gb2, e), gb2)
        t |> equal(parse_tree(res2.tables, gb2, "1 + 2 * 3"), "*(+(1, 2), 3)")
    }
}

[test(description = "one %left level shared by + and - makes 1 - 2 - 3 and 1 - 2 + 3 reduce left to right")]
def test_left_same_level(t : T?) {
    var gb <- arith(["+", "-", "*"])
    prec_left(gb, terms(gb, ["+", "-"]))
    prec_left(gb, terms(gb, ["*"]))
    let tb <- build_lalr(gb, rule_id(gb, "E"))
    t |> equal(tb.conflicts, 9)
    let res <- resolve_precedence(tb, gb)
    t |> equal(res.report.by_precedence, 9)
    t |> equal(res.tables.conflicts, 0)
    t |> equal(parse_tree(res.tables, gb, "1 - 2 - 3"), "-(-(1, 2), 3)")
    t |> equal(parse_tree(res.tables, gb, "1 - 2 + 3"), "+(-(1, 2), 3)")
    t |> equal(parse_tree(res.tables, gb, "1 - 2 * 3 - 4"), "-(-(1, *(2, 3)), 4)")
    let r <- lr_parse(res.tables, tokens(gb, "1 - 2 - 3"))
    let ops <- [for (p in r.reductions); describe_prod(res.tables, p); where length(res.tables.prods[p].rhs) == 3]
    t |> equal(ops, ["E ::= E - E", "E ::= E - E"])
    t |> equal(r.reductions[2], 2)
}

[test(description = "%right makes 2 ^ 3 ^ 4 group to the right and still binds tighter than a lower %left")]
def test_right(t : T?) {
    var gb <- arith(["+", "^"])
    prec_left(gb, terms(gb, ["+"]))
    prec_right(gb, terms(gb, ["^"]))
    let res <- resolve_precedence(build_lalr(gb, rule_id(gb, "E")), gb)
    t |> equal(res.report.by_precedence, 4)
    t |> equal(res.tables.conflicts, 0)
    t |> equal(parse_tree(res.tables, gb, "2 ^ 3 ^ 4"), "^(2, ^(3, 4))")
    t |> equal(parse_tree(res.tables, gb, "1 + 2 ^ 3 + 4"), "+(+(1, ^(2, 3)), 4)")
}

[test(description = "%nonassoc < turns its tie into an error cell: a < b parses, a < b < c is refused at the second < with < not expected")]
def test_nonassoc(t : T?) {
    var gb <- arith(["<", "+"])
    prec_nonassoc(gb, terms(gb, ["<"]))
    prec_left(gb, terms(gb, ["+"]))
    let tb <- build_lalr(gb, rule_id(gb, "E"))
    t |> equal(tb.conflicts, 4)
    let res <- resolve_precedence(tb, gb)
    t |> equal(res.report.nonassoc_errors, 1)
    t |> equal(res.report.by_precedence, 3)
    t |> equal(res.report.by_default, 0)
    t |> equal(res.tables.conflicts, 0)
    t |> equal(length(res.tables.alt), 0)
    for (c in res.report.cells) {
        if (c.how == PrecHow.nonassoc) {
            t |> equal(c.term, term_id(gb, "<"))
            t |> equal(c.chosen, 0)
            t |> equal(length(c.removed), 2)
            t |> equal(res.tables.action[c.state * res.tables.nterms + c.term], 0)
        }
    }
    t |> equal(parse_tree(res.tables, gb, "a < b"), "<(a, b)")
    t |> equal(parse_tree(res.tables, gb, "a < b + c"), "<(a, +(b, c))")
    t |> equal(parse_tree(res.tables, gb, "a + b < c"), "<(+(a, b), c)")
    let r <- lr_parse(res.tables, tokens(gb, "a < b < c"))
    t |> success(!r.ok)
    t |> equal(r.pos, 3)
    t |> equal(r.token, term_id(gb, "<"))
    t |> success(find_index(r.expected, term_id(gb, "<")) < 0, "< is not expected")
    t |> equal(r.expected, [term_id(gb, "+"), res.tables.eof])
}

[test(description = "a %prec override gives unary minus a level above *, so - 1 * 2 is *(-1, 2); without it the minus takes the precedence of -")]
def test_prec_override(t : T?) {
    var gb <- arith(["+", "-", "*"])
    let neg = prod(gb, "E", "- E")
    prec_left(gb, terms(gb, ["+", "-"]))
    prec_left(gb, terms(gb, ["*"]))
    let e = rule_id(gb, "E")
    {
        let res <- resolve_precedence(build_lalr(gb, e), gb)
        t |> equal(res.report.by_default, 0)
        t |> equal(parse_tree(res.tables, gb, "- 1 * 2"), "-*(1, 2)")
    }
    prec_right(gb, terms(gb, ["UMINUS"]))
    prec_of_production(gb, neg, term_id(gb, "UMINUS"))
    let tb <- build_lalr(gb, e)
    let res <- resolve_precedence(tb, gb)
    t |> equal(res.report.by_precedence, tb.conflicts)
    t |> equal(res.report.by_default, 0)
    t |> equal(res.tables.conflicts, 0)
    t |> equal(parse_tree(res.tables, gb, "- 1 * 2"), "*(-1, 2)")
    t |> equal(parse_tree(res.tables, gb, "1 - - 2 - 3"), "-(-(1, -2), 3)")
}

def private dangling_else() : LalrBuilder {
    var gb : LalrBuilder
    prod(gb, "S", "if C then S")
    prod(gb, "S", "if C then S else S")
    prod(gb, "S", "other")
    prod(gb, "C", "cond")
    return <- gb
}

[test(description = "a cell whose production has no precedence stays a conflict: resolved by the default shift, counted and kept in alt")]
def test_unresolved_default_shift(t : T?) {
    var gb <- dangling_else()
    prec_right(gb, terms(gb, ["else"]))
    let tb <- build_lalr(gb, rule_id(gb, "S"))
    let res <- resolve_precedence(tb, gb)
    t |> equal(res.report.by_default, 1)
    t |> equal(res.report.by_precedence, 0)
    t |> equal(res.report.shift_reduce, 1)
    t |> equal(res.report.reduce_reduce, 0)
    t |> equal(res.tables.conflicts, 1)
    t |> equal(length(res.tables.alt), 1)
    t |> success(starts_with(res.tables.first_conflict, "shift/reduce conflict in state"),
                 res.tables.first_conflict)
    let c & = unsafe(res.report.cells[0])
    t |> equal(c.how, PrecHow.by_default)
    t |> success(c.chosen > 0, "the shift wins")
    t |> equal(length(c.kept), 1)
    t |> equal(describe_action(tb, c.kept[0]), "reduce S ::= if C then S")
    let r <- lr_parse(res.tables, tokens(gb, "if cond then if cond then other else other"))
    t |> success(r.ok)
}

[test(description = "%nonassoc then below %nonassoc else settles the dangling else by precedence: the shift, no conflict left")]
def test_dangling_else_declared(t : T?) {
    var gb <- dangling_else()
    prec_nonassoc(gb, terms(gb, ["then"]))
    prec_nonassoc(gb, terms(gb, ["else"]))
    let res <- resolve_precedence(build_lalr(gb, rule_id(gb, "S")), gb)
    t |> equal(res.report.by_precedence, 1)
    t |> equal(res.report.by_default, 0)
    t |> equal(res.tables.conflicts, 0)
    let r <- lr_parse(res.tables, tokens(gb, "if cond then if cond then other else other"))
    t |> success(r.ok)
    let ifs <- [for (p in r.reductions); length(res.tables.prods[p].rhs); where length(res.tables.prods[p].rhs) > 1]
    t |> equal(ifs, [6, 4])
}

[test(description = "a reduce/reduce cell ignores precedence and keeps the production that comes first in the grammar, reported as default")]
def test_reduce_reduce(t : T?) {
    for (order in [["A", "B"], ["B", "A"]]) {
        var gb : LalrBuilder
        prod(gb, "S", "A")
        prod(gb, "S", "B")
        let first = prod(gb, order[0], "x")
        let second = prod(gb, order[1], "x")
        prec_left(gb, terms(gb, ["lo"]))
        prec_left(gb, terms(gb, ["hi"]))
        prec_of_production(gb, first, term_id(gb, "lo"))
        prec_of_production(gb, second, term_id(gb, "hi"))
        let tb <- build_lalr(gb, rule_id(gb, "S"))
        t |> equal(tb.conflicts, 1)
        let res <- resolve_precedence(tb, gb)
        t |> equal(res.report.by_default, 1)
        t |> equal(res.report.reduce_reduce, 1)
        t |> equal(res.report.shift_reduce, 0)
        t |> equal(res.tables.conflicts, 1)
        t |> success(starts_with(res.tables.first_conflict, "reduce/reduce conflict"),
                     res.tables.first_conflict)
        t |> equal(describe_action(tb, res.report.cells[0].chosen), "reduce {order[0]} ::= x")
        let r <- lr_parse(res.tables, tokens(gb, "x"))
        t |> success(r.ok)
        t |> equal(describe_prod(tb, r.reductions[0]), "{order[0]} ::= x")
    }
}

[test(description = "tables with no conflict come back equal and the report is empty")]
def test_no_conflicts(t : T?) {
    var gb : LalrBuilder
    prod(gb, "E", "E + T")
    prod(gb, "E", "T")
    prod(gb, "T", "id")
    prec_left(gb, terms(gb, ["+"]))
    let tb <- build_lalr(gb, rule_id(gb, "E"))
    let res <- resolve_precedence(tb, gb)
    t |> equal(length(res.report.cells), 0)
    t |> equal(res.tables.action, tb.action)
    t |> equal(res.tables.conflicts, 0)
}

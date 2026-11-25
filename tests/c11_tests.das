options gen2
options indenting = 4

require dastest/testing_boost public
require bison/bytes
require bison/prec
require daslib/strings_boost
require daslib/fio
require daslib/module_path
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
    let res <- resolve_precedence(g.tables, LalrBuilder())
    t |> equal(res.report.by_default, 2)
    t |> equal(res.report.by_precedence, 0)
}

[test(description = "the C11 grammar with one integer terminal per token builds to the same 479 states and the same two conflicts, which resolve_precedence reports as two default shifts and the driver still parses through", timeout = 1200)]
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
    let res <- resolve_precedence(tb, lb)
    t |> equal(res.report.by_default, 2)
    t |> equal(res.report.by_precedence, 0)
    t |> equal(res.report.nonassoc_errors, 0)
    t |> equal(res.report.shift_reduce, 2)
    t |> equal(res.report.reduce_reduce, 0)
    t |> equal(res.tables.conflicts, 2)
    t |> equal(tb.conflicts, 2)
    let text = ("State 38 conflicts: 1 shift/reduce\n" +
        "    '('  shift, and go to state 62\n" +
        "    '('  [reduce using rule 161 (type_qualifier ::= ATOMIC)]\n" +
        "State 443 conflicts: 1 shift/reduce\n" +
        "    ELSE  shift, and go to state 463\n" +
        "    ELSE  [reduce using rule 254 (selection_statement ::= IF '(' expression ')' statement)]\n")
    t |> equal(format_report(res.report), text)
    let words = "INT IDENTIFIER '(' ')' '\{' IF '(' IDENTIFIER ')' IF '(' IDENTIFIER ')' ';' ELSE ';' '\}'"
    let toks <- [for (w in split(words, " ")); lb.term_index?[w] ?? -1]
    let r <- lr_parse(res.tables, toks)
    t |> success(r.ok, r.err)
    let ifs <- [for (p in r.reductions); describe_prod(res.tables, p);
                where starts_with(describe_prod(res.tables, p), "selection_statement ::= IF")]
    t |> equal(ifs, ["selection_statement ::= IF '(' expression ')' statement ELSE statement",
                     "selection_statement ::= IF '(' expression ')' statement"])
    t |> success(
                 !lr_parse(res.tables,
                           [for (w in split("INT ';' ELSE", " ")); lb.term_index?[w] ?? -1]).ok)
}

// the `rule("lhs", "rhs")` calls of the [bison] C11 example as `lhs ::= rhs`, in source order,
// the braces the string literals escape read as braces
def private example_rules() : array<string> {
    let src = fread(path_join(get_this_module_dir(), "../examples/c11/c11_parser.das"))
    var out : array<string>
    for (line in split(src, "\n")) {
        let at = find(line, "    rule(\"")
        continue if (at != 0)
        var inscope parts <- split(slice(line, 10), "\"")
        out |> push(replace(replace("{parts[0]} ::= {parts[2]}", "\\\{", "\{"), "\\\}", "\}"))
    }
    return <- out
}

[test(description = "the C11 grammar of these tests and the [bison] C11 example are one grammar: the same productions, as lhs ::= rhs, in the same order", timeout = 1200)]
def test_c11_one_grammar(t : T?) {
    var gb : GrammarBuilder
    build_c11(gb)
    let lb <- c11_int_builder(t, gb)
    var inscope ours <- [for (p in lb.prods); build_string() $(var w) {
            w |> write("{lb.rule_names[p.lhs]} ::=")
            for (s in p.rhs) {
                w |> write(" ")
                w |> write(s < 0 ? lb.rule_names[-1 - s] : lb.term_names[s])
            }
        }]
    var inscope theirs <- example_rules()
    t |> equal(length(theirs), 274)
    t |> equal(ours, theirs)
}

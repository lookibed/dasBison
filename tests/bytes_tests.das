options gen2
options indenting = 4

require dastest/testing_boost public
require bison/bytes
require daslib/strings_boost

def private range_set(lo, hi : int) : ByteSet {
    var bs : ByteSet
    for (b in range(lo, hi + 1)) {
        bs[b] = true
    }
    return bs
}

def private number_list() : tuple<gb : GrammarBuilder; root : int> {
    var gb : GrammarBuilder
    let list = rule_id(gb, "list")
    let num = rule_id(gb, "num")
    add_production(gb, list, [sym_rule(num)])
    add_production(gb, list, [sym_rule(list), sym_byte(','), sym_rule(num)])
    add_production(gb, num, [sym_bytes(range_set('0', '9'))])
    add_production(gb, num, [sym_rule(num), sym_bytes(range_set('0', '9'))])
    return <- (gb <- gb, root = list)
}

[test(description = "a comma-separated number list partitions into three byte classes and parses through the core")]
def test_number_list(t : T?) {
    let built <- number_list()
    let g <- build_grammar(built.gb, built.root)
    t |> equal(g.tables.err, "")
    t |> equal(g.nclasses, 3)
    t |> equal(g.tables.nterms, 4)
    t |> equal(g.tables.conflicts, 0)
    t |> equal(g.byte_class['0'], g.byte_class['9'])
    t |> success(g.byte_class['0'] != g.byte_class[','])
    t |> success(g.byte_class['a'] != g.byte_class[','] && g.byte_class['a'] != g.byte_class['5'])
    t |> equal(g.tables.term_names[g.byte_class[',']], "','")
    for (s in ["7", "12,3", "0,00,123"]) {
        t |> success(lr_parse_bytes(g, s).ok, s)
    }
    let r <- lr_parse_bytes(g, "12,,3")
    t |> success(!r.ok)
    t |> equal(r.pos, 3)
    t |> equal(r.expected, [g.byte_class['0']])
    let at_end <- lr_parse_bytes(g, "12,")
    t |> success(!at_end.ok)
    t |> equal(at_end.token, g.tables.eof)
    let junk <- lr_parse_bytes(g, "1a")
    t |> success(!junk.ok)
    t |> equal(junk.pos, 1)
}

[test(description = "a byte set spanning several classes becomes a set rule with one production per class")]
def test_set_rule(t : T?) {
    var gb : GrammarBuilder
    let s = rule_id(gb, "s")
    add_production(gb, s, [sym_bytes(range_set('a', 'c')), sym_byte('x')])
    add_production(gb, s, [sym_byte('b'), sym_byte('y')])
    let g <- build_grammar(gb, s)
    t |> equal(g.tables.err, "")
    t |> equal(g.nclasses, 5)
    t |> equal(g.byte_class['a'], g.byte_class['c'])
    let sets <- [for (n in g.tables.rule_names); n; where starts_with(n, "<set")]
    t |> equal(length(sets), 1)
    var set_prods = 0
    for (p in g.tables.prods) {
        set_prods += g.tables.rule_names[p.lhs] == sets[0] ? 1 : 0
    }
    t |> equal(set_prods, 2)
    for (w in ["ax", "bx", "cx", "by"]) {
        t |> success(lr_parse_bytes(g, w).ok, w)
    }
    for (w in ["ay", "cy", "b", "xb"]) {
        t |> success(!lr_parse_bytes(g, w).ok, w)
    }
}

[test(description = "an empty byte set is a rule with no production and fails the build; the error names the first unproductive rule by id, as dasLR1 does")]
def test_byte_errors(t : T?) {
    let empty_set : ByteSet
    var gb : GrammarBuilder
    let s = rule_id(gb, "s")
    add_production(gb, s, [sym_byte('a'), sym_bytes(empty_set)])
    let g <- build_grammar(gb, s)
    t |> equal(g.tables.err, "rule 's' derives no terminal string")
    let sets <- [for (n in g.tables.rule_names); n; where starts_with(n, "<set")]
    t |> equal(length(sets), 1, "the empty set is a rule of its own")
    var gb2 : GrammarBuilder
    let s2 = rule_id(gb2, "s")
    let loop = rule_id(gb2, "loop")
    add_production(gb2, s2, [sym_rule(loop)])
    add_production(gb2, loop, [sym_byte('a'), sym_rule(loop)])
    t |> equal(build_grammar(gb2, s2).tables.err, "rule 's' derives no terminal string")
}

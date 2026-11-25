# dasBison

A parser generator for [daslang](https://daslang.io/): LALR(1) tables built at run time over
integer terminal ids, a byte-class front end over the same core, and a deterministic driver.

```das
options gen2
require bison/lalr

[export]
def main() {
    var gb : LalrBuilder
    let plus = term_id(gb, "+")
    let id = term_id(gb, "id")
    let e = rule_id(gb, "E")
    add_production(gb, e, [rule_sym(e), term_sym(plus), term_sym(id)])
    add_production(gb, e, [term_sym(id)])
    let tables <- build_lalr(gb, e)
    print("{tables.nstates} states, {tables.conflicts} conflicts\n")
    let r <- lr_parse(tables, [id, plus, plus])
    if (!r.ok) {
        print("{r.err} at token {r.pos}, expected {r.expected}\n")
    }
}
```

- Terminals are `0 .. n-1`, declared by name (`term_id`) or by count (`declare_terms`); the end
  of input is the next id (`tables.eof`). Rules are named (`rule_id`); a right-hand side mixes
  `term_sym(t)` and `rule_sym(r)`; an empty one is an epsilon production.
- `tables.action[state * nterms + term]`: 0 error, `1 + s` shift, `-(1 + p)` reduce by
  `tables.prods[p]`, `LALR_ACCEPT`. `tables.goto_nt[state * nrules + rule]`.
- A conflicting cell keeps all its actions: the first in `action`, the rest in `alt[cell]`;
  `conflicts`, `first_conflict` and `describe_conflicts(tables)` report them. The core resolves
  nothing; `bison/prec` does (below).
- `tables.err` names a grammar that cannot build: an undeclared symbol, or a reachable rule that
  derives no terminal string.
- `lr_parse(tables, tokens)` runs one stack (the first action of a conflicting cell) and returns
  the reductions, or the position, state, refused terminal and the exact expected set.

Precedence and associativity go through `bison/prec`, over a built table, as yacc applies them:

```das
options gen2
require bison/lalr
require bison/prec

[export]
def main() {
    var gb : LalrBuilder
    let plus = term_id(gb, "+")
    let star = term_id(gb, "*")
    let num = term_id(gb, "num")
    let e = rule_id(gb, "E")
    add_production(gb, e, [rule_sym(e), term_sym(plus), rule_sym(e)])
    add_production(gb, e, [rule_sym(e), term_sym(star), rule_sym(e)])
    add_production(gb, e, [term_sym(num)])
    prec_left(gb, [plus])           // %left '+'
    prec_left(gb, [star])           // %left '*' - a later line binds tighter
    let tables <- build_lalr(gb, e) // 4 shift/reduce conflicts, all kept
    let res <- resolve_precedence(tables, gb)
    print("{res.report.by_precedence} resolved, {res.tables.conflicts} left\n")
    print(format_report(res.report)) // the unresolved cells, as bison -v lists them
    let r <- lr_parse(res.tables, [num, plus, num, star, num])
}
```

- `prec_left` / `prec_right` / `prec_nonassoc(gb, terms)`: each call is the next level up.
  `prec_of_production(gb, prod, term)` is `%prec term` for production `prod` (its index in
  `gb.prods`). A production otherwise takes its last terminal's level.
- `resolve_precedence(tables, gb)` returns `PrecResult`: `tables`, a resolved copy (the input is
  not changed), and `report`: `by_precedence`, `by_default`, `nonassoc_errors`, bison's
  `shift_reduce` / `reduce_reduce` counts, and one `PrecCell` per conflicting cell. A cell nothing
  declared for is resolved yacc's default way (shift, else the earliest production), stays in
  `conflicts` and `alt`, and is listed by `format_report`; a `%nonassoc` tie is an error cell.

Byte grammars - terminals as byte sets - go through `bison/bytes`: `GrammarBuilder`, `sym_byte`,
`sym_bytes`, `sym_rule`, `build_grammar(gb, root) : Grammar` with `byte_class`, `nclasses` and
the core's `tables`; `lr_parse_bytes(g, "text")` parses a string.

Install: `daspkg install github.com/lookibed/dasBison`, then `require bison/lalr` or
`require bison/bytes`. Run the tests from a daslang checkout:
`daslang -load_module <dasBison> dastest/dastest.das -- --test <dasBison>/tests`. Design and the
rules a change must keep: `ARCHITECTURE.md`, `REVIEW.md`.

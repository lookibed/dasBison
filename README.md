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
  `conflicts`, `first_conflict` and `describe_conflicts(tables)` report them. Nothing is resolved.
- `tables.err` names a grammar that cannot build: an undeclared symbol, or a reachable rule that
  derives no terminal string.
- `lr_parse(tables, tokens)` runs one stack (the first action of a conflicting cell) and returns
  the reductions, or the position, state, refused terminal and the exact expected set.

Byte grammars - terminals as byte sets - go through `bison/bytes`: `GrammarBuilder`, `sym_byte`,
`sym_bytes`, `sym_rule`, `build_grammar(gb, root) : Grammar` with `byte_class`, `nclasses` and
the core's `tables`; `lr_parse_bytes(g, "text")` parses a string.

Install: `daspkg install github.com/lookibed/dasBison`, then `require bison/lalr` or
`require bison/bytes`. Run the tests from a daslang checkout:
`daslang -load_module <dasBison> dastest/dastest.das -- --test <dasBison>/tests`. Design and the
rules a change must keep: `ARCHITECTURE.md`, `REVIEW.md`.

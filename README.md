# dasBison

A parser generator for [daslang](https://daslang.io/): LALR(1) tables over integer terminal ids, a
byte-class front end over the same core, a deterministic driver, and a `[bison]` macro that builds
the tables when the module compiles and turns a function into a typed parser over a
[dasFlex](https://github.com/lookibed/dasFlex) lexer.

```das
options gen2
require flex/flex_macro
require bison/bison_macro
require strings

enum CTok {
    NUM = 256           // punctuators need no member: the lexer emits their byte
}

[flex]
def calc_lex(var lx : FlexLexer) : bool {
    rule("[0-9]+(\\.[0-9]+)?") {
        lx |> emit(CTok.NUM)
    }
    rule("[\\-+*/()]") {
        lx |> emit(first_character(text(lx)))
    }
    rule("[ \\t\\r\\n]+") {
    }
}

[bison(tokens = CTok, lexer = calc_lex)]
def calc(var p : Parser) : float {
    prec_left("+", "-")                 // yacc order: a later line binds tighter
    prec_left("*", "/")
    rule("expr", "expr '+' expr") <| $(a : float; b : float) : float {
        return a + b
    }
    rule("expr", "expr '-' expr") <| $(a, b : float) => a - b
    rule("expr", "expr '*' expr") <| $(a, b : float) => a * b
    rule("expr", "expr '/' expr") <| $(a, b : float) => a / b
    rule("expr", "'(' expr ')'") <| $(e : float) => e
    rule("expr", "NUM") <| $(t : FlexToken) => to_float(text(p.lexer, t))
    root("expr")
}

[export]
def main() {
    var p : Parser
    parser_open(p, "(1 + 2) * 3", "input.txt")
    let v = calc(p)                     // 9
    if (p.failed) {
        print("{p.err}\n")              // input.txt:1:4: unexpected ..., expected one of: ...
    }
}
```

- A right-hand side is text: a rule's name, a member of the `tokens` enum (its value is the kind),
  a quoted character (the token whose kind is that byte), `""` for epsilon, a trailing `%prec NAME`.
  `prec_left` / `prec_right` / `prec_nonassoc` take token names or characters; `root` defaults to
  the first rule.
- The action's arguments are the values of the symbols that carry one, in order - rules that yield,
  and named tokens as their `FlexToken` (`text(p.lexer, t)` is its text) - or none at all. A rule's
  type is what its actions return; a rule with no action passes its one value on; a rule whose
  actions return nothing yields no value. The root's value is the function's result.
- A conflict precedence leaves to yacc's default is a compile warning in `bison -v` words, unless
  `[bison(expected = N)]` (yacc's `%expect`) names the shift/reduce count.
- A refused token sets `p.failed`, `p.line`, `p.col` and `p.err`
  (`file:line:col: unexpected TOKEN, expected one of: a, b, c`) and the function returns the default
  value. Walk-through: `tutorials/01_calculator.das`.

The calculator as yacc-like text, with a unary minus - `%bison~` at module level writes a `[bison]`
function like the one above:

```das
%bison~ calc : float, tokens = CTok, lexer = calc_lex
%left '+' '-'
%left '*' '/'
%right UMINUS
%expect 0
%rules
expr : expr '+' expr          { $$ = $1 + $3 }
     | expr '-' expr          { $$ = $1 - $3 }
     | expr '*' expr          { $$ = $1 * $3 }
     | expr '/' expr          { $$ = $1 / $3 }
     | '-' expr %prec UMINUS  { $$ = -$2 }
     | '(' expr ')'           { $$ = $2 }
     | NUM                    { $$ = to_float(text(p.lexer, $1)) }
     ;
%%
```

- The header names the parser, its result type, the token enum and the lexer. Before `%rules`:
  `%left` / `%right` / `%nonassoc`, `%expect N`, `%start NAME` (else the first rule is the root),
  `%type <Type> names`. The text ends at `%%`.
- `$n` is the n-th symbol of the right-hand side, quoted characters counted; reading one that
  carries no value is a compile error. `$$ = value` returns the rule's value. The root's type is the
  header's; another rule an action reads by `$n` needs `%type`.
- The reader's errors, `[bison]`'s errors at a rule and daslang's inside an action point at the line
  of the text. Walk-through: `tutorials/02_bison_reader.das`.

The core runs without the macro:

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

Install: `daspkg install github.com/lookibed/dasBison` (it brings dasFlex), then
`require bison/bison_macro`, `require bison/lalr` or `require bison/bytes`. Run the tests from a
daslang checkout:
`daslang -load_module <dasBison> -load_module <dasFlex> dastest/dastest.das -- --test <dasBison>/tests`. Design and the
rules a change must keep: `ARCHITECTURE.md`, `REVIEW.md`.

The C11 example (`examples/c11`, and `tests/c11_showcase_tests.das` through it) requires dasFlex's C
lexer by a relative path, `../../../dasFlex/examples/c_lexer/c_lexer.das`: it assumes a dasFlex
checkout beside the dasBison one (`<dir>/dasBison`, `<dir>/dasFlex`).

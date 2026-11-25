options gen2
options indenting = 4

require dastest/testing_boost public
require bison/bison_macro
require bison/grammar_text
require bison/lalr
require bison/prec
require flex/flex_macro
require strings

enum CTok {
    NUM = 256
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
    prec_left("+", "-")
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

// the value, or on a failure the error text after the default value the parser returned
def private run_calc(src : string) : string {
    var p : Parser
    parser_open(p, src, "calc.txt")
    let v = calc(p)
    return p.failed ? "{v} {p.err}" : "{v}"
}

[test(description = "the [bison] calculator evaluates by its %left lines: * binds tighter than +, - associates left, parentheses group")]
def test_calc(t : T?) {
    t |> equal(run_calc("1+2*3"), "7")
    t |> equal(run_calc("(1+2)*3"), "9")
    t |> equal(run_calc("2-3-4"), "-5")
    t |> equal(run_calc("8/2/2"), "2")
    t |> equal(run_calc(" 1.5 * (2 + 2) "), "6")
}

[test(description = "a refused token gives file:line:col, its name and the exact expected set; the end of input and a lexer error report the same way, with the default value")]
def test_calc_errors(t : T?) {
    t |> equal(run_calc("1+"), "0 calc.txt:1:3: unexpected end of input, expected one of: '(', NUM")
    t |> equal(run_calc("1 2"), "0 calc.txt:1:3: unexpected NUM, expected one of: '+', '-', '*', '/', end of input")
    t |> equal(run_calc("2*(3\n+)"), "0 calc.txt:2:2: unexpected ')', expected one of: '(', NUM")
    t |> equal(run_calc("1 + x"), "0 calc.txt:1:5: unexpected 'x'")
    var p : Parser
    parser_open(p, "(1", "")
    calc(p)
    t |> success(p.failed)
    t |> equal(p.err, "1:3: unexpected end of input, expected one of: '+', '-', '*', '/', ')'")
    t |> equal(p.line, 1)
    t |> equal(p.col, 3)
}

enum ITok {
    IF = 1
    ELSE = 2
    X = 3
}

[flex]
def if_lex(var lx : FlexLexer) : bool {
    rule("if") {
        lx |> emit(ITok.IF)
    }
    rule("else") {
        lx |> emit(ITok.ELSE)
    }
    rule("x") {
        lx |> emit(ITok.X)
    }
    rule(" +") {
    }
}

// the dangling else: one shift/reduce conflict, declared with `expected = 1` and resolved by
// yacc's default shift, so the else binds to the inner if
[bison(tokens = ITok, lexer = if_lex, expected = 1)]
def ifs(var p : Parser) : string {
    rule("stmt", "IF stmt") <| $(i : FlexToken; s : string) => "if({s})"
    rule("stmt", "IF stmt ELSE stmt") <| $(i : FlexToken; a : string; e : FlexToken; b : string) => "if({a}, {b})"
    rule("stmt", "X") <| $() => "x"
}

def private dangling_else() : TextGrammar {
    let rules <- [TextRule(lhs = "stmt", rhs = "IF stmt"), TextRule(lhs = "stmt", rhs = "IF stmt ELSE stmt"),
                  TextRule(lhs = "stmt", rhs = "X")]
    let precs : array<TextPrec>
    let tokens <- { "IF" => 1, "ELSE" => 2, "X" => 3 }
    return <- grammar_from_text(rules, precs, "", tokens)
}

[test(description = "the dangling else through [bison] shifts by default, binding else to the inner if; the warning the macro gives names the conflict as bison -v does, and expected = 1 silences exactly it")]
def test_dangling_else(t : T?) {
    var p : Parser
    parser_open(p, "if if x else x")
    t |> equal(ifs(p), "if(if(x, x))")
    parser_open(p, "if x else if x else x")
    t |> equal(ifs(p), "if(x, if(x, x))")
    let g <- dangling_else()
    t |> equal(g.err, "")
    let res <- resolve_precedence(build_lalr(g.builder, g.root), g.builder)
    t |> equal(res.report.shift_reduce, 1)
    let warning = "[bison] ifs: 1 shift/reduce, 0 reduce/reduce conflicts, resolved by default:\nState 4 conflicts: 1 shift/reduce\n    ELSE  shift, and go to state 5\n    ELSE  [reduce using rule 1 (stmt ::= IF stmt)]\n"
    t |> equal(conflict_warning("ifs", res.report, -1), warning)
    t |> equal(conflict_warning("ifs", res.report, 1), "")
    t |> equal(conflict_warning("ifs", res.report, 0), replace(warning, "conflicts, resolved", "conflicts (expected = 0), resolved"))
}

[test(description = "a right-hand side reads names, quoted characters with escapes and a trailing %prec, and names what is wrong with a bad one")]
def test_rhs_text(t : T?) {
    let r <- parse_rhs("expr '+' expr %prec UMINUS")
    t |> equal(length(r.syms), 3)
    t |> equal(r.syms[1].name, "'+'")
    t |> equal(r.syms[1].ch, '+')
    t |> equal(r.syms[0].ch, -1)
    t |> equal(r.prec, "UMINUS")
    t |> equal(parse_rhs("'\\'' '\\\\'").syms[0].ch, '\'')
    t |> equal(parse_rhs("'\\'' '\\\\'").syms[1].ch, '\\')
    t |> equal(length(parse_rhs("").syms), 0)
    t |> equal(parse_rhs("a 'bc'").err, "a quoted character is one character between single quotes, at offset 2")
    t |> equal(parse_rhs("a %prec").err, "%prec needs a token name")
    t |> equal(parse_rhs("a %prec X b").err, "'b' after %prec X: %prec ends the right-hand side")
    t |> equal(parse_rhs("a + b").err, "unexpected '+' at offset 2: a symbol is a name or a quoted character")
}

[test(description = "a text grammar resolves names to rules, tokens and quoted bytes, keys terminals by kind, and refuses an unknown name, a kind two names share, and a root that is no rule")]
def test_text_grammar(t : T?) {
    let tokens <- { "NUM" => 256, "PLUS" => '+' }
    let precs : array<TextPrec>
    let ok <- grammar_from_text([TextRule(lhs = "e", rhs = "e '-' NUM"), TextRule(lhs = "e", rhs = "NUM")], precs, "", tokens)
    t |> equal(ok.err, "")
    t |> equal(ok.kinds, ['-', 256])
    t |> equal(ok.root, 0)
    let unknown <- grammar_from_text([TextRule(lhs = "e", rhs = "e NAME")], precs, "", tokens)
    t |> equal(unknown.err, "'NAME' is neither a rule nor a token")
    t |> equal(unknown.err_rule, 0)
    let same_kind <- grammar_from_text([TextRule(lhs = "e", rhs = "NUM"), TextRule(lhs = "e", rhs = "e PLUS '+'")], precs, "", tokens)
    t |> equal(same_kind.err, "'+' and PLUS are the same token kind 43")
    t |> equal(same_kind.err_rule, 1)
    let no_root <- grammar_from_text([TextRule(lhs = "e", rhs = "NUM")], precs, "f", tokens)
    t |> equal(no_root.err, "root 'f' is not a rule")
    let uminus <- grammar_from_text([TextRule(lhs = "e", rhs = "'-' e %prec UMINUS"), TextRule(lhs = "e", rhs = "NUM")],
                                    [TextPrec(assoc = PrecAssoc.left, names <- ["-"]), TextPrec(assoc = PrecAssoc.right, names <- ["UMINUS"])],
                                    "", tokens)
    t |> equal(uminus.err, "")
    t |> equal(uminus.builder.prec_prods[0], uminus.builder.term_index?["UMINUS"] ?? -2)
    t |> equal(uminus.kinds[uminus.builder.term_index?["UMINUS"] ?? 0], -1)
}

var private g_seen : array<string>

enum LTok {
    WORD = 1
}

[flex]
def list_lex(var lx : FlexLexer) : bool {
    rule("[a-z]+") {
        lx |> emit(LTok.WORD)
    }
    rule("[;]") {
        lx |> emit(';')
    }
    rule(" +") {
    }
}

// `items` yields no value: its actions return nothing and run for their effect, and the root's
// action takes no value from it
[bison(tokens = LTok, lexer = list_lex)]
def words(var p : Parser) : int {
    rule("doc", "items ';'") <| $() => length(g_seen)
    rule("items", "items WORD") <| $(w : FlexToken) {
        g_seen |> push(text(p.lexer, w))
    }
    rule("items", "")
}

[test(description = "a rule whose actions return nothing yields no value: it carries nothing on the stack, its actions run in reduce order, and an epsilon production needs no action")]
def test_void_rule(t : T?) {
    g_seen |> clear()
    var p : Parser
    parser_open(p, "a bc d ;")
    t |> equal(words(p), 3)
    t |> equal(g_seen, ["a", "bc", "d"])
}

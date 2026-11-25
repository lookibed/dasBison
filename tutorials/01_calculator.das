// Tutorial dasBison-01: a calculator
//
// This tutorial covers:
//   - a [flex] lexer whose token kinds are an enum and the bytes of punctuation
//   - a [bison] function: rules as right-hand-side strings, an action per rule, the root
//   - precedence lines, and %prec for a unary minus
//   - typed values: a rule's type is what its actions return; a token's value is its FlexToken
//   - the error a refused token produces, with the expected set
//
// Run: daslang -load_module <dasBison> -load_module <dasFlex> tutorials/01_calculator.das

options gen2
options indenting = 4

require flex/flex_macro
require bison/bison_macro
require strings

// The named tokens. A punctuator needs no member: the lexer emits its byte, and the grammar
// writes it quoted ('+'). Kinds the enum gives must not collide with those bytes, so it starts at 256.
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

// The grammar is read when the module compiles: the LALR(1) tables are built then and stored as
// private globals, and the function's body becomes the parser. `tokens` names the enum whose
// members the rules may use, `lexer` the [flex] function the parser pulls tokens from.
//
// Each rule is `rule("lhs", "rhs")` with an action block. The block's arguments are the values of
// the right-hand side's symbols that carry one - rules, and named tokens as their FlexToken - in
// order; quoted characters carry none. The action's result is the rule's value: here every `expr`
// is a float, so the function returns a float.
[bison(tokens = CTok, lexer = calc_lex)]
def calc(var p : Parser) : float {
    // yacc's order: each line binds tighter than the one before it
    prec_left("+", "-")
    prec_left("*", "/")
    prec_right("UMINUS")
    rule("expr", "expr '+' expr") <| $(a, b : float) => a + b
    rule("expr", "expr '-' expr") <| $(a, b : float) => a - b
    rule("expr", "expr '*' expr") <| $(a, b : float) => a * b
    rule("expr", "expr '/' expr") <| $(a, b : float) => a / b
    // UMINUS is no token the lexer emits - it only names a precedence level for %prec
    rule("expr", "'-' expr %prec UMINUS") <| $(e : float) => -e
    rule("expr", "'(' expr ')'") <| $(e : float) => e
    // `p` is the function's parameter: the action reads the token's text from the lexer's input
    rule("expr", "NUM") <| $(t : FlexToken) => to_float(text(p.lexer, t))
    root("expr")
}

[export]
def main() {
    for (src in ["1 + 2 * 3", "(1 + 2) * 3", "2 - 3 - 4", "-2 * -(3 + 1)"]) {
        var p : Parser
        parser_open(p, src)
        print("{src} = {calc(p)}\n")
    }
    // A token the tables refuse stops the parse: `failed` is set, `err` says where, what came and
    // what the parser would have taken there, and the function returns the default value.
    var p : Parser
    parser_open(p, "1 +\n  * 2", "input.txt")
    let v = calc(p)
    print("{v} {p.err}\n")      // 0 input.txt:2:3: unexpected '*', expected one of: '-', '(', NUM
}

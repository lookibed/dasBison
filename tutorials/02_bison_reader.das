// Tutorial dasBison-02: the %bison~ text form
//
// This tutorial covers:
//   - the calculator of tutorial 01 written as yacc-like text instead of rule() calls
//   - the header that names the parser, its result type, the token enum and the lexer
//   - %left / %right / %expect declarations, %prec, and the rules section
//   - $$ and $1..$n in the actions, which are daslang code
//
// Run: daslang -load_module <dasBison> -load_module <dasFlex> tutorials/02_bison_reader.das

options gen2
options indenting = 4

require flex/flex_macro
require bison/bison_macro
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

// `%bison~ name : Type, tokens = Enum, lexer = scan` at module level declares the parser
// `def name(var p : Parser) : Type`, the same function [bison] generates - the reader writes that
// [bison] function and the macro builds it. Before `%rules`: the precedence lines in yacc's order
// (a later line binds tighter), and `%expect N`, the shift/reduce conflicts the grammar is meant to
// have. After it, yacc's rules: `name : symbols { action } | ... ;`. The first rule is the root.
//
// In an action `$n` is the value of the n-th symbol of the right-hand side - a rule's value, or a
// named token's FlexToken - and `$$ = value` returns the rule's value. The root's values are of the
// header's type; quoted characters carry no value, so `$2` of `expr '+' expr` is an error. `p` is
// the parser. The text ends at `%%`.
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

[export]
def main() {
    // The generated function is called exactly like the [bison] one.
    for (src in ["1 + 2 * 3", "(1 + 2) * 3", "2 - 3 - 4", "-2 * -(3 + 1)"]) {
        var p : Parser
        parser_open(p, src)
        print("{src} = {calc(p)}\n")
    }
    var p : Parser
    parser_open(p, "1 +\n  * 2", "input.txt")
    let v = calc(p)
    print("{v} {p.err}\n")      // 0 input.txt:2:3: unexpected '*', expected one of: '-', '(', NUM
}

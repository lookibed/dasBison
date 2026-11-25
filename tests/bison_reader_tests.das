options gen2
options indenting = 4

require dastest/testing_boost public
require daslib/strings_boost
require strings
require flex/flex_macro
require bison/bison_macro
require _compile_issues

enum RTok {
    NUM = 256
    IF
    ELSE
    X
}

[flex]
def r_lex(var lx : FlexLexer) : bool {
    rule("[0-9]+(\\.[0-9]+)?") {
        lx |> emit(RTok.NUM)
    }
    rule("if") {
        lx |> emit(RTok.IF)
    }
    rule("else") {
        lx |> emit(RTok.ELSE)
    }
    rule("x") {
        lx |> emit(RTok.X)
    }
    rule("[\\-+*/(),]") {
        lx |> emit(first_character(text(lx)))
    }
    rule("[ \\t\\r\\n]+") {
    }
}

%bison~ calc : float, tokens = RTok, lexer = r_lex
%left '+' '-'
%left '*' '/'
%right UMINUS
%expect 0
%rules
expr : expr '+' expr          { $$ = $1 + $3 }
     | expr '-' expr          { $$ = $1 - $3 }
     | expr '*' expr          { $$ = $1 * $3 }
     | '-' expr %prec UMINUS  { $$ = -$2 }
     | '(' expr ')'           { $$ = $2 }
     | NUM                    { $$ = to_float(text(p.lexer, $1)) }
     ;
%%

// the value, or on a failure the error text after the default value the parser returned
def private run_calc(src : string) : string {
    var p : Parser
    parser_open(p, src, "calc.txt")
    let v = calc(p)
    return p.failed ? "{v} {p.err}" : "{v}"
}

[test(description = "the %bison~ calculator evaluates by its %left and %right lines, %prec gives unary minus its level, and a refused token reports as [bison] does")]
def test_calc(t : T?) {
    t |> equal(run_calc("1+2*3"), "7")
    t |> equal(run_calc("(1+2)*3"), "9")
    t |> equal(run_calc("2-3-4"), "-5")
    t |> equal(run_calc("-2*-(3+1)"), "8")
    t |> equal(run_calc("1+"),
               "0 calc.txt:1:3: unexpected end of input, expected one of: '-', '(', NUM")
    t |> equal(run_calc("2*(3\n+)"),
               "0 calc.txt:2:2: unexpected ')', expected one of: '-', '(', NUM")
}

// the dangling else: one shift/reduce conflict, declared by %expect 1 and resolved by the default shift
%bison~ ifs : string, tokens = RTok, lexer = r_lex
%expect 1
%rules
stmt : IF stmt                { $$ = "if({$2})" }
     | IF stmt ELSE stmt      { $$ = "if({$2}, {$4})" }
     | X                      { $$ = "x" }
     ;
%%

[test(description = "the dangling else in text form binds else to the inner if, with %expect 1 naming its conflict")]
def test_dangling_else(t : T?) {
    var p : Parser
    parser_open(p, "if if x else x")
    t |> equal(ifs(p), "if(if(x, x))")
    parser_open(p, "if x else if x else x")
    t |> equal(ifs(p), "if(x, if(x, x))")
}

// the effects the actions of `sums` and `marks` ran, in reduce order
var private g_log : array<string>

// the root is `doc`, not the first rule; `items` is typed by %type, the root by the header
%bison~ sums : string, tokens = RTok, lexer = r_lex
%start doc
%type <int> items
%rules
items : items ',' NUM   {
            let v = to_int(text(p.lexer, $3))
            g_log |> push("+{v}")
            $$ = $1 + v
        }
      | NUM             { $$ = to_int(text(p.lexer, $1)) }
      ;
doc : '(' items ')'     { return "sum {$2}" }
    | '(' ')'           { $$ = "empty" }
    | marks             { $$ = "marks" }
    ;
marks : marks X         { g_log |> push("x") }
      | X               { g_log |> push("x") }
      ;
%%

[test(description = "%start names the root; a block action runs its statements and ends in $$ = or return; %type types a rule an action reads; a rule without $$ yields nothing and runs for its effect")]
def test_start_and_blocks(t : T?) {
    g_log |> clear()
    var p : Parser
    parser_open(p, "(1, 2, 39)")
    t |> equal(sums(p), "sum 42")
    t |> equal(g_log, ["+2", "+39"])
    parser_open(p, "()")
    t |> equal(sums(p), "empty")
    g_log |> clear()
    parser_open(p, "x x")
    t |> equal(sums(p), "marks")
    t |> equal(g_log, ["x", "x"])
    parser_open(p, "1, 2")
    sums(p)
    t |> equal(p.err, "1:1: unexpected NUM, expected one of: '(', X")
}

[test(description = "the source the reader writes keeps every rule and every line of an action on the line it was written on")]
def test_line_preserving_source(t : T?) {
    let text = " e : int, tokens = T, lexer = lx\n%left '+'\n\n%rules\ne : e '+' e \{\n    $$ = $1 + $3\n\}\n  | N \{ $$ = 1 \} ;\n"
    let out = bison_reader_source(text)
    t |> equal(out.err, "")
    let lines <- split(out.source, "\n")
    t |> equal(count(out.source, "\n"), count(text, "\n") + 1)   // the `}` takes the `%%` line
    t |> equal(lines[0], "[bison(tokens = T, lexer = lx)] def e(var p : Parser) : int \{")
    t |> equal(lines[1], "prec_left(\"'+'\")")
    t |> equal(lines[4], "rule(\"e\", \"e '+' e\") <| $(_1 : int; _3 : int) : int \{")
    t |> equal(lines[5], "    return _1 + _3")
    t |> equal(lines[7], "rule(\"e\", \"N\") <| $() : int \{ return 1 \}")
    t |> equal(lines[8], "\}")
}

//! a module with a lexer of `NUM` and punctuation and a `%bison~ bad : int` grammar of `decls` and
//! `rules`; the `%bison~` header is line 20
def private reader_module(decls, rules : string) : string {
    let head = ("options gen2\nrequire strings\nrequire flex/flex_macro\nrequire bison/bison_macro\n"
        + "enum E \{\n    NUM = 256\n\}\n[flex]\ndef lx(var lx : FlexLexer) : bool \{\n"
        + "    rule(\"[0-9]+\") \{\n        lx |> emit(E.NUM)\n    \}\n"
        + "    rule(\"[+()]\") \{\n        lx |> emit(first_character(text(lx)))\n    \}\n\}\n\n\n\n")
    return head + "%bison~ bad : int, tokens = E, lexer = lx\n{decls}%rules\n{rules}%%\n"
}

[test(description = "a module the reader test helper writes compiles clean when its grammar is right")]
def test_clean_module(t : T?) {
    t |> equal(compile_issues("ok.das", reader_module("%left '+'\n", "e : e '+' e  \{ $$ = $1 + $3 \}\n  | NUM  \{ $$ = 1 \}\n  ;\n")), "")
}

[test(description = "$n on a valueless symbol, $n past the right-hand side, an unknown token, a missing %rules and a rule without ';' fail the compile at the line of the text")]
def test_errors(t : T?) {
    t |> run("$n on a quoted character") @(t : T?) {
        let issues = compile_issues("e1.das", reader_module("", "e : NUM  \{ $$ = 1 \}\n  | '(' e ')'  \{ $$ = $1 \}\n  ;\n"))
        t |> has_issue(issues, "$1 is '(', a quoted character, which carries no value")
        t |> has_issue(issues, "e1.das:23:")
    }
    t |> run("$n on a rule that yields nothing") @(t : T?) {
        let issues = compile_issues("e2.das", reader_module("", "e : v NUM  \{ $$ = $1 \}\n  ;\nv : '('  \{ \}\n  ;\n"))
        t |> has_issue(issues, "$1 is 'v', a rule that yields no value")
        t |> has_issue(issues, "e2.das:22:")
    }
    t |> run("$n past the right-hand side") @(t : T?) {
        let issues = compile_issues("e3.das", reader_module("", "e : NUM  \{\n    $$ = 1\n\}\n  | '(' e ')'  \{\n    $$ = $4\n\}\n  ;\n"))
        t |> has_issue(issues, "$4: the right-hand side of 'e' has 3 symbols")
        t |> has_issue(issues, "e3.das:26:")
    }
    t |> run("an unknown token name") @(t : T?) {
        let issues = compile_issues("e4.das", reader_module("", "e : NUM  \{ $$ = 1 \}\n  | NOPE  \{ $$ = 2 \}\n  ;\n"))
        t |> has_issue(issues, "'NOPE' is neither a rule nor a token")
        t |> has_issue(issues, "e4.das:23:")
    }
    t |> run("no %rules line") @(t : T?) {
        let src = replace(reader_module("%left '+'\n", ""), "%rules\n", "")
        let issues = compile_issues("e5.das", src)
        t |> has_issue(issues, "the rules section starts at a line `%rules`")
        t |> has_issue(issues, "e5.das:22:")
    }
    t |> run("a rule without ';'") @(t : T?) {
        let issues = compile_issues("e6.das", reader_module("", "e : NUM  \{ $$ = 1 \}\n  | v  \{ $$ = $1 \}\n\nv : NUM  \{ $$ = 2 \}\n  ;\n"))
        t |> has_issue(issues, "the rule 'e' ends with ';'")
        t |> has_issue(issues, "e6.das:23:")
    }
    t |> run("$n of an untyped rule") @(t : T?) {
        let issues = compile_issues("e7.das", reader_module("", "e : v  \{ $$ = $1 \}\n  ;\nv : NUM  \{ $$ = 2 \}\n  ;\n"))
        t |> has_issue(issues, "$1 is 'v', whose type the text does not declare: `%type <Type> v`")
        t |> has_issue(issues, "e7.das:22:")
    }
}

[test(description = "a type error inside an action is reported at the user's line in the %bison~ text")]
def test_action_error_line(t : T?) {
    let issues = compile_issues("a1.das", reader_module("", "e : NUM  \{\n    let s : string = 1\n    $$ = 1\n\}\n  ;\n"))
    t |> success(!empty(issues), "the action must not compile")
    t |> has_issue(issues, "a1.das:23:")
}

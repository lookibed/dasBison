options gen2
options indenting = 4

require dastest/testing_boost public
require daslib/strings_boost
require strings
require math
require flex/flex_macro
require bison/bison_macro
require _compile_issues
require _bison_run

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
    rule("[\\-+*/(),^<]") {
        lx |> emit(first_character(text(lx)))
    }
    rule("[ \\t\\r\\n]+") {
    }
}

%bison~ calc : float, tokens = RTok, lexer = r_lex
%nonassoc '<'
%left '+' '-'
%left '*' '/'
%right '^'
%right UMINUS
%expect 0
%rules
expr : expr '<' expr          { $$ = $1 < $3 ? 1.0 : 0.0 }
     | expr '+' expr          { $$ = $1 + $3 }
     | expr '-' expr          { $$ = $1 - $3 }
     | expr '*' expr          { $$ = $1 * $3 }
     | expr '^' expr          { $$ = pow($1, $3) }
     | '-' expr %prec UMINUS  { $$ = -$2 }
     | '(' expr ')'           { $$ = $2 }
     | NUM                    { $$ = to_float(text(p.lexer, $1)) }
     ;
%%

[test(description = "the %bison~ calculator evaluates by its precedence lines: %right groups 2^3^2 to the right, %nonassoc refuses a < b < c, %prec lifts unary minus above ^ so -2^2 is 4, and a refused token reports as [bison] does")]
def test_calc(t : T?) {
    t |> equal(run_parser(@@calc, "1+2*3"), "7")
    t |> equal(run_parser(@@calc, "(1+2)*3"), "9")
    t |> equal(run_parser(@@calc, "2-3-4"), "-5")
    t |> equal(run_parser(@@calc, "-2*-(3+1)"), "8")
    t |> equal(run_parser(@@calc, "2^3^2"), "512")
    t |> equal(run_parser(@@calc, "-2^2"), "4")
    t |> equal(run_parser(@@calc, "2*3^2"), "18")
    t |> equal(run_parser(@@calc, "1+1<3"), "1")
    t |> equal(run_parser(@@calc, "1<2<3"),
               "0 calc.txt:1:4: unexpected '<', expected one of: '+', '-', '*', '^', end of input")
    t |> equal(run_parser(@@calc, "1+"),
               "0 calc.txt:1:3: unexpected end of input, expected one of: '-', '(', NUM")
    t |> equal(run_parser(@@calc, "2*(3\n+)"),
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

[test(description = "%start before a precedence line puts root on its own line, the precedence call on the next")]
def test_start_line(t : T?) {
    let text = " e : int, tokens = T, lexer = lx\n%start e\n%left '+'\n%rules\ne : e '+' e \{ $$ = 1 \} ;\n"
    let out = bison_reader_source(text)
    t |> equal(out.err, "")
    let lines <- split(out.source, "\n")
    t |> equal(count(out.source, "\n"), count(text, "\n") + 1)
    t |> equal(lines[1], "root(\"e\")")
    t |> equal(lines[2], "prec_left(\"'+'\")")
}

[test(description = "a comment on a declaration line is no part of it: // to the end and /* */ within the line, a quoted / kept")]
def test_declaration_comments(t : T?) {
    let text = (" e : int, tokens = T, lexer = lx\n%left '+' '-' // additive\n"
        + "%left '/' /* division */ '*'  // multiplicative\n%expect 0 // none\n%start e // root\n"
        + "%rules\ne : e '+' e \{ $$ = 1 \} ;\n")
    let out = bison_reader_source(text)
    t |> equal(out.err, "")
    let lines <- split(out.source, "\n")
    t |> equal(lines[0],
               "[bison(tokens = T, lexer = lx, expected = 0)] def e(var p : Parser) : int \{")
    t |> equal(lines[1], "prec_left(\"'+'\", \"'-'\")")
    t |> equal(lines[2], "prec_left(\"'/'\", \"'*'\")")
}

[test(description = "a block comment in an action is copied as written: a brace in it does not close the action, a $n in it is not read, nested comments balance and its lines are kept")]
def test_action_comments(t : T?) {
    let text = (" e : int, tokens = T, lexer = lx\n%rules\ne : N \{ /* } */ $$ = 1 \}\n"
        + "  | N N \{ /* $1 */ $$ = 2 \}\n  | N N N \{ /* a /* nested } */\n  comment */ $$ = 3 \}\n"
        + "  | N N N N \{ $$ = 4 \} ;\n")
    let out = bison_reader_source(text)
    t |> equal(out.err, "")
    let lines <- split(out.source, "\n")
    t |> equal(count(out.source, "\n"), count(text, "\n") + 1)
    t |> equal(lines[2], "rule(\"e\", \"N\") <| $() : int \{ /* } */ return 1 \}")
    t |> equal(lines[3], "rule(\"e\", \"N N\") <| $() : int \{ /* $1 */ return 2 \}")
    t |> equal(lines[4], "rule(\"e\", \"N N N\") <| $() : int \{ /* a /* nested } */")
    t |> equal(lines[5], "  comment */ return 3 \}")
    t |> equal(lines[6], "rule(\"e\", \"N N N N\") <| $() : int \{ return 4 \}")
}

[test(description = "the reader places every call on its line: two alternatives of one line joined by ;, an action whose string or comment spans lines, an action on the line after its symbols, an empty alternative on the line of its terminator")]
def test_line_placement(t : T?) {
    let text = (" e : int, tokens = T, lexer = lx\n%left '+'\n%rules\n"
        + "e : N \{ $$ = 1 \} | N N \{ $$ = 2 \}\n"
        + "  | N N N \{ $$ = \"a\nb\" == \"\" ? 3 : 4 \}\n"
        + "  | N '+'\n    \{ $$ = 5 \}\n"
        + "  | N N N N \{ /* a\n b */ $$ = 6 \}\n"
        + "  | f \{ $$ = 7 \}\n  ;\n"
        + "f : N\n  |\n  ;\n")
    let out = bison_reader_source(text)
    t |> equal(out.err, "")
    let lines <- split(out.source, "\n")
    t |> equal(count(out.source, "\n"), count(text, "\n") + 1)
    t |> equal(lines[3], ("rule(\"e\", \"N\") <| $() : int \{ return 1 \}; "
        + "rule(\"e\", \"N N\") <| $() : int \{ return 2 \}"))
    t |> equal(lines[4], "rule(\"e\", \"N N N\") <| $() : int \{ return \"a")
    t |> equal(lines[5], "b\" == \"\" ? 3 : 4 \}")
    t |> equal(lines[6], "")
    t |> equal(lines[7], "rule(\"e\", \"N '+'\") <| $() : int \{ return 5 \}")
    t |> equal(lines[8], "rule(\"e\", \"N N N N\") <| $() : int \{ /* a")
    t |> equal(lines[9], " b */ return 6 \}")
    t |> equal(lines[10], "rule(\"e\", \"f\") <| $() : int \{ return 7 \}")
    t |> equal(lines[12], "rule(\"f\", \"N\")")
    t |> equal(lines[13], "")
    t |> equal(lines[14], "rule(\"f\", \"\")")
    t |> equal(lines[15], "\}")
}

// `e` reads `$2`, so its action takes every value: `v`'s too when `v` yields one
def private return_probe(v_action : string) : BisonReaderOutput {
    return bison_reader_source(" e : int, tokens = T, lexer = lx\n%rules\ne : v N \{ $$ = $2 \} ;\n"
        + "v : '(' \{ {v_action} \} ;\n")
}

[test(description = "an action returns a value when the token after return, past blanks and comments, is not ; } ) or the line's end: return(0) and a parenthesis that opens a multi-line value yield; return before ; } ) a comment or the line's end does not")]
def test_return_value(t : T?) {
    for (valued in ["return(0)", "return (\n0)", "return /* c */ 0"]) {
        let out = return_probe(valued)
        t |> equal(out.err, "$1 is 'v', whose type the text does not declare: `%type <Type> v`",
                   valued)
    }
    for (bare in ["return  ;", "return /* none */ ;", "return // none\n", "return", "return\n",
                  "(return)"]) {
        let out = return_probe(bare)
        t |> equal(out.err, "", bare)
        t |> success(find(out.source, "<| $(_2 : FlexToken) : int") >= 0, out.source)
    }
}

// line `n` of the reader's output, or its error
def private out_line(out : BisonReaderOutput; n : int) : string {
    return "error at {out.line}: {out.err}" if (!empty(out.err))
    let lines <- split(out.source, "\n")
    return n < length(lines) ? lines[n] : "no line {n}"
}

// the reader's output for `rules` after a header of `e : int` and an empty declaration section
def private rules_source(rules : string) : BisonReaderOutput =>
    bison_reader_source(" e : int, tokens = T, lexer = lx\n%rules\n" + rules)

[test(description = "the reader lexes comments between rules, quoted quotes and braces, character literals and // in actions, $ before a non-digit, %empty, %prec with a quoted character, CRLF and nested types in the header and %type")]
def test_reader_lexing(t : T?) {
    let between = rules_source("e : f \{ $$ = 1 \} ;\n// one \} here\n/* two\n \} */\nf : N ;\n")
    t |> equal(out_line(between, 6), "rule(\"f\", \"N\")")
    let quote = rules_source("e : N '\\'' '\{' N '\}' \{ $$ = 1 \} ;\n")
    t |> equal(out_line(quote, 2),
               "rule(\"e\", \"N '\\\\'' '\\\{' N '\\\}'\") <| $() : int \{ return 1 \}")
    let chars = rules_source("e : N \{ let c = '\}'; $$ = 1 // \}\n \}\n  | N N \{ $$ = 2 \} ;\n")
    t |> equal(out_line(chars, 2),
               "rule(\"e\", \"N\") <| $() : int \{ let c = '\}'; return 1 // \}")
    t |> equal(out_line(chars, 4), "rule(\"e\", \"N N\") <| $() : int \{ return 2 \}")
    let dollar = rules_source("e : N \{ $$ = $x \} ;\n")
    t |> equal(out_line(dollar, 2), "rule(\"e\", \"N\") <| $() : int \{ return $x \}")
    let none = rules_source("e : f N \{ $$ = 1 \} ;\nf : %empty | N ;\n")
    t |> equal(out_line(none, 3), "rule(\"f\", \"\"); rule(\"f\", \"N\")")
    let prec = bison_reader_source(" e : int, tokens = T, lexer = lx\n%left '*'\n%rules\n"
        + "e : '-' N %prec '*' \{ $$ = 1 \} ;\n")
    t |> equal(out_line(prec, 3), "rule(\"e\", \"'-' N %prec '*'\") <| $() : int \{ return 1 \}")
    let lf = (" e : int, tokens = T, lexer = lx\n%left '+'\n%rules\ne : e '+' N \{\n $$ = 1 \}\n"
        + "  | N \{ $$ = 2 \}\n  ;\n")
    let crlf = bison_reader_source(replace(lf, "\n", "\r\n"))
    t |> equal(crlf.err, "")
    t |> equal(replace(crlf.source, "\r", ""), bison_reader_source(lf).source)
    let types = bison_reader_source(" e : array<tuple<int, float>>, tokens = T, lexer = lx\n"
        + "%type <table<string; array<int>>> f\n%rules\ne : f \{ $$ = [(1, 2.0)] \} ;\n"
        + "f : N \{ $$ = \{\"a\" => [1]\} \} ;\n")
    t |> equal(out_line(types, 0), "[bison(tokens = T, lexer = lx)] def e(var p : Parser) : array<tuple<int, float>> \{")
    t |> equal(out_line(types, 4), "rule(\"f\", \"N\") <| $() : table<string; array<int>> \{ return \{\"a\" => [1]\} \}")
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

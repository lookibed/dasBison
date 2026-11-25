options gen2
options indenting = 4

module c11_parser public

// The C11 grammar of Degener/Lee through [bison]: every production of the yacc grammar as one
// rule with its yacc right-hand side, over the [flex] lexer of dasFlex's C example. The parser
// checks syntax only; its one job besides is the typedef table the lexer reads, filled by the
// grammar's own actions in the classic yacc way:
//
//   storage_class_specifier : bool    TYPEDEF is true, every other storage class false
//   declaration_specifiers  : bool    whether the specifier list holds TYPEDEF
//   direct_declarator, declarator : string    the declared identifier's text
//
// A declarator's name must lex as TYPEDEF_NAME from the token after it, but `declaration` reduces
// only once the token after its `;` is read, too late. So the flag reaches the declarator through
// the parser instead: the innermost `declaration_specifiers` reduction (the last specifier of the
// list, right recursion) pushes its bool on `p.specifiers`, each enclosing one widens the top,
// `init_declarator` - reduced on the `,` or `;` that follows it, before the next token is read -
// adds its name to `p.lexer.symbols` when the top is true, and the consumers of a specifier list
// (`declaration`, `function_definition`, `parameter_declaration`) pop it. A parameter list inside
// a declarator pushes and pops its own entries, so `typedef void (*handler)(int sig);` declares
// `handler` and not `sig`. Block scope is not tracked: a typedef name stays one to the end.
//
// Two conflicts are left. The dangling else shifts by yacc's default (`expected = 1`). `_Atomic (`
// is the type specifier `_Atomic ( type-name )`, as C11 6.7.2.4 reads it, not the qualifier
// followed by a parenthesis: two precedence lines put `'('` above ATOMIC, so the cell shifts by
// precedence rather than by default.
//
// The token stream is the probe's: `c11_tokens` wraps the lexer, dropping GNU `__attribute__`,
// `__asm__` and `__typeof__` with their parenthesized arguments and the keywords `__extension__`,
// `__inline`, `__restrict`, and joining adjacent string literals into one token.

require bison/bison_macro public
require ../../../dasFlex/examples/c_lexer/c_lexer.das public

//! A C11 parser: the bison `Parser`, the typedef flags of the specifier lists being parsed, and
//! how many typedef names the actions declared.
struct C11Parser : Parser {
    specifiers : array<bool>
    typedefs : int
}

//! The outcome of one parse: accepted or the error, external declarations and typedef names seen.
struct C11Result {
    accepted : bool
    decls : int
    typedefs : int
    err : string
}

//! a specifier list starts at its last specifier
def private open_specifiers(var p : C11Parser; is_typedef : bool) : bool {
    p.specifiers |> push(is_typedef)
    return is_typedef
}

//! an enclosing specifier of the same list
def private widen_specifiers(var p : C11Parser; is_typedef : bool) : bool {
    p.specifiers[length(p.specifiers) - 1] = is_typedef
    return is_typedef
}

//! the declaration, definition or parameter that read the list is done with it
def private close_specifiers(var p : C11Parser) {
    p.specifiers |> pop()
}

//! a declarator of the innermost open specifier list: under TYPEDEF its name lexes as a type next
def private declare_name(var p : C11Parser; name : string) {
    if (p.specifiers[length(p.specifiers) - 1] && !key_exists(p.lexer.symbols, name)) {
        p.lexer.symbols[name] = 1
        p.typedefs++
    }
}

let private GNU_WITH_ARGS <- fixed_array("__attribute__", "__asm__", "__asm", "__typeof__")
let private GNU_DROPPED <- fixed_array("__extension__", "__inline", "__inline__", "__restrict", "__restrict__")

def private is_word(kind : int) : bool => kind == int(CTok.IDENTIFIER) || kind == int(CTok.TYPEDEF_NAME)

//! skip a GNU construct's parenthesized argument: through the `)` that balances the first `(`
def private skip_parens(var lx : FlexLexer) {
    var depth = 0
    while (c_next(lx)) {
        if (lx.tok.kind == '(') {
            depth++
        } elif (lx.tok.kind == ')') {
            depth--
            return if (depth == 0)
        }
    }
}

//! extend the string literal in `lx.tok` over the string literals right after it
def private join_strings(var lx : FlexLexer) {
    while (true) {
        let tok = lx.tok
        let pos = lx.pos
        let line = lx.line
        let col = lx.col
        let cond = lx.cond
        if (c_next(lx) && lx.tok.kind == int(CTok.STRING_LITERAL)) {
            let next = lx.tok
            lx.tok = tok
            lx.tok.len = next.start + next.len - tok.start
            continue
        }
        lx.tok = tok
        lx.pos = pos
        lx.line = line
        lx.col = col
        lx.cond = cond
        lx.failed = false
        lx.emitted = true
        return
    }
}

//! The parser's lexer: `c_next`, with the GNU extensions dropped and adjacent strings joined.
def c11_tokens(var lx : FlexLexer) : bool {
    while (c_next(lx)) {
        if (is_word(lx.tok.kind)) {
            let word = text(lx, lx.tok)
            if (has_value(GNU_WITH_ARGS, word)) {
                skip_parens(lx)
                continue
            }
            continue if (has_value(GNU_DROPPED, word))
        }
        if (lx.tok.kind == int(CTok.STRING_LITERAL)) {
            join_strings(lx)
        }
        return true
    }
    return false
}

[bison(tokens = CTok, lexer = c11_tokens, expected = 1)]
def c11_parse(var p : C11Parser) : int {  // nolint:STYLE038 - a grammar is one rule list by construction
    prec_nonassoc("ATOMIC")
    prec_nonassoc("'('")
    rule("primary_expression", "IDENTIFIER")
    rule("primary_expression", "constant")
    rule("primary_expression", "string")
    rule("primary_expression", "'(' expression ')'")
    rule("primary_expression", "generic_selection")
    rule("constant", "I_CONSTANT")
    rule("constant", "F_CONSTANT")
    rule("constant", "ENUMERATION_CONSTANT")
    rule("enumeration_constant", "IDENTIFIER")
    rule("string", "STRING_LITERAL")
    rule("string", "FUNC_NAME")
    rule("generic_selection", "GENERIC '(' assignment_expression ',' generic_assoc_list ')'")
    rule("generic_assoc_list", "generic_association")
    rule("generic_assoc_list", "generic_assoc_list ',' generic_association")
    rule("generic_association", "type_name ':' assignment_expression")
    rule("generic_association", "DEFAULT ':' assignment_expression")
    rule("postfix_expression", "primary_expression")
    rule("postfix_expression", "postfix_expression '[' expression ']'")
    rule("postfix_expression", "postfix_expression '(' ')'")
    rule("postfix_expression", "postfix_expression '(' argument_expression_list ')'")
    rule("postfix_expression", "postfix_expression '.' IDENTIFIER")
    rule("postfix_expression", "postfix_expression PTR_OP IDENTIFIER")
    rule("postfix_expression", "postfix_expression INC_OP")
    rule("postfix_expression", "postfix_expression DEC_OP")
    rule("postfix_expression", "'(' type_name ')' '\{' initializer_list '\}'")
    rule("postfix_expression", "'(' type_name ')' '\{' initializer_list ',' '\}'")
    rule("argument_expression_list", "assignment_expression")
    rule("argument_expression_list", "argument_expression_list ',' assignment_expression")
    rule("unary_expression", "postfix_expression")
    rule("unary_expression", "INC_OP unary_expression")
    rule("unary_expression", "DEC_OP unary_expression")
    rule("unary_expression", "unary_operator cast_expression")
    rule("unary_expression", "SIZEOF unary_expression")
    rule("unary_expression", "SIZEOF '(' type_name ')'")
    rule("unary_expression", "ALIGNOF '(' type_name ')'")
    rule("unary_operator", "'&'")
    rule("unary_operator", "'*'")
    rule("unary_operator", "'+'")
    rule("unary_operator", "'-'")
    rule("unary_operator", "'~'")
    rule("unary_operator", "'!'")
    rule("cast_expression", "unary_expression")
    rule("cast_expression", "'(' type_name ')' cast_expression")
    rule("multiplicative_expression", "cast_expression")
    rule("multiplicative_expression", "multiplicative_expression '*' cast_expression")
    rule("multiplicative_expression", "multiplicative_expression '/' cast_expression")
    rule("multiplicative_expression", "multiplicative_expression '%' cast_expression")
    rule("additive_expression", "multiplicative_expression")
    rule("additive_expression", "additive_expression '+' multiplicative_expression")
    rule("additive_expression", "additive_expression '-' multiplicative_expression")
    rule("shift_expression", "additive_expression")
    rule("shift_expression", "shift_expression LEFT_OP additive_expression")
    rule("shift_expression", "shift_expression RIGHT_OP additive_expression")
    rule("relational_expression", "shift_expression")
    rule("relational_expression", "relational_expression '<' shift_expression")
    rule("relational_expression", "relational_expression '>' shift_expression")
    rule("relational_expression", "relational_expression LE_OP shift_expression")
    rule("relational_expression", "relational_expression GE_OP shift_expression")
    rule("equality_expression", "relational_expression")
    rule("equality_expression", "equality_expression EQ_OP relational_expression")
    rule("equality_expression", "equality_expression NE_OP relational_expression")
    rule("and_expression", "equality_expression")
    rule("and_expression", "and_expression '&' equality_expression")
    rule("exclusive_or_expression", "and_expression")
    rule("exclusive_or_expression", "exclusive_or_expression '^' and_expression")
    rule("inclusive_or_expression", "exclusive_or_expression")
    rule("inclusive_or_expression", "inclusive_or_expression '|' exclusive_or_expression")
    rule("logical_and_expression", "inclusive_or_expression")
    rule("logical_and_expression", "logical_and_expression AND_OP inclusive_or_expression")
    rule("logical_or_expression", "logical_and_expression")
    rule("logical_or_expression", "logical_or_expression OR_OP logical_and_expression")
    rule("conditional_expression", "logical_or_expression")
    rule("conditional_expression", "logical_or_expression '?' expression ':' conditional_expression")
    rule("assignment_expression", "conditional_expression")
    rule("assignment_expression", "unary_expression assignment_operator assignment_expression")
    rule("assignment_operator", "'='")
    rule("assignment_operator", "MUL_ASSIGN")
    rule("assignment_operator", "DIV_ASSIGN")
    rule("assignment_operator", "MOD_ASSIGN")
    rule("assignment_operator", "ADD_ASSIGN")
    rule("assignment_operator", "SUB_ASSIGN")
    rule("assignment_operator", "LEFT_ASSIGN")
    rule("assignment_operator", "RIGHT_ASSIGN")
    rule("assignment_operator", "AND_ASSIGN")
    rule("assignment_operator", "XOR_ASSIGN")
    rule("assignment_operator", "OR_ASSIGN")
    rule("expression", "assignment_expression")
    rule("expression", "expression ',' assignment_expression")
    rule("constant_expression", "conditional_expression")
    rule("declaration", "declaration_specifiers ';'") <| $() {
        p |> close_specifiers()
    }
    rule("declaration", "declaration_specifiers init_declarator_list ';'") <| $() {
        p |> close_specifiers()
    }
    rule("declaration", "static_assert_declaration")
    rule("declaration_specifiers", "storage_class_specifier declaration_specifiers") <| $(s, d : bool) => p |> widen_specifiers(s || d)
    rule("declaration_specifiers", "storage_class_specifier") <| $(s : bool) => p |> open_specifiers(s)
    rule("declaration_specifiers", "type_specifier declaration_specifiers")
    rule("declaration_specifiers", "type_specifier") <| $() => p |> open_specifiers(false)
    rule("declaration_specifiers", "type_qualifier declaration_specifiers")
    rule("declaration_specifiers", "type_qualifier") <| $() => p |> open_specifiers(false)
    rule("declaration_specifiers", "function_specifier declaration_specifiers")
    rule("declaration_specifiers", "function_specifier") <| $() => p |> open_specifiers(false)
    rule("declaration_specifiers", "alignment_specifier declaration_specifiers")
    rule("declaration_specifiers", "alignment_specifier") <| $() => p |> open_specifiers(false)
    rule("init_declarator_list", "init_declarator")
    rule("init_declarator_list", "init_declarator_list ',' init_declarator")
    rule("init_declarator", "declarator '=' initializer") <| $(name : string) {
        p |> declare_name(name)
    }
    rule("init_declarator", "declarator") <| $(name : string) {
        p |> declare_name(name)
    }
    rule("storage_class_specifier", "TYPEDEF") <| $() => true
    rule("storage_class_specifier", "EXTERN") <| $() => false
    rule("storage_class_specifier", "STATIC") <| $() => false
    rule("storage_class_specifier", "THREAD_LOCAL") <| $() => false
    rule("storage_class_specifier", "AUTO") <| $() => false
    rule("storage_class_specifier", "REGISTER") <| $() => false
    rule("type_specifier", "VOID")
    rule("type_specifier", "CHAR")
    rule("type_specifier", "SHORT")
    rule("type_specifier", "INT")
    rule("type_specifier", "LONG")
    rule("type_specifier", "FLOAT")
    rule("type_specifier", "DOUBLE")
    rule("type_specifier", "SIGNED")
    rule("type_specifier", "UNSIGNED")
    rule("type_specifier", "BOOL")
    rule("type_specifier", "COMPLEX")
    rule("type_specifier", "IMAGINARY")
    rule("type_specifier", "atomic_type_specifier")
    rule("type_specifier", "struct_or_union_specifier")
    rule("type_specifier", "enum_specifier")
    rule("type_specifier", "TYPEDEF_NAME")
    rule("struct_or_union_specifier", "struct_or_union '\{' struct_declaration_list '\}'")
    rule("struct_or_union_specifier", "struct_or_union IDENTIFIER '\{' struct_declaration_list '\}'")
    rule("struct_or_union_specifier", "struct_or_union IDENTIFIER")
    rule("struct_or_union", "STRUCT")
    rule("struct_or_union", "UNION")
    rule("struct_declaration_list", "struct_declaration")
    rule("struct_declaration_list", "struct_declaration_list struct_declaration")
    rule("struct_declaration", "specifier_qualifier_list ';'")
    rule("struct_declaration", "specifier_qualifier_list struct_declarator_list ';'")
    rule("struct_declaration", "static_assert_declaration")
    rule("specifier_qualifier_list", "type_specifier specifier_qualifier_list")
    rule("specifier_qualifier_list", "type_specifier")
    rule("specifier_qualifier_list", "type_qualifier specifier_qualifier_list")
    rule("specifier_qualifier_list", "type_qualifier")
    rule("struct_declarator_list", "struct_declarator")
    rule("struct_declarator_list", "struct_declarator_list ',' struct_declarator")
    rule("struct_declarator", "':' constant_expression")
    rule("struct_declarator", "declarator ':' constant_expression")
    rule("struct_declarator", "declarator")
    rule("enum_specifier", "ENUM '\{' enumerator_list '\}'")
    rule("enum_specifier", "ENUM '\{' enumerator_list ',' '\}'")
    rule("enum_specifier", "ENUM IDENTIFIER '\{' enumerator_list '\}'")
    rule("enum_specifier", "ENUM IDENTIFIER '\{' enumerator_list ',' '\}'")
    rule("enum_specifier", "ENUM IDENTIFIER")
    rule("enumerator_list", "enumerator")
    rule("enumerator_list", "enumerator_list ',' enumerator")
    rule("enumerator", "enumeration_constant '=' constant_expression")
    rule("enumerator", "enumeration_constant")
    rule("atomic_type_specifier", "ATOMIC '(' type_name ')'")
    rule("type_qualifier", "CONST")
    rule("type_qualifier", "RESTRICT")
    rule("type_qualifier", "VOLATILE")
    rule("type_qualifier", "ATOMIC")
    rule("function_specifier", "INLINE")
    rule("function_specifier", "NORETURN")
    rule("alignment_specifier", "ALIGNAS '(' type_name ')'")
    rule("alignment_specifier", "ALIGNAS '(' constant_expression ')'")
    rule("declarator", "pointer direct_declarator")
    rule("declarator", "direct_declarator") <| $(name : string) => name
    rule("direct_declarator", "IDENTIFIER") <| $(t : FlexToken) => text(p.lexer, t)
    rule("direct_declarator", "'(' declarator ')'")
    rule("direct_declarator", "direct_declarator '[' ']'")
    rule("direct_declarator", "direct_declarator '[' '*' ']'")
    rule("direct_declarator", "direct_declarator '[' STATIC type_qualifier_list assignment_expression ']'") <| $(name : string; static_kw : FlexToken) => name
    rule("direct_declarator", "direct_declarator '[' STATIC assignment_expression ']'") <| $(name : string; static_kw : FlexToken) => name
    rule("direct_declarator", "direct_declarator '[' type_qualifier_list '*' ']'")
    rule("direct_declarator", "direct_declarator '[' type_qualifier_list STATIC assignment_expression ']'") <| $(name : string; static_kw : FlexToken) => name
    rule("direct_declarator", "direct_declarator '[' type_qualifier_list assignment_expression ']'")
    rule("direct_declarator", "direct_declarator '[' type_qualifier_list ']'")
    rule("direct_declarator", "direct_declarator '[' assignment_expression ']'")
    rule("direct_declarator", "direct_declarator '(' parameter_type_list ')'")
    rule("direct_declarator", "direct_declarator '(' ')'")
    rule("direct_declarator", "direct_declarator '(' identifier_list ')'")
    rule("pointer", "'*' type_qualifier_list pointer")
    rule("pointer", "'*' type_qualifier_list")
    rule("pointer", "'*' pointer")
    rule("pointer", "'*'")
    rule("type_qualifier_list", "type_qualifier")
    rule("type_qualifier_list", "type_qualifier_list type_qualifier")
    rule("parameter_type_list", "parameter_list ',' ELLIPSIS")
    rule("parameter_type_list", "parameter_list")
    rule("parameter_list", "parameter_declaration")
    rule("parameter_list", "parameter_list ',' parameter_declaration")
    rule("parameter_declaration", "declaration_specifiers declarator") <| $() {
        p |> close_specifiers()
    }
    rule("parameter_declaration", "declaration_specifiers abstract_declarator") <| $() {
        p |> close_specifiers()
    }
    rule("parameter_declaration", "declaration_specifiers") <| $() {
        p |> close_specifiers()
    }
    rule("identifier_list", "IDENTIFIER")
    rule("identifier_list", "identifier_list ',' IDENTIFIER")
    rule("type_name", "specifier_qualifier_list abstract_declarator")
    rule("type_name", "specifier_qualifier_list")
    rule("abstract_declarator", "pointer direct_abstract_declarator")
    rule("abstract_declarator", "pointer")
    rule("abstract_declarator", "direct_abstract_declarator")
    rule("direct_abstract_declarator", "'(' abstract_declarator ')'")
    rule("direct_abstract_declarator", "'[' ']'")
    rule("direct_abstract_declarator", "'[' '*' ']'")
    rule("direct_abstract_declarator", "'[' STATIC type_qualifier_list assignment_expression ']'")
    rule("direct_abstract_declarator", "'[' STATIC assignment_expression ']'")
    rule("direct_abstract_declarator", "'[' type_qualifier_list STATIC assignment_expression ']'")
    rule("direct_abstract_declarator", "'[' type_qualifier_list assignment_expression ']'")
    rule("direct_abstract_declarator", "'[' type_qualifier_list ']'")
    rule("direct_abstract_declarator", "'[' assignment_expression ']'")
    rule("direct_abstract_declarator", "direct_abstract_declarator '[' ']'")
    rule("direct_abstract_declarator", "direct_abstract_declarator '[' '*' ']'")
    rule("direct_abstract_declarator", "direct_abstract_declarator '[' STATIC type_qualifier_list assignment_expression ']'")
    rule("direct_abstract_declarator", "direct_abstract_declarator '[' STATIC assignment_expression ']'")
    rule("direct_abstract_declarator", "direct_abstract_declarator '[' type_qualifier_list assignment_expression ']'")
    rule("direct_abstract_declarator", "direct_abstract_declarator '[' type_qualifier_list STATIC assignment_expression ']'")
    rule("direct_abstract_declarator", "direct_abstract_declarator '[' type_qualifier_list ']'")
    rule("direct_abstract_declarator", "direct_abstract_declarator '[' assignment_expression ']'")
    rule("direct_abstract_declarator", "'(' ')'")
    rule("direct_abstract_declarator", "'(' parameter_type_list ')'")
    rule("direct_abstract_declarator", "direct_abstract_declarator '(' ')'")
    rule("direct_abstract_declarator", "direct_abstract_declarator '(' parameter_type_list ')'")
    rule("initializer", "'\{' initializer_list '\}'")
    rule("initializer", "'\{' initializer_list ',' '\}'")
    rule("initializer", "assignment_expression")
    rule("initializer_list", "designation initializer")
    rule("initializer_list", "initializer")
    rule("initializer_list", "initializer_list ',' designation initializer")
    rule("initializer_list", "initializer_list ',' initializer")
    rule("designation", "designator_list '='")
    rule("designator_list", "designator")
    rule("designator_list", "designator_list designator")
    rule("designator", "'[' constant_expression ']'")
    rule("designator", "'.' IDENTIFIER")
    rule("static_assert_declaration", "STATIC_ASSERT '(' constant_expression ',' STRING_LITERAL ')' ';'")
    rule("statement", "labeled_statement")
    rule("statement", "compound_statement")
    rule("statement", "expression_statement")
    rule("statement", "selection_statement")
    rule("statement", "iteration_statement")
    rule("statement", "jump_statement")
    rule("labeled_statement", "IDENTIFIER ':' statement")
    rule("labeled_statement", "CASE constant_expression ':' statement")
    rule("labeled_statement", "DEFAULT ':' statement")
    rule("compound_statement", "'\{' '\}'")
    rule("compound_statement", "'\{' block_item_list '\}'")
    rule("block_item_list", "block_item")
    rule("block_item_list", "block_item_list block_item")
    rule("block_item", "declaration")
    rule("block_item", "statement")
    rule("expression_statement", "';'")
    rule("expression_statement", "expression ';'")
    rule("selection_statement", "IF '(' expression ')' statement ELSE statement")
    rule("selection_statement", "IF '(' expression ')' statement")
    rule("selection_statement", "SWITCH '(' expression ')' statement")
    rule("iteration_statement", "WHILE '(' expression ')' statement")
    rule("iteration_statement", "DO statement WHILE '(' expression ')' ';'")
    rule("iteration_statement", "FOR '(' expression_statement expression_statement ')' statement")
    rule("iteration_statement", "FOR '(' expression_statement expression_statement expression ')' statement")
    rule("iteration_statement", "FOR '(' declaration expression_statement ')' statement")
    rule("iteration_statement", "FOR '(' declaration expression_statement expression ')' statement")
    rule("jump_statement", "GOTO IDENTIFIER ';'")
    rule("jump_statement", "CONTINUE ';'")
    rule("jump_statement", "BREAK ';'")
    rule("jump_statement", "RETURN ';'")
    rule("jump_statement", "RETURN expression ';'")
    rule("translation_unit", "external_declaration") <| $() => 1
    rule("translation_unit", "translation_unit external_declaration") <| $(n : int) => n + 1
    rule("external_declaration", "function_definition")
    rule("external_declaration", "declaration")
    rule("function_definition", "declaration_specifiers declarator declaration_list compound_statement") <| $() {
        p |> close_specifiers()
    }
    rule("function_definition", "declaration_specifiers declarator compound_statement") <| $() {
        p |> close_specifiers()
    }
    rule("declaration_list", "declaration")
    rule("declaration_list", "declaration_list declaration")
    root("translation_unit")
}

//! Parse the preprocessed C source `src` (`file` names it in the error); `__builtin_va_list` is a
//! typedef name from the start, as GCC's headers assume.
def parse_c11(src : string; file : string = "") : C11Result {
    var p : C11Parser
    parser_open(p, src, file)
    p.lexer.symbols["__builtin_va_list"] = 1
    let decls = c11_parse(p)
    return C11Result(accepted = !p.failed, decls = decls, typedefs = p.typedefs, err = p.err)
}

//! How many tokens the parser reads from `src`: the stream of `c11_tokens`.
def c11_token_count(src : string) : int {
    var lx : FlexLexer
    flex_open(lx, src)
    var n = 0
    while (c11_tokens(lx)) {
        n++
    }
    return n
}

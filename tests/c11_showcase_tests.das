options gen2
options indenting = 4

require dastest/testing_boost public
require daslib/fio
require daslib/module_path
require ../examples/c11/c11_parser.das

//! the tokens a declaration can start with: what an identifier that is no typedef name meets
let private DECLARATION_START = "ATOMIC, TYPEDEF, EXTERN, STATIC, THREAD_LOCAL, AUTO, REGISTER, VOID, CHAR, SHORT, INT, LONG, FLOAT, DOUBLE, SIGNED, UNSIGNED, BOOL, COMPLEX, IMAGINARY, TYPEDEF_NAME, STRUCT, UNION, ENUM, CONST, RESTRICT, VOLATILE, INLINE, NORETURN, ALIGNAS, STATIC_ASSERT"

[test(description = "a typedef name lexes as TYPEDEF_NAME from the token after its declarator: the declaration, a parameter and a result use it, and the same name undeclared is refused")]
def test_typedef_after_declaration(t : T?) {
    let r = parse_c11("typedef int T; T x; T twice(T a) \{ return a + a; \}")
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 3)
    t |> equal(r.typedefs, 1)
    t |> equal(parse_c11("T x;", "t.c").err,
               "t.c:1:1: unexpected IDENTIFIER, expected one of: {DECLARATION_START}")
}

[test(description = "a parameter list inside a typedef's declarator keeps its own specifier flag: the function pointer is a type, its parameter is not, and a declarator after a function type is one again")]
def test_typedef_through_parameters(t : T?) {
    t |> equal(parse_c11("typedef void (*handler)(int sig); handler h; sig x;", "h.c").err,
               "h.c:1:46: unexpected IDENTIFIER, expected one of: {DECLARATION_START}, end of input")
    let r = parse_c11("typedef int F(int), G; G g; F *fp;")
    t |> success(r.accepted, r.err)
    t |> equal(r.typedefs, 2)
}

[test(description = "a struct with a member list, a designated initializer and a typedef of the tagged type")]
def test_struct(t : T?) {
    let r = parse_c11("struct point \{ int x, y; \}; typedef struct point point_t; point_t q = \{ .x = 1, .y = 2 \};")
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 3)
    t |> equal(r.typedefs, 1)
}

[test(description = "a function with an if / else if / else chain: the dangling else shifts, expected = 1")]
def test_if_else(t : T?) {
    let r = parse_c11("int sign(int v) \{ if (v < 0) return -1; else if (v > 0) return 1; else return 0; \}")
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 1)
}

[test(description = "a for loop whose first clause is a declaration, beside a block declaration and a compound assignment")]
def test_for_declaration(t : T?) {
    let r = parse_c11("int sum(int n) \{ int s = 0; for (int i = 0; i < n; i++) \{ s += i; \} return s; \}")
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 1)
}

[test(description = "_Atomic ( is the type specifier _Atomic(type-name), as C11 6.7.2.4 reads it; _Atomic without ( is the qualifier")]
def test_atomic(t : T?) {
    let r = parse_c11("_Atomic(int) counter; _Atomic int flag; _Atomic(int) *p;")
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 3)
}

[test(description = "the token stream drops GNU __attribute__ and __asm__ with their arguments and __extension__, and joins adjacent string literals into one token")]
def test_gnu_filter(t : T?) {
    let src = "extern int f(int) __attribute__((nothrow)) __asm__(\"f\" \"g\"); __extension__ typedef long long ll; ll v; char *s = \"a\" \"b\" \"c\";"
    let r = parse_c11(src)
    t |> success(r.accepted, r.err)
    t |> equal(r.decls, 4)
    t |> equal(c11_token_count(src), 21)
}

//! what a constant in an expression can meet: a postfix, a binary or an assignment operator, `?`, `,`, `;`
let private AFTER_CONSTANT = ("'(', ',', '[', '.', PTR_OP, INC_OP, DEC_OP, '&', '*', '+', '-', '/', '%', "
    + "LEFT_OP, RIGHT_OP, '<', '>', LE_OP, GE_OP, EQ_OP, NE_OP, '^', '|', AND_OP, OR_OP, '?', '=', "
    + "MUL_ASSIGN, DIV_ASSIGN, MOD_ASSIGN, ADD_ASSIGN, SUB_ASSIGN, LEFT_ASSIGN, RIGHT_ASSIGN, "
    + "AND_ASSIGN, XOR_ASSIGN, OR_ASSIGN, ';'")

[test(description = "a missing ; refuses the } at its line and column, naming every token the constant before it could meet, not only the ones left after the reduces the } ran")]
def test_malformed(t : T?) {
    let r = parse_c11("int f(void)\n\{\n    return 1\n\}\n", "bad.c")
    t |> success(!r.accepted)
    t |> equal(r.err, "bad.c:4:1: unexpected '\}', expected one of: {AFTER_CONSTANT}")
}

[test(description = "the preprocessed qsort comparator in tests/data parses from disk, found beside this test file")]
def test_qsort_file(t : T?) {
    let path = path_join(get_this_module_dir(), "data/qsort_cmp.i")
    var src = ""
    fopen(path, "rb") $(f) {
        if (f != null) {
            src = fread(f)
        }
    }
    t |> success(!empty(src), "{path} reads empty")
    let r = parse_c11(src, "qsort_cmp.i")
    t |> success(r.accepted, r.err)
    t |> equal(r.typedefs, 1)
    t |> equal(c11_token_count(src), 284)
}

options gen2
options indenting = 4
options strict_smart_pointers = true
options no_unused_block_arguments = false
options no_unused_function_arguments = false

module bison_macro shared public

require daslib/ast_boost
require daslib/templates_boost
require math
require daslib/strings_boost

require bison/lalr
require bison/prec
require bison/grammar_text
require bison/bison_parser public
require bison/bison_reader public

// `[bison(tokens = Enum, lexer = scan)]` on `def name(var p : Parser) : T { rule(...) ... }` reads
// the grammar at compile time, builds and resolves its LALR(1) tables, stores them as private
// module globals, turns every action into a private function and rewrites the body into the driver.

//! One `rule(...)` call: its text, its action block (null for none) and what the action yields.
struct private BisonRule {
    site : Expression const?
    lhs : string
    rhs : string
    action : ExprBlock?             //!< the action's block, null when the rule has none
    yields : bool                   //!< the action returns a value
}

struct private BisonSpec {
    func_name : string
    param : string
    rules : array<BisonRule>
    precs : array<TextPrec>
    prec_sites : array<Expression const?>
    root : string
    err : string
    err_site : Expression const?
}

//! a failure the compile reports at the call it belongs to; the first one wins
def private fail_at(var spec : BisonSpec; msg : string; site : Expression const?) {
    if (empty(spec.err)) {
        spec.err = msg
        spec.err_site = site
    }
}

//! counts the `return <value>` statements of a block outside the blocks and lambdas nested in it
class private ReturnScan : AstVisitor {
    depth : int
    values : int
    def override preVisitExprMakeBlock(expr : ExprMakeBlock?) {
        depth++
    }
    def override visitExprMakeBlock(var expr : ExprMakeBlock?) : ExpressionPtr {
        depth--
        return expr
    }
    def override visitExprReturn(var expr : ExprReturn?) : ExpressionPtr {
        if (depth == 0 && expr.subexpr != null) {
            values++
        }
        return expr
    }
}

//! whether an action yields a value: its declared result type, else a `return <value>` in it
def private block_yields(var blk : ExprBlock?) : bool {
    if (blk.returnType != null && !blk.returnType.isAuto) {
        return !blk.returnType.isVoid
    }
    var scan = new ReturnScan()
    make_visitor(*scan) $(adapter) {
        for (s in blk.list) {
            visit_expression(s, adapter)
        }
    }
    let yields = scan.values > 0
    unsafe {
        delete scan
    }
    return yields
}

def private const_string(e : Expression const?) : tuple<ok : bool; value : string> {
    return (ok = false, value = "") if (!(e is ExprConstString))
    return (ok = true, value = string((e as ExprConstString).value))
}

def private collect_rule(var spec : BisonSpec; call : ExprCall?) {
    let nargs = length(call.arguments)
    let lhs = nargs >= 2 ? const_string(call.arguments[0]) : (ok = false, value = "")
    let rhs = nargs >= 2 ? const_string(call.arguments[1]) : (ok = false, value = "")
    let has_block = nargs == 3 && call.arguments[2] is ExprMakeBlock
    if (!lhs.ok || !rhs.ok || (nargs == 3 && !has_block) || nargs > 3) {
        fail_at(spec, "rule(\"lhs\", \"rhs\") or rule(\"lhs\", \"rhs\") <| $(values) \{ action \} expected", call)
        return
    }
    var r = BisonRule(site = call, lhs = lhs.value, rhs = rhs.value)
    if (has_block) {
        r.action = call.arguments[2] |> unquote_block
        r.yields = block_yields(r.action)
    }
    spec.rules |> emplace(r)
}

def private collect_prec(var spec : BisonSpec; call : ExprCall?) {
    var pl : TextPrec
    pl.assoc = call.name == "prec_left" ? PrecAssoc.left : (call.name == "prec_right" ? PrecAssoc.right : PrecAssoc.nonassoc)
    for (a in call.arguments) {
        let s = const_string(a)
        if (!s.ok) {
            fail_at(spec, "{call.name} takes token names as strings", call)
            return
        }
        pl.names |> push(s.value)
    }
    spec.precs |> emplace(pl)
    spec.prec_sites |> push(call)
}

def private collect_root(var spec : BisonSpec; call : ExprCall?) {
    let name = length(call.arguments) == 1 ? const_string(call.arguments[0]) : (ok = false, value = "")
    if (!name.ok) {
        fail_at(spec, "root takes a rule name literal: root(\"rule\")", call)
    } elif (!empty(spec.root)) {
        fail_at(spec, "root is named once; root(\"{spec.root}\") came first", call)
    } else {
        spec.root = name.value
    }
}

def private collect(var spec : BisonSpec; body : ExprBlock?) {
    for (st in body.list) {
        return if (!empty(spec.err))
        if (!(st is ExprCall)) {
            fail_at(spec, "only rule, prec_left, prec_right, prec_nonassoc and root calls belong in a [bison] body", st)
            return
        }
        let call = st as ExprCall
        if (call.name == "rule") {
            collect_rule(spec, call)
        } elif (call.name == "prec_left" || call.name == "prec_right"
                || call.name == "prec_nonassoc") {
            collect_prec(spec, call)
        } elif (call.name == "root") {
            collect_root(spec, call)
        } else {
            fail_at(spec, "only rule, prec_left, prec_right, prec_nonassoc and root calls belong in a [bison] body, not {call.name}", call)
        }
    }
}

//! what the grammar's values are: per rule whether it yields one and the action that types it, per
//! production the positions of its value symbols
struct private BisonValues {
    rule_yields : array<bool>
    rule_action : array<int>        //!< per rule: the production whose action types its values, -1
    values : array<array<int>>      //!< per production: the right-hand-side positions that carry values
}

def private rule_name(spec : BisonSpec; i : int) : string =>
    "rule(\"{spec.rules[i].lhs}\", \"{spec.rules[i].rhs}\")"

// per production: which symbols carry a value - named tokens and rules that yield
def private value_positions(spec : BisonSpec; g : TextGrammar; var vals : BisonValues) {
    vals.values |> reserve(length(spec.rules))
    for (i in range(length(spec.rules))) {
        var inscope pos : array<int>
        for (j, s in count(), g.builder.prods[i].rhs) {
            if (sym_is_rule(s) ? vals.rule_yields[sym_rule_of(s)] : g.syms[i][j].ch < 0) {
                pos |> push(j)
            }
        }
        vals.values |> emplace(pos)
    }
}

// one production's action against its rule: the same kind of result as the rule's other actions,
// the argument count, typed arguments, and a pass-through where it has no action
def private check_action(var spec : BisonSpec; vals : BisonValues; lhs, i : int) {
    let r & = unsafe(spec.rules[i])
    let nvalues = length(vals.values[i])
    if (r.action == null) {
        if (vals.rule_yields[lhs] && nvalues != 1) {
            fail_at(spec, "{rule_name(spec, i)} needs an action: '{r.lhs}' yields a value and the right-hand side carries {nvalues} values to pass on, not one", r.site)
        }
        return
    }
    if (r.yields != vals.rule_yields[lhs]) {
        let first = vals.rule_action[lhs]
        fail_at(spec, "{rule_name(spec, i)}: the action returns no value, the one of {rule_name(spec, first)} does", r.site)
        return
    }
    let nargs = length(r.action.arguments)
    if (nargs != 0 && nargs != nvalues) {
        fail_at(spec, "{rule_name(spec, i)}: the action takes {nargs} arguments, the right-hand side carries {nvalues} values (named tokens and rules that yield)", r.site)
        return
    }
    for (a in r.action.arguments) {
        if (a._type == null || a._type.isAuto) {
            fail_at(spec, "{rule_name(spec, i)}: argument '{a.name}' needs a type", r.site)
            return
        }
    }
}

def private plan_values(var spec : BisonSpec; g : TextGrammar) : BisonValues {
    var vals : BisonValues
    let nrules = length(g.builder.rule_names)
    vals.rule_yields |> resize(nrules)
    vals.rule_action |> resize(nrules)
    for (a in vals.rule_action) {
        a = -1
    }
    for (i, r in count(), spec.rules) {
        let lhs = g.builder.prods[i].lhs
        if (r.yields && vals.rule_action[lhs] < 0) {
            vals.rule_yields[lhs] = true
            vals.rule_action[lhs] = i
        }
    }
    value_positions(spec, g, vals)
    for (i in range(length(spec.rules))) {
        check_action(spec, vals, g.builder.prods[i].lhs, i)
    }
    return <- vals
}

//! the private global `name` initialized as `to_array_move([vals...])`
def private table_global(name : string; vals : array<auto>; at : LineInfo;
                         var errors : das_string) : bool {
    var init = convert_to_expression(vals, at)
    if (!(compiling_module() |> add_global_private_var(name, at, init))) {
        errors := "can't add the global {name}"
        return false
    }
    return true
}

//! the name of the private function production `i`'s action becomes
def private action_name(spec : BisonSpec; i : int) : string => "{spec.func_name}`bison`act`{i}"

//! the value stack of rule `r`
def private stack_name(r : int) : string => "bison`v`{r}"

//! production `i`'s action as a private function: the parser, then the action's arguments, each
//! `var` - the value is the action's own, popped off its stack
def private add_action(spec : BisonSpec; i : int; parser_type : TypeDeclPtr;
                       var errors : das_string) : bool {
    let r & = unsafe(spec.rules[i])
    let at = r.site.at
    var fn <- new Function(at = at, atDecl = at, name := action_name(spec, i),
                           flags = FunctionFlags.privateFunction)
    var pvar <- new Variable(at = at, name := spec.param, _type <- clone_type(parser_type))
    pvar.flags.generated = true
    fn.arguments |> emplace(pvar)
    for (a in r.action.arguments) {
        var arg <- clone_variable(a)
        arg._type.flags.constant = false
        arg._type.flags.removeConstant = true
        arg.flags.generated = true
        fn.arguments |> emplace(arg)
    }
    let declared = r.action.returnType != null && !r.action.returnType.isAuto
    let inferred = r.yields ? Type.autoinfer : Type.tVoid
    fn.result = declared ? clone_type(r.action.returnType) : new TypeDecl(at = at,
        baseType = inferred,
        flags = TypeDeclFlags.removeConstant | TypeDeclFlags.removeRef)
    var body = clone_expression(r.action) as ExprBlock
    body.arguments |> clear
    body.returnType = null
    body.blockFlags.isClosure = false
    body.genFlags.generated = true
    fn.body = body
    if (!(compiling_module() |> add_function(fn))) {
        errors := "can't add the action function of {rule_name(spec, i)}"
        return false
    }
    return true
}

//! a call to production `i`'s action: on the parser and on `args`, or with `for_type` on default
//! values of the action's argument types (a call `typedecl` reads and never runs)
def private action_call(spec : BisonSpec; i : int; args : array<string>; for_type : bool;
                        at : LineInfo) : ExpressionPtr {
    var call = new ExprCall(at = at, name := action_name(spec, i))
    call.arguments |> emplace_new <| new ExprVar(at = at, name := spec.param)
    if (!for_type) {
        for (a in args) {
            call.arguments |> emplace_new <| new ExprVar(at = at, name := a)
        }
    } else {
        for (a in spec.rules[i].action.arguments) {
            var tp <- clone_type(a._type)
            tp.flags.constant = false
            tp.flags.ref = false
            var mk = new ExprMakeStruct(at = at, makeType <- tp)
            mk.makeStructFlags.useInitializer = true
            mk.makeStructFlags.alwaysUseInitializer = true
            call.arguments |> emplace(mk)
        }
    }
    return call
}

//! the value stacks: a token stack, and one `array<T>` per rule that yields, `T` the type its first
//! action returns; every other action and pass-through of the rule is checked against it
def private make_stacks(spec : BisonSpec; vals : BisonValues;
                        at : LineInfo) : array<ExpressionPtr> {
    var out : array<ExpressionPtr>
    let none : array<string>
    for (r, k in count(), vals.rule_action) {
        continue if (k < 0)
        let vname = stack_name(r)
        var call = action_call(spec, k, none, true, at)
        out |> push_from <| qmacro_block_to_array() {
            var $i(vname) : array<typedecl($e(call)) -const>
        }
    }
    return <- out
}

//! the type checks a typed stack cannot make itself readable: every action of a rule returns the
//! type of its first, a pass-through passes a value of the rule's type
def private make_type_checks(spec : BisonSpec; g : TextGrammar;
                             vals : BisonValues) : array<ExpressionPtr> {
    var out : array<ExpressionPtr>
    let none : array<string>
    for (i, rl in count(), spec.rules) {
        let lhs = g.builder.prods[i].lhs
        let k = vals.rule_action[lhs]
        continue if (k < 0 || k == i)
        let at = rl.site.at
        let lhs_stack = stack_name(lhs)
        if (rl.action != null) {
            var mine = action_call(spec, i, none, true, at)
            let msg = "[bison] {rule_name(spec, i)}: the action returns another type than the one of {rule_name(spec, k)}"
            out |> push <| qmacro(static_assert(typeinfo stripped_typename($e(mine)) == typeinfo stripped_typename($i(lhs_stack)[0]), $v(msg)))
        } else {
            let s = g.builder.prods[i].rhs[vals.values[i][0]]
            let from = sym_is_rule(s) ? stack_name(sym_rule_of(s)) : "bison`toks"
            let msg = "[bison] {rule_name(spec, i)}: the value passed on is not of the type of {rule_name(spec, k)}"
            out |> push <| qmacro(static_assert(typeinfo stripped_typename($i(from)[0]) == typeinfo stripped_typename($i(lhs_stack)[0]), $v(msg)))
        }
        out[length(out) - 1].at = at
    }
    return <- out
}

//! the pops of production `i`'s right-hand side, last symbol first: a value the action takes into
//! `bison`a<position>`, any other value and every token dropped
def private make_pops(vals : BisonValues; prod : Production; i : int;
                      pass_args : bool) : array<ExpressionPtr> {
    var pops : array<ExpressionPtr>
    let nrhs = length(prod.rhs)
    for (k in range(nrhs)) {
        let j = nrhs - 1 - k
        let s = prod.rhs[j]
        let carries = find_index(vals.values[i], j) >= 0
        continue if (sym_is_rule(s) && !carries)
        let from = sym_is_rule(s) ? stack_name(sym_rule_of(s)) : "bison`toks"
        if (carries && pass_args) {
            let aname = "bison`a{j}"
            pops |> push <| qmacro_expr() {
                var $i(aname) = bison_pop($i(from))
            }
        } else {
            pops |> push <| qmacro_expr() {
                $i(from) |> pop()
            }
        }
    }
    return <- pops
}

//! production `i`'s value: its action's result, the one value passed on, or the action run for its
//! effect; pushed on the stack of `lhs` when the rule yields
def private make_reduce(spec : BisonSpec; vals : BisonValues; i, lhs : int; args : array<string>;
                        at : LineInfo) : array<ExpressionPtr> {
    let rl & = unsafe(spec.rules[i])
    let lhs_stack = stack_name(lhs)
    var reduce : array<ExpressionPtr>
    if (rl.action == null) {
        if (vals.rule_yields[lhs]) {
            let a = args[0]
            reduce |> push <| qmacro_expr() {
                $i(lhs_stack) |> emplace($i(a))
            }
        }
    } elif (rl.yields) {
        var call = action_call(spec, i, args, false, at)
        reduce |> push_from <| qmacro_block_to_array() {
            var bison`r = $e(call)
            $i(lhs_stack) |> emplace(bison`r)
        }
    } else {
        var call = action_call(spec, i, args, false, at)
        reduce |> push(call)
    }
    return <- reduce
}

//! the reduce by production `i` (table production `i + 1`): pop its states and values, run the
//! action or pass the one value on, push the result and the goto state
def private make_arm(spec : BisonSpec; g : TextGrammar; vals : BisonValues; i, nrules : int;
                     g_goto : string) : ExpressionPtr {
    let rl & = unsafe(spec.rules[i])
    let at = rl.site.at
    let prod & = unsafe(g.builder.prods[i])
    let lhs = prod.lhs
    let nrhs = length(prod.rhs)
    let pass_args = rl.action == null || !empty(rl.action.arguments)
    var pops <- make_pops(vals, prod, i, pass_args)
    let args <- [for (j in vals.values[i]); "bison`a{j}"; where pass_args]
    var reduce <- make_reduce(spec, vals, i, lhs, args, at)
    let tprod = i + 1
    var head <- qmacro_block_to_array() {
        bison`states |> resize(length(bison`states) - $v(nrhs))
    }
    var tail <- qmacro_block_to_array() {
        bison`states |> push($i(g_goto)[bison`states[length(bison`states) - 1] * $v(nrules) + $v(lhs)])
        continue
    }
    var arm = qmacro_block() {
        if (bison`prod == $v(tprod)) {
        }
    }
    var then_blk = ((arm as ExprBlock).list[0] as ExprIfThenElse).if_true as ExprBlock
    for (part in [head, pops, reduce, tail]) {
        for (e in part) {
            then_blk.list |> push(e)
        }
    }
    return arm
}

//! the parser function's body: the value stacks, then the loop that reads a token when it needs
//! one and shifts, reduces, accepts or fails on the table's action
[arch(at="../ARCHITECTURE.md#macro-driver")]
def private make_driver(spec : BisonSpec; g : TextGrammar; t : LalrTables; vals : BisonValues;
                        lexer : string; result_type : TypeDeclPtr; at : LineInfo) : ExpressionPtr {
    let p = spec.param
    let f = spec.func_name
    let g_action = "{f}`bison`action"
    let g_goto = "{f}`bison`goto"
    let g_kind_terms = "{f}`bison`kind_terms"
    let g_names = "{f}`bison`names"
    let g_lhs = "{f}`bison`lhs"
    let g_len = "{f}`bison`len"
    let root_stack = stack_name(g.root)
    var stacks <- make_stacks(spec, vals, at)
    var checks <- make_type_checks(spec, g, vals)
    var arms <- [for (i in range(length(spec.rules))); make_arm(spec, g, vals, i, t.nrules, g_goto)]
    var rtype <- clone_type(result_type)
    var head <- qmacro_block_to_array() {
        var bison`none : $t(rtype)
        var bison`states : array<int>
        var bison`toks : array<FlexToken>
        var bison`saved : array<int>
    }
    var run <- qmacro_block_to_array() {
        bison`states |> push(0)
        var bison`term = -1
        var bison`reduces = 0
        var bison`low = 0
        while (true) {
            if (bison`term == -1) {
                if ($c(lexer)($i(p).lexer)) {
                    bison`term = bison_terminal($i(g_kind_terms), $i(p).lexer.tok.kind)
                } elif ($i(p).lexer.failed) {
                    bison_lexer_failed($i(p))
                    return <- bison`none
                } else {
                    bison`term = $v(t.eof)
                }
                bison`low = length(bison`states)
                bison`saved |> clear()
            }
            let bison`top = bison`states[length(bison`states) - 1]
            let bison`act = bison`term >= 0 ? $i(g_action)[bison`top * $v(t.nterms) + bison`term] : 0
            if (bison`act > 0 && bison`act != $v(LALR_ACCEPT)) {
                bison`states |> push(bison`act - 1)
                bison`toks |> push($i(p).lexer.tok)
                bison`term = -1
                bison`reduces = 0
                continue
            }
            if (bison`act == $v(LALR_ACCEPT)) {
                var bison`root = bison_pop($i(root_stack))
                return <- bison`root
            }
            if (bison`act == 0 || bison`reduces >= $v(LR_MAX_REDUCES)) {
                bison_syntax_error($i(p), $i(g_names), bison`term, $v(t.eof),
                                   bison_expected($i(g_action), $i(g_goto), $i(g_lhs), $i(g_len),
                                                  $v(t.nterms), $v(t.nrules),
                                                  bison`states, bison`low, bison`saved))
                return <- bison`none
            }
            bison`reduces++
            let bison`prod = -1 - bison`act
            let bison`depth = length(bison`states) - $i(g_len)[bison`prod]
            while (bison`low > bison`depth) {
                bison`low--
                bison`saved |> push(bison`states[bison`low])
            }
            $b(arms)
        }
    }
    var body : ExpressionPtr = new ExprBlock(at = at)
    for (part in [head, stacks, checks, run]) {
        for (e in part) {
            (body as ExprBlock).list |> push(e)
        }
    }
    force_generated(body, true)
    return body
}

//! the annotation's string argument `name`, or `absent`
def private string_arg(args : AnnotationArgumentList; name, absent : string) : string {
    let arg = find_arg(args, name)
    return arg is tString ? arg as tString : absent
}

//! The annotation's arguments: the token enum, the lexer, and `expected` (-1 when absent).
struct private BisonArgs {
    tokens : string
    lexer : string
    expected : int
    err : string
}

//! the annotation's arguments; `err` when `tokens` or `lexer` is missing or `expected` is not an
//! int of 0 or more
def private bison_args(args : AnnotationArgumentList) : BisonArgs {
    var ba = BisonArgs(tokens = string_arg(args, "tokens", ""),
                       lexer = string_arg(args, "lexer", ""))
    let expected_arg = find_arg(args, "expected")
    ba.expected = expected_arg is tInt ? expected_arg as tInt : -1
    if (empty(ba.tokens) || empty(ba.lexer)) {
        ba.err = "[bison] needs tokens = <the token enum> and lexer = <the [flex] function>"
    } elif (!(expected_arg is nothing) && ba.expected < 0) {
        ba.err = "[bison] expected = N takes the number of shift/reduce conflicts, an int of 0 or more"
    }
    return ba
}

//! enum `name` as the compiling module sees it: its own, else the one module it requires (directly
//! or through a public require) that declares it; `err` when none or several do
def private visible_enum(name : string) : tuple<en : Enumeration?; err : string> {
    let here = compiling_module()
    var en : Enumeration? = here |> module_find_enumeration(name)
    return (en = en, err = "") if (en != null)
    var inscope owners : array<string>
    for_each_module(get_ptr(compiling_program())) $(m) {
        if (m != here && is_visible_directly(here, m)) {
            var found : Enumeration? = m |> module_find_enumeration(name)
            if (found != null) {
                en = found
                owners |> push(string(m.name))
            }
        }
    }
    if (length(owners) > 1) {
        return (en = null,
                err = "[bison] tokens = {name}: ambiguous, an enum of {join(owners, " and ")}")
    }
    return (en = en,
            err = en == null ? "[bison] tokens = {name}: no such enum the module sees" : "")
}

//! the members of enum `name` and their values, the token kinds; `err` when the module sees no
//! such enum or several, or a member's value is not a constant the parse gives
def private enum_kinds(name : string) : tuple<by_name : table<string; int>; err : string> {
    var res : tuple<by_name : table<string; int>; err : string>
    let vis = visible_enum(name)
    if (vis.en == null) {
        res.err = vis.err
        return <- res
    }
    let en = vis.en
    var next = 0l
    for (e in en.list) {
        var v = next
        if (e.value != null) {
            let lit = integer_literal(e.value)
            if (!lit.ok) {
                res.err = "[bison] tokens = {name}: the value of {e.name} is not an integer literal"
                return <- res
            }
            v = lit.value
        }
        if (v < -2147483648l || v > 2147483647l) {
            res.err = "[bison] tokens = {name}: {e.name} = {v} does not fit a token kind, an int"
            return <- res
        }
        res.by_name[string(e.name)] = int(v)
        next = v + 1l
    }
    return <- res
}

//! the value of an integer literal of any width or sign, `-` before one included
def private integer_literal(e : Expression const?) : tuple<ok : bool; value : int64> {
    if (e is ExprOp1 && (e as ExprOp1).op == "-") {
        let inner = integer_literal((e as ExprOp1).subexpr)
        return (ok = inner.ok, value = -inner.value)
    }
    return (ok = true, value = int64((e as ExprConstInt).value)) if (e is ExprConstInt)
    return (ok = true, value = int64((e as ExprConstInt8).value)) if (e is ExprConstInt8)
    return (ok = true, value = int64((e as ExprConstInt16).value)) if (e is ExprConstInt16)
    return (ok = true, value = (e as ExprConstInt64).value) if (e is ExprConstInt64)
    return (ok = true, value = int64((e as ExprConstUInt).value)) if (e is ExprConstUInt)
    return (ok = true, value = int64((e as ExprConstUInt8).value)) if (e is ExprConstUInt8)
    return (ok = true, value = int64((e as ExprConstUInt16).value)) if (e is ExprConstUInt16)
    return (ok = true, value = int64((e as ExprConstUInt64).value)) if (e is ExprConstUInt64)
    return (ok = false, value = 0l)
}

//! a failure that belongs to one call is reported at its line; the annotation fails with a pointer to it
def private fail_rule(msg : string; site : Expression const?; var errors : das_string) : bool {
    if (site == null) {
        errors := msg
        return false
    }
    compiling_program() |> macro_error(site.at, msg)
    errors := "line {int(site.at.line)}: {msg}"
    return false
}

//! the largest token kind a grammar may use: the kind map is an array indexed by kind
let private BISON_MAX_KIND = 65535

//! the private globals the driver reads: the tables, the kind map, the terminal names, and the
//! left-hand side and length of every table production
def private add_tables(spec : BisonSpec; g : TextGrammar; t : LalrTables; at : LineInfo;
                       var errors : das_string) : bool {
    let f = spec.func_name
    var max_kind = -1
    for (k in g.term_kinds) {
        max_kind = max(max_kind, k)
    }
    if (max_kind < 0) {
        let msg = "[bison] the grammar names no token: a parser reads at least one named or quoted token"
        return fail_rule(msg, spec.rules[0].site, errors)
    }
    if (max_kind > BISON_MAX_KIND) {
        errors := "[bison] token kind {max_kind} is past {BISON_MAX_KIND}, the largest the kind map holds"
        return false
    }
    var kind_terms : array<int>
    kind_terms |> resize(max_kind + 1)
    for (k in kind_terms) {
        k = -2
    }
    for (term, k in count(), g.term_kinds) {
        if (k >= 0) {
            kind_terms[k] = term
        }
    }
    var names := t.term_names
    names[t.eof] = "end of input"
    let lhs <- [for (pr in t.prods); pr.lhs]
    let len <- [for (pr in t.prods); length(pr.rhs)]
    return (table_global("{f}`bison`action", t.action, at, errors)
        && table_global("{f}`bison`goto", t.goto_nt, at, errors)
        && table_global("{f}`bison`kind_terms", kind_terms, at, errors)
        && table_global("{f}`bison`names", names, at, errors)
        && table_global("{f}`bison`lhs", lhs, at, errors)
        && table_global("{f}`bison`len", len, at, errors))
}

[function_macro(name="bison")]
class BisonMacro : AstFunctionAnnotation {
    def override apply(var func : FunctionPtr; var group : ModuleGroup;
                       var args : AnnotationArgumentList;
                       var errors : das_string) : bool {
        if (length(func.arguments) != 1) {
            errors := "[bison] takes one argument: var p : Parser"
            return false
        }
        let ba = bison_args(args)
        if (!empty(ba.err)) {
            errors := ba.err
            return false
        }
        let lexer = ba.lexer
        let expected = ba.expected
        let tk = enum_kinds(ba.tokens)
        if (!empty(tk.err)) {
            errors := tk.err
            return false
        }
        var spec = BisonSpec(func_name = string(func.name), param = string(func.arguments[0].name))
        collect(spec, func.body as ExprBlock)
        return fail_rule(spec.err, spec.err_site, errors) if (!empty(spec.err))
        var inscope text_rules <- [for (r in spec.rules); TextRule(lhs = r.lhs, rhs = r.rhs)]
        var g <- grammar_from_text(text_rules, spec.precs, spec.root, tk.by_name)
        if (!empty(g.err)) {
            let prec_site = g.err_prec >= 0 ? spec.prec_sites[g.err_prec] : null
            let site = g.err_rule >= 0 ? spec.rules[g.err_rule].site : prec_site
            return fail_rule("[bison] {g.err}", site, errors)
        }
        let built <- build_lalr(g.builder, g.root)
        if (!empty(built.err)) {
            let rule = g.builder.rule_index?[built.err_rule] ?? -1
            let at_rule = find_index_if(g.builder.prods) $(pr) => pr.lhs == rule
            return fail_rule("[bison] {built.err}", at_rule >= 0 ? spec.rules[at_rule].site : null,
                             errors)
        }
        let res <- resolve_precedence(built, g.builder)
        let warning = conflict_warning(spec.func_name, res.report, expected)
        if (!empty(warning)) {
            to_log(LOG_WARNING, "{func.at.fileInfo.name}:{int(func.at.line)}: {warning}")
        }
        let vals <- plan_values(spec, g)
        return fail_rule(spec.err, spec.err_site, errors) if (!empty(spec.err))
        if (!vals.rule_yields[g.root]) {
            errors := "[bison] the root rule '{g.builder.rule_names[g.root]}' yields no value"
            return false
        }
        return false if (!add_tables(spec, g, res.tables, func.at, errors))
        for (i, r in count(), spec.rules) {
            continue if (r.action == null)
            return false if (!add_action(spec, i, func.arguments[0]._type, errors))
        }
        func.body = make_driver(spec, g, res.tables, vals, lexer, func.result, func.at)
        return true
    }
}

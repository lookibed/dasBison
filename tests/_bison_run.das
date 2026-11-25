options gen2
options indenting = 4

module _bison_run shared public

require bison/bison_parser

//! runs the `[bison]` parser `parse` over `src` read as `calc.txt`: its value, or on a failure the
//! error text after the default value the parser returned
def run_parser(parse : function<(var p : Parser) : float>; src : string) : string {
    var p : Parser
    parser_open(p, src, "calc.txt")
    let v = invoke(parse, p)
    return p.failed ? "{v} {p.err}" : "{v}"
}

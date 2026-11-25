options gen2
options indenting = 4

// Parse preprocessed C11 files (`gcc -E` output) with the [bison] C11 grammar of `c11_parser`:
// prints `path: accepted, N tokens, M typedefs` per file, or the error with its position.
//
// Run: daslang -load_module <dasBison> -load_module <dasFlex> examples/c11/parse_c11.das -- files.i...

require c11_parser
require daslib/fio

[export]
def main() {
    var failed = false
    let args <- get_command_line_arguments()
    let dashdash = find_index(args, "--")
    for (path in args[dashdash + 1..length(args)]) {
        var src = ""
        fopen(path, "rb") $(f) {
            if (f != null) {
                src = fread(f)
            }
        }
        let res = parse_c11(src, path)
        if (res.accepted) {
            print("{path}: accepted, {c11_token_count(src)} tokens, {res.typedefs} typedefs\n")
        } else {
            print("{res.err}\n")
            failed = true
        }
    }
    unsafe {
        fio::exit(failed ? 1 : 0)
    }
}

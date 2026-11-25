options gen2
options indenting = 4

module _compile_issues shared public

require daslib/ast
require daslib/rtti
require dastest/testing_boost
require strings

//! a source file the compile reads from memory: its path and its text
typedef VirtualFile = tuple<name : string; text : string>

//! compiles `text` as the virtual file `name`; "" when it compiled clean, the issue text otherwise
def compile_issues(name, text : string) : string {
    let none : array<VirtualFile>
    return compile_issues(name, text, none)
}

//! compiles `text` as the virtual file `name` beside the virtual files `others` it may require
def compile_issues(name, text : string; others : array<VirtualFile>) : string {
    var out = ""
    var inscope access <- make_file_access("")
    for (f in others) {
        set_file_source(access, f.name, f.text)
    }
    set_file_source(access, name, text)
    using() $(var mg : ModuleGroup) {
        using() $(var cop : CodeOfPolicies) {
            compile_file(name, access, unsafe(addr(mg)), cop) $(ok; _program; issues) {
                out = ok ? "" : string(issues)
            }
        }
    }
    return out
}

//! `issues` holds `text`; the failure shows every issue
def has_issue(t : T?; issues, text : string) {
    t |> success(find(issues, text) >= 0, issues)
}

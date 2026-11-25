options gen2
options indenting = 4

module _compile_issues shared public

require daslib/ast
require daslib/rtti
require dastest/testing_boost
require strings

//! compiles `text` as the virtual file `name`; "" when it compiled clean, the issue text otherwise
def compile_issues(name, text : string) : string {
    var out = ""
    var inscope access <- make_file_access("")
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

options gen2
options indenting = 4
options _function_length = 0   // build_c11 is one generated production list
module _grammar_c11 shared public
require bison/bytes

//! generated from the C11 yacc grammar (Degener 2012 revision of Jeff Lee 1985): one byte per terminal
//! named tokens 128..200 in %token order, single-character tokens as their ASCII byte
let TOKEN_NAMES <- ["IDENTIFIER", "I_CONSTANT", "F_CONSTANT", "STRING_LITERAL", "FUNC_NAME",
                    "SIZEOF", "PTR_OP", "INC_OP", "DEC_OP", "LEFT_OP", "RIGHT_OP", "LE_OP", "GE_OP",
    "EQ_OP", "NE_OP", "AND_OP", "OR_OP", "MUL_ASSIGN", "DIV_ASSIGN", "MOD_ASSIGN", "ADD_ASSIGN",
    "SUB_ASSIGN", "LEFT_ASSIGN", "RIGHT_ASSIGN", "AND_ASSIGN", "XOR_ASSIGN", "OR_ASSIGN",
    "TYPEDEF_NAME", "ENUMERATION_CONSTANT", "TYPEDEF", "EXTERN", "STATIC", "AUTO", "REGISTER",
    "INLINE", "CONST", "RESTRICT", "VOLATILE", "BOOL", "CHAR", "SHORT", "INT", "LONG", "SIGNED",
    "UNSIGNED", "FLOAT", "DOUBLE", "VOID", "COMPLEX", "IMAGINARY", "STRUCT", "UNION", "ENUM",
    "ELLIPSIS", "CASE", "DEFAULT", "IF", "ELSE", "SWITCH", "WHILE", "DO", "FOR", "GOTO", "CONTINUE",
    "BREAK", "RETURN", "ALIGNAS", "ALIGNOF", "ATOMIC", "GENERIC", "NORETURN", "STATIC_ASSERT",
    "THREAD_LOCAL"]

def c11_token_id(name : string) : int {
    for (i, n in count(), TOKEN_NAMES) {
        if (n == name) {
            return 128 + i
        }
    }
    return -1
}

def build_c11(var gb : GrammarBuilder) : int {
    let r_primary_expression = rule_id(gb, "primary_expression")
    let r_constant = rule_id(gb, "constant")
    let r_enumeration_constant = rule_id(gb, "enumeration_constant")
    let r_string = rule_id(gb, "string")
    let r_generic_selection = rule_id(gb, "generic_selection")
    let r_generic_assoc_list = rule_id(gb, "generic_assoc_list")
    let r_generic_association = rule_id(gb, "generic_association")
    let r_postfix_expression = rule_id(gb, "postfix_expression")
    let r_argument_expression_list = rule_id(gb, "argument_expression_list")
    let r_unary_expression = rule_id(gb, "unary_expression")
    let r_unary_operator = rule_id(gb, "unary_operator")
    let r_cast_expression = rule_id(gb, "cast_expression")
    let r_multiplicative_expression = rule_id(gb, "multiplicative_expression")
    let r_additive_expression = rule_id(gb, "additive_expression")
    let r_shift_expression = rule_id(gb, "shift_expression")
    let r_relational_expression = rule_id(gb, "relational_expression")
    let r_equality_expression = rule_id(gb, "equality_expression")
    let r_and_expression = rule_id(gb, "and_expression")
    let r_exclusive_or_expression = rule_id(gb, "exclusive_or_expression")
    let r_inclusive_or_expression = rule_id(gb, "inclusive_or_expression")
    let r_logical_and_expression = rule_id(gb, "logical_and_expression")
    let r_logical_or_expression = rule_id(gb, "logical_or_expression")
    let r_conditional_expression = rule_id(gb, "conditional_expression")
    let r_assignment_expression = rule_id(gb, "assignment_expression")
    let r_assignment_operator = rule_id(gb, "assignment_operator")
    let r_expression = rule_id(gb, "expression")
    let r_constant_expression = rule_id(gb, "constant_expression")
    let r_declaration = rule_id(gb, "declaration")
    let r_declaration_specifiers = rule_id(gb, "declaration_specifiers")
    let r_init_declarator_list = rule_id(gb, "init_declarator_list")
    let r_init_declarator = rule_id(gb, "init_declarator")
    let r_storage_class_specifier = rule_id(gb, "storage_class_specifier")
    let r_type_specifier = rule_id(gb, "type_specifier")
    let r_struct_or_union_specifier = rule_id(gb, "struct_or_union_specifier")
    let r_struct_or_union = rule_id(gb, "struct_or_union")
    let r_struct_declaration_list = rule_id(gb, "struct_declaration_list")
    let r_struct_declaration = rule_id(gb, "struct_declaration")
    let r_specifier_qualifier_list = rule_id(gb, "specifier_qualifier_list")
    let r_struct_declarator_list = rule_id(gb, "struct_declarator_list")
    let r_struct_declarator = rule_id(gb, "struct_declarator")
    let r_enum_specifier = rule_id(gb, "enum_specifier")
    let r_enumerator_list = rule_id(gb, "enumerator_list")
    let r_enumerator = rule_id(gb, "enumerator")
    let r_atomic_type_specifier = rule_id(gb, "atomic_type_specifier")
    let r_type_qualifier = rule_id(gb, "type_qualifier")
    let r_function_specifier = rule_id(gb, "function_specifier")
    let r_alignment_specifier = rule_id(gb, "alignment_specifier")
    let r_declarator = rule_id(gb, "declarator")
    let r_direct_declarator = rule_id(gb, "direct_declarator")
    let r_pointer = rule_id(gb, "pointer")
    let r_type_qualifier_list = rule_id(gb, "type_qualifier_list")
    let r_parameter_type_list = rule_id(gb, "parameter_type_list")
    let r_parameter_list = rule_id(gb, "parameter_list")
    let r_parameter_declaration = rule_id(gb, "parameter_declaration")
    let r_identifier_list = rule_id(gb, "identifier_list")
    let r_type_name = rule_id(gb, "type_name")
    let r_abstract_declarator = rule_id(gb, "abstract_declarator")
    let r_direct_abstract_declarator = rule_id(gb, "direct_abstract_declarator")
    let r_initializer = rule_id(gb, "initializer")
    let r_initializer_list = rule_id(gb, "initializer_list")
    let r_designation = rule_id(gb, "designation")
    let r_designator_list = rule_id(gb, "designator_list")
    let r_designator = rule_id(gb, "designator")
    let r_static_assert_declaration = rule_id(gb, "static_assert_declaration")
    let r_statement = rule_id(gb, "statement")
    let r_labeled_statement = rule_id(gb, "labeled_statement")
    let r_compound_statement = rule_id(gb, "compound_statement")
    let r_block_item_list = rule_id(gb, "block_item_list")
    let r_block_item = rule_id(gb, "block_item")
    let r_expression_statement = rule_id(gb, "expression_statement")
    let r_selection_statement = rule_id(gb, "selection_statement")
    let r_iteration_statement = rule_id(gb, "iteration_statement")
    let r_jump_statement = rule_id(gb, "jump_statement")
    let r_translation_unit = rule_id(gb, "translation_unit")
    let r_external_declaration = rule_id(gb, "external_declaration")
    let r_function_definition = rule_id(gb, "function_definition")
    let r_declaration_list = rule_id(gb, "declaration_list")
    add_production(gb, r_primary_expression, [sym_byte(128)])
    add_production(gb, r_primary_expression, [sym_rule(r_constant)])
    add_production(gb, r_primary_expression, [sym_rule(r_string)])
    add_production(gb, r_primary_expression, [sym_byte(40), sym_rule(r_expression), sym_byte(41)])
    add_production(gb, r_primary_expression, [sym_rule(r_generic_selection)])
    add_production(gb, r_constant, [sym_byte(129)])
    add_production(gb, r_constant, [sym_byte(130)])
    add_production(gb, r_constant, [sym_byte(156)])
    add_production(gb, r_enumeration_constant, [sym_byte(128)])
    add_production(gb, r_string, [sym_byte(131)])
    add_production(gb, r_string, [sym_byte(132)])
    add_production(gb, r_generic_selection,
                   [sym_byte(197), sym_byte(40), sym_rule(r_assignment_expression), sym_byte(44),
                    sym_rule(r_generic_assoc_list), sym_byte(41)])
    add_production(gb, r_generic_assoc_list, [sym_rule(r_generic_association)])
    add_production(gb, r_generic_assoc_list,
                   [sym_rule(r_generic_assoc_list), sym_byte(44), sym_rule(r_generic_association)])
    add_production(gb, r_generic_association,
                   [sym_rule(r_type_name), sym_byte(58), sym_rule(r_assignment_expression)])
    add_production(gb, r_generic_association,
                   [sym_byte(183), sym_byte(58), sym_rule(r_assignment_expression)])
    add_production(gb, r_postfix_expression, [sym_rule(r_primary_expression)])
    add_production(gb, r_postfix_expression,
                   [sym_rule(r_postfix_expression), sym_byte(91), sym_rule(r_expression),
                    sym_byte(93)])
    add_production(gb, r_postfix_expression,
                   [sym_rule(r_postfix_expression), sym_byte(40), sym_byte(41)])
    add_production(gb, r_postfix_expression,
                   [sym_rule(r_postfix_expression), sym_byte(40),
                    sym_rule(r_argument_expression_list), sym_byte(41)])
    add_production(gb, r_postfix_expression,
                   [sym_rule(r_postfix_expression), sym_byte(46), sym_byte(128)])
    add_production(gb, r_postfix_expression,
                   [sym_rule(r_postfix_expression), sym_byte(134), sym_byte(128)])
    add_production(gb, r_postfix_expression, [sym_rule(r_postfix_expression), sym_byte(135)])
    add_production(gb, r_postfix_expression, [sym_rule(r_postfix_expression), sym_byte(136)])
    add_production(gb, r_postfix_expression,
                   [sym_byte(40), sym_rule(r_type_name), sym_byte(41), sym_byte(123),
                    sym_rule(r_initializer_list), sym_byte(125)])
    add_production(gb, r_postfix_expression,
                   [sym_byte(40), sym_rule(r_type_name), sym_byte(41), sym_byte(123),
                    sym_rule(r_initializer_list), sym_byte(44), sym_byte(125)])
    add_production(gb, r_argument_expression_list, [sym_rule(r_assignment_expression)])
    add_production(gb, r_argument_expression_list,
                   [sym_rule(r_argument_expression_list), sym_byte(44),
                    sym_rule(r_assignment_expression)])
    add_production(gb, r_unary_expression, [sym_rule(r_postfix_expression)])
    add_production(gb, r_unary_expression, [sym_byte(135), sym_rule(r_unary_expression)])
    add_production(gb, r_unary_expression, [sym_byte(136), sym_rule(r_unary_expression)])
    add_production(gb, r_unary_expression,
                   [sym_rule(r_unary_operator), sym_rule(r_cast_expression)])
    add_production(gb, r_unary_expression, [sym_byte(133), sym_rule(r_unary_expression)])
    add_production(gb, r_unary_expression,
                   [sym_byte(133), sym_byte(40), sym_rule(r_type_name), sym_byte(41)])
    add_production(gb, r_unary_expression,
                   [sym_byte(195), sym_byte(40), sym_rule(r_type_name), sym_byte(41)])
    add_production(gb, r_unary_operator, [sym_byte(38)])
    add_production(gb, r_unary_operator, [sym_byte(42)])
    add_production(gb, r_unary_operator, [sym_byte(43)])
    add_production(gb, r_unary_operator, [sym_byte(45)])
    add_production(gb, r_unary_operator, [sym_byte(126)])
    add_production(gb, r_unary_operator, [sym_byte(33)])
    add_production(gb, r_cast_expression, [sym_rule(r_unary_expression)])
    add_production(gb, r_cast_expression,
                   [sym_byte(40), sym_rule(r_type_name), sym_byte(41), sym_rule(r_cast_expression)])
    add_production(gb, r_multiplicative_expression, [sym_rule(r_cast_expression)])
    add_production(gb, r_multiplicative_expression,
                   [sym_rule(r_multiplicative_expression), sym_byte(42),
                    sym_rule(r_cast_expression)])
    add_production(gb, r_multiplicative_expression,
                   [sym_rule(r_multiplicative_expression), sym_byte(47),
                    sym_rule(r_cast_expression)])
    add_production(gb, r_multiplicative_expression,
                   [sym_rule(r_multiplicative_expression), sym_byte(37),
                    sym_rule(r_cast_expression)])
    add_production(gb, r_additive_expression, [sym_rule(r_multiplicative_expression)])
    add_production(gb, r_additive_expression,
                   [sym_rule(r_additive_expression), sym_byte(43),
                    sym_rule(r_multiplicative_expression)])
    add_production(gb, r_additive_expression,
                   [sym_rule(r_additive_expression), sym_byte(45),
                    sym_rule(r_multiplicative_expression)])
    add_production(gb, r_shift_expression, [sym_rule(r_additive_expression)])
    add_production(gb, r_shift_expression,
                   [sym_rule(r_shift_expression), sym_byte(137), sym_rule(r_additive_expression)])
    add_production(gb, r_shift_expression,
                   [sym_rule(r_shift_expression), sym_byte(138), sym_rule(r_additive_expression)])
    add_production(gb, r_relational_expression, [sym_rule(r_shift_expression)])
    add_production(gb, r_relational_expression,
                   [sym_rule(r_relational_expression), sym_byte(60), sym_rule(r_shift_expression)])
    add_production(gb, r_relational_expression,
                   [sym_rule(r_relational_expression), sym_byte(62), sym_rule(r_shift_expression)])
    add_production(gb, r_relational_expression,
                   [sym_rule(r_relational_expression), sym_byte(139), sym_rule(r_shift_expression)])
    add_production(gb, r_relational_expression,
                   [sym_rule(r_relational_expression), sym_byte(140), sym_rule(r_shift_expression)])
    add_production(gb, r_equality_expression, [sym_rule(r_relational_expression)])
    add_production(gb, r_equality_expression,
                   [sym_rule(r_equality_expression), sym_byte(141),
                    sym_rule(r_relational_expression)])
    add_production(gb, r_equality_expression,
                   [sym_rule(r_equality_expression), sym_byte(142),
                    sym_rule(r_relational_expression)])
    add_production(gb, r_and_expression, [sym_rule(r_equality_expression)])
    add_production(gb, r_and_expression,
                   [sym_rule(r_and_expression), sym_byte(38), sym_rule(r_equality_expression)])
    add_production(gb, r_exclusive_or_expression, [sym_rule(r_and_expression)])
    add_production(gb, r_exclusive_or_expression,
                   [sym_rule(r_exclusive_or_expression), sym_byte(94), sym_rule(r_and_expression)])
    add_production(gb, r_inclusive_or_expression, [sym_rule(r_exclusive_or_expression)])
    add_production(gb, r_inclusive_or_expression,
                   [sym_rule(r_inclusive_or_expression), sym_byte(124),
                    sym_rule(r_exclusive_or_expression)])
    add_production(gb, r_logical_and_expression, [sym_rule(r_inclusive_or_expression)])
    add_production(gb, r_logical_and_expression,
                   [sym_rule(r_logical_and_expression), sym_byte(143),
                    sym_rule(r_inclusive_or_expression)])
    add_production(gb, r_logical_or_expression, [sym_rule(r_logical_and_expression)])
    add_production(gb, r_logical_or_expression,
                   [sym_rule(r_logical_or_expression), sym_byte(144),
                    sym_rule(r_logical_and_expression)])
    add_production(gb, r_conditional_expression, [sym_rule(r_logical_or_expression)])
    add_production(gb, r_conditional_expression,
                   [sym_rule(r_logical_or_expression), sym_byte(63), sym_rule(r_expression),
                    sym_byte(58), sym_rule(r_conditional_expression)])
    add_production(gb, r_assignment_expression, [sym_rule(r_conditional_expression)])
    add_production(gb, r_assignment_expression,
                   [sym_rule(r_unary_expression), sym_rule(r_assignment_operator),
                    sym_rule(r_assignment_expression)])
    add_production(gb, r_assignment_operator, [sym_byte(61)])
    add_production(gb, r_assignment_operator, [sym_byte(145)])
    add_production(gb, r_assignment_operator, [sym_byte(146)])
    add_production(gb, r_assignment_operator, [sym_byte(147)])
    add_production(gb, r_assignment_operator, [sym_byte(148)])
    add_production(gb, r_assignment_operator, [sym_byte(149)])
    add_production(gb, r_assignment_operator, [sym_byte(150)])
    add_production(gb, r_assignment_operator, [sym_byte(151)])
    add_production(gb, r_assignment_operator, [sym_byte(152)])
    add_production(gb, r_assignment_operator, [sym_byte(153)])
    add_production(gb, r_assignment_operator, [sym_byte(154)])
    add_production(gb, r_expression, [sym_rule(r_assignment_expression)])
    add_production(gb, r_expression,
                   [sym_rule(r_expression), sym_byte(44), sym_rule(r_assignment_expression)])
    add_production(gb, r_constant_expression, [sym_rule(r_conditional_expression)])
    add_production(gb, r_declaration, [sym_rule(r_declaration_specifiers), sym_byte(59)])
    add_production(gb, r_declaration,
                   [sym_rule(r_declaration_specifiers), sym_rule(r_init_declarator_list),
                    sym_byte(59)])
    add_production(gb, r_declaration, [sym_rule(r_static_assert_declaration)])
    add_production(gb, r_declaration_specifiers,
                   [sym_rule(r_storage_class_specifier), sym_rule(r_declaration_specifiers)])
    add_production(gb, r_declaration_specifiers, [sym_rule(r_storage_class_specifier)])
    add_production(gb, r_declaration_specifiers,
                   [sym_rule(r_type_specifier), sym_rule(r_declaration_specifiers)])
    add_production(gb, r_declaration_specifiers, [sym_rule(r_type_specifier)])
    add_production(gb, r_declaration_specifiers,
                   [sym_rule(r_type_qualifier), sym_rule(r_declaration_specifiers)])
    add_production(gb, r_declaration_specifiers, [sym_rule(r_type_qualifier)])
    add_production(gb, r_declaration_specifiers,
                   [sym_rule(r_function_specifier), sym_rule(r_declaration_specifiers)])
    add_production(gb, r_declaration_specifiers, [sym_rule(r_function_specifier)])
    add_production(gb, r_declaration_specifiers,
                   [sym_rule(r_alignment_specifier), sym_rule(r_declaration_specifiers)])
    add_production(gb, r_declaration_specifiers, [sym_rule(r_alignment_specifier)])
    add_production(gb, r_init_declarator_list, [sym_rule(r_init_declarator)])
    add_production(gb, r_init_declarator_list,
                   [sym_rule(r_init_declarator_list), sym_byte(44), sym_rule(r_init_declarator)])
    add_production(gb, r_init_declarator,
                   [sym_rule(r_declarator), sym_byte(61), sym_rule(r_initializer)])
    add_production(gb, r_init_declarator, [sym_rule(r_declarator)])
    add_production(gb, r_storage_class_specifier, [sym_byte(157)])
    add_production(gb, r_storage_class_specifier, [sym_byte(158)])
    add_production(gb, r_storage_class_specifier, [sym_byte(159)])
    add_production(gb, r_storage_class_specifier, [sym_byte(200)])
    add_production(gb, r_storage_class_specifier, [sym_byte(160)])
    add_production(gb, r_storage_class_specifier, [sym_byte(161)])
    add_production(gb, r_type_specifier, [sym_byte(175)])
    add_production(gb, r_type_specifier, [sym_byte(167)])
    add_production(gb, r_type_specifier, [sym_byte(168)])
    add_production(gb, r_type_specifier, [sym_byte(169)])
    add_production(gb, r_type_specifier, [sym_byte(170)])
    add_production(gb, r_type_specifier, [sym_byte(173)])
    add_production(gb, r_type_specifier, [sym_byte(174)])
    add_production(gb, r_type_specifier, [sym_byte(171)])
    add_production(gb, r_type_specifier, [sym_byte(172)])
    add_production(gb, r_type_specifier, [sym_byte(166)])
    add_production(gb, r_type_specifier, [sym_byte(176)])
    add_production(gb, r_type_specifier, [sym_byte(177)])
    add_production(gb, r_type_specifier, [sym_rule(r_atomic_type_specifier)])
    add_production(gb, r_type_specifier, [sym_rule(r_struct_or_union_specifier)])
    add_production(gb, r_type_specifier, [sym_rule(r_enum_specifier)])
    add_production(gb, r_type_specifier, [sym_byte(155)])
    add_production(gb, r_struct_or_union_specifier,
                   [sym_rule(r_struct_or_union), sym_byte(123), sym_rule(r_struct_declaration_list),
                    sym_byte(125)])
    add_production(gb, r_struct_or_union_specifier,
                   [sym_rule(r_struct_or_union), sym_byte(128), sym_byte(123),
                    sym_rule(r_struct_declaration_list), sym_byte(125)])
    add_production(gb, r_struct_or_union_specifier, [sym_rule(r_struct_or_union), sym_byte(128)])
    add_production(gb, r_struct_or_union, [sym_byte(178)])
    add_production(gb, r_struct_or_union, [sym_byte(179)])
    add_production(gb, r_struct_declaration_list, [sym_rule(r_struct_declaration)])
    add_production(gb, r_struct_declaration_list,
                   [sym_rule(r_struct_declaration_list), sym_rule(r_struct_declaration)])
    add_production(gb, r_struct_declaration, [sym_rule(r_specifier_qualifier_list), sym_byte(59)])
    add_production(gb, r_struct_declaration,
                   [sym_rule(r_specifier_qualifier_list), sym_rule(r_struct_declarator_list),
                    sym_byte(59)])
    add_production(gb, r_struct_declaration, [sym_rule(r_static_assert_declaration)])
    add_production(gb, r_specifier_qualifier_list,
                   [sym_rule(r_type_specifier), sym_rule(r_specifier_qualifier_list)])
    add_production(gb, r_specifier_qualifier_list, [sym_rule(r_type_specifier)])
    add_production(gb, r_specifier_qualifier_list,
                   [sym_rule(r_type_qualifier), sym_rule(r_specifier_qualifier_list)])
    add_production(gb, r_specifier_qualifier_list, [sym_rule(r_type_qualifier)])
    add_production(gb, r_struct_declarator_list, [sym_rule(r_struct_declarator)])
    add_production(gb, r_struct_declarator_list,
                   [sym_rule(r_struct_declarator_list), sym_byte(44),
                    sym_rule(r_struct_declarator)])
    add_production(gb, r_struct_declarator, [sym_byte(58), sym_rule(r_constant_expression)])
    add_production(gb, r_struct_declarator,
                   [sym_rule(r_declarator), sym_byte(58), sym_rule(r_constant_expression)])
    add_production(gb, r_struct_declarator, [sym_rule(r_declarator)])
    add_production(gb, r_enum_specifier,
                   [sym_byte(180), sym_byte(123), sym_rule(r_enumerator_list), sym_byte(125)])
    add_production(gb, r_enum_specifier,
                   [sym_byte(180), sym_byte(123), sym_rule(r_enumerator_list), sym_byte(44),
                    sym_byte(125)])
    add_production(gb, r_enum_specifier,
                   [sym_byte(180), sym_byte(128), sym_byte(123), sym_rule(r_enumerator_list),
                    sym_byte(125)])
    add_production(gb, r_enum_specifier,
                   [sym_byte(180), sym_byte(128), sym_byte(123), sym_rule(r_enumerator_list),
                    sym_byte(44), sym_byte(125)])
    add_production(gb, r_enum_specifier, [sym_byte(180), sym_byte(128)])
    add_production(gb, r_enumerator_list, [sym_rule(r_enumerator)])
    add_production(gb, r_enumerator_list,
                   [sym_rule(r_enumerator_list), sym_byte(44), sym_rule(r_enumerator)])
    add_production(gb, r_enumerator,
                   [sym_rule(r_enumeration_constant), sym_byte(61),
                    sym_rule(r_constant_expression)])
    add_production(gb, r_enumerator, [sym_rule(r_enumeration_constant)])
    add_production(gb, r_atomic_type_specifier,
                   [sym_byte(196), sym_byte(40), sym_rule(r_type_name), sym_byte(41)])
    add_production(gb, r_type_qualifier, [sym_byte(163)])
    add_production(gb, r_type_qualifier, [sym_byte(164)])
    add_production(gb, r_type_qualifier, [sym_byte(165)])
    add_production(gb, r_type_qualifier, [sym_byte(196)])
    add_production(gb, r_function_specifier, [sym_byte(162)])
    add_production(gb, r_function_specifier, [sym_byte(198)])
    add_production(gb, r_alignment_specifier,
                   [sym_byte(194), sym_byte(40), sym_rule(r_type_name), sym_byte(41)])
    add_production(gb, r_alignment_specifier,
                   [sym_byte(194), sym_byte(40), sym_rule(r_constant_expression), sym_byte(41)])
    add_production(gb, r_declarator, [sym_rule(r_pointer), sym_rule(r_direct_declarator)])
    add_production(gb, r_declarator, [sym_rule(r_direct_declarator)])
    add_production(gb, r_direct_declarator, [sym_byte(128)])
    add_production(gb, r_direct_declarator, [sym_byte(40), sym_rule(r_declarator), sym_byte(41)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(91), sym_byte(93)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(91), sym_byte(42), sym_byte(93)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(91), sym_byte(159),
                    sym_rule(r_type_qualifier_list), sym_rule(r_assignment_expression),
        sym_byte(93)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(91), sym_byte(159),
                    sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(91), sym_rule(r_type_qualifier_list),
                    sym_byte(42), sym_byte(93)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(91), sym_rule(r_type_qualifier_list),
                    sym_byte(159), sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(91), sym_rule(r_type_qualifier_list),
                    sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(91), sym_rule(r_type_qualifier_list),
                    sym_byte(93)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(91), sym_rule(r_assignment_expression),
                    sym_byte(93)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(40), sym_rule(r_parameter_type_list),
                    sym_byte(41)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(40), sym_byte(41)])
    add_production(gb, r_direct_declarator,
                   [sym_rule(r_direct_declarator), sym_byte(40), sym_rule(r_identifier_list),
                    sym_byte(41)])
    add_production(gb, r_pointer,
                   [sym_byte(42), sym_rule(r_type_qualifier_list), sym_rule(r_pointer)])
    add_production(gb, r_pointer, [sym_byte(42), sym_rule(r_type_qualifier_list)])
    add_production(gb, r_pointer, [sym_byte(42), sym_rule(r_pointer)])
    add_production(gb, r_pointer, [sym_byte(42)])
    add_production(gb, r_type_qualifier_list, [sym_rule(r_type_qualifier)])
    add_production(gb, r_type_qualifier_list,
                   [sym_rule(r_type_qualifier_list), sym_rule(r_type_qualifier)])
    add_production(gb, r_parameter_type_list,
                   [sym_rule(r_parameter_list), sym_byte(44), sym_byte(181)])
    add_production(gb, r_parameter_type_list, [sym_rule(r_parameter_list)])
    add_production(gb, r_parameter_list, [sym_rule(r_parameter_declaration)])
    add_production(gb, r_parameter_list,
                   [sym_rule(r_parameter_list), sym_byte(44), sym_rule(r_parameter_declaration)])
    add_production(gb, r_parameter_declaration,
                   [sym_rule(r_declaration_specifiers), sym_rule(r_declarator)])
    add_production(gb, r_parameter_declaration,
                   [sym_rule(r_declaration_specifiers), sym_rule(r_abstract_declarator)])
    add_production(gb, r_parameter_declaration, [sym_rule(r_declaration_specifiers)])
    add_production(gb, r_identifier_list, [sym_byte(128)])
    add_production(gb, r_identifier_list,
                   [sym_rule(r_identifier_list), sym_byte(44), sym_byte(128)])
    add_production(gb, r_type_name,
                   [sym_rule(r_specifier_qualifier_list), sym_rule(r_abstract_declarator)])
    add_production(gb, r_type_name, [sym_rule(r_specifier_qualifier_list)])
    add_production(gb, r_abstract_declarator,
                   [sym_rule(r_pointer), sym_rule(r_direct_abstract_declarator)])
    add_production(gb, r_abstract_declarator, [sym_rule(r_pointer)])
    add_production(gb, r_abstract_declarator, [sym_rule(r_direct_abstract_declarator)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_byte(40), sym_rule(r_abstract_declarator), sym_byte(41)])
    add_production(gb, r_direct_abstract_declarator, [sym_byte(91), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator, [sym_byte(91), sym_byte(42), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_byte(91), sym_byte(159), sym_rule(r_type_qualifier_list),
                    sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_byte(91), sym_byte(159), sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_byte(91), sym_rule(r_type_qualifier_list), sym_byte(159),
                    sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_byte(91), sym_rule(r_type_qualifier_list),
                    sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_byte(91), sym_rule(r_type_qualifier_list), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_byte(91), sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_rule(r_direct_abstract_declarator), sym_byte(91), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_rule(r_direct_abstract_declarator), sym_byte(91), sym_byte(42),
                    sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_rule(r_direct_abstract_declarator), sym_byte(91), sym_byte(159),
                    sym_rule(r_type_qualifier_list), sym_rule(r_assignment_expression),
        sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_rule(r_direct_abstract_declarator), sym_byte(91), sym_byte(159),
                    sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_rule(r_direct_abstract_declarator), sym_byte(91),
                    sym_rule(r_type_qualifier_list), sym_rule(r_assignment_expression),
        sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_rule(r_direct_abstract_declarator), sym_byte(91),
                    sym_rule(r_type_qualifier_list), sym_byte(159),
        sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_rule(r_direct_abstract_declarator), sym_byte(91),
                    sym_rule(r_type_qualifier_list), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_rule(r_direct_abstract_declarator), sym_byte(91),
                    sym_rule(r_assignment_expression), sym_byte(93)])
    add_production(gb, r_direct_abstract_declarator, [sym_byte(40), sym_byte(41)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_byte(40), sym_rule(r_parameter_type_list), sym_byte(41)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_rule(r_direct_abstract_declarator), sym_byte(40), sym_byte(41)])
    add_production(gb, r_direct_abstract_declarator,
                   [sym_rule(r_direct_abstract_declarator), sym_byte(40),
                    sym_rule(r_parameter_type_list), sym_byte(41)])
    add_production(gb, r_initializer, [sym_byte(123), sym_rule(r_initializer_list), sym_byte(125)])
    add_production(gb, r_initializer,
                   [sym_byte(123), sym_rule(r_initializer_list), sym_byte(44), sym_byte(125)])
    add_production(gb, r_initializer, [sym_rule(r_assignment_expression)])
    add_production(gb, r_initializer_list, [sym_rule(r_designation), sym_rule(r_initializer)])
    add_production(gb, r_initializer_list, [sym_rule(r_initializer)])
    add_production(gb, r_initializer_list,
                   [sym_rule(r_initializer_list), sym_byte(44), sym_rule(r_designation),
                    sym_rule(r_initializer)])
    add_production(gb, r_initializer_list,
                   [sym_rule(r_initializer_list), sym_byte(44), sym_rule(r_initializer)])
    add_production(gb, r_designation, [sym_rule(r_designator_list), sym_byte(61)])
    add_production(gb, r_designator_list, [sym_rule(r_designator)])
    add_production(gb, r_designator_list, [sym_rule(r_designator_list), sym_rule(r_designator)])
    add_production(gb, r_designator, [sym_byte(91), sym_rule(r_constant_expression), sym_byte(93)])
    add_production(gb, r_designator, [sym_byte(46), sym_byte(128)])
    add_production(gb, r_static_assert_declaration,
                   [sym_byte(199), sym_byte(40), sym_rule(r_constant_expression), sym_byte(44),
                    sym_byte(131), sym_byte(41), sym_byte(59)])
    add_production(gb, r_statement, [sym_rule(r_labeled_statement)])
    add_production(gb, r_statement, [sym_rule(r_compound_statement)])
    add_production(gb, r_statement, [sym_rule(r_expression_statement)])
    add_production(gb, r_statement, [sym_rule(r_selection_statement)])
    add_production(gb, r_statement, [sym_rule(r_iteration_statement)])
    add_production(gb, r_statement, [sym_rule(r_jump_statement)])
    add_production(gb, r_labeled_statement, [sym_byte(128), sym_byte(58), sym_rule(r_statement)])
    add_production(gb, r_labeled_statement,
                   [sym_byte(182), sym_rule(r_constant_expression), sym_byte(58),
                    sym_rule(r_statement)])
    add_production(gb, r_labeled_statement, [sym_byte(183), sym_byte(58), sym_rule(r_statement)])
    add_production(gb, r_compound_statement, [sym_byte(123), sym_byte(125)])
    add_production(gb, r_compound_statement,
                   [sym_byte(123), sym_rule(r_block_item_list), sym_byte(125)])
    add_production(gb, r_block_item_list, [sym_rule(r_block_item)])
    add_production(gb, r_block_item_list, [sym_rule(r_block_item_list), sym_rule(r_block_item)])
    add_production(gb, r_block_item, [sym_rule(r_declaration)])
    add_production(gb, r_block_item, [sym_rule(r_statement)])
    add_production(gb, r_expression_statement, [sym_byte(59)])
    add_production(gb, r_expression_statement, [sym_rule(r_expression), sym_byte(59)])
    add_production(gb, r_selection_statement,
                   [sym_byte(184), sym_byte(40), sym_rule(r_expression), sym_byte(41),
                    sym_rule(r_statement), sym_byte(185), sym_rule(r_statement)])
    add_production(gb, r_selection_statement,
                   [sym_byte(184), sym_byte(40), sym_rule(r_expression), sym_byte(41),
                    sym_rule(r_statement)])
    add_production(gb, r_selection_statement,
                   [sym_byte(186), sym_byte(40), sym_rule(r_expression), sym_byte(41),
                    sym_rule(r_statement)])
    add_production(gb, r_iteration_statement,
                   [sym_byte(187), sym_byte(40), sym_rule(r_expression), sym_byte(41),
                    sym_rule(r_statement)])
    add_production(gb, r_iteration_statement,
                   [sym_byte(188), sym_rule(r_statement), sym_byte(187), sym_byte(40),
                    sym_rule(r_expression), sym_byte(41), sym_byte(59)])
    add_production(gb, r_iteration_statement,
                   [sym_byte(189), sym_byte(40), sym_rule(r_expression_statement),
                    sym_rule(r_expression_statement), sym_byte(41), sym_rule(r_statement)])
    add_production(gb, r_iteration_statement,
                   [sym_byte(189), sym_byte(40), sym_rule(r_expression_statement),
                    sym_rule(r_expression_statement), sym_rule(r_expression), sym_byte(41),
        sym_rule(r_statement)])
    add_production(gb, r_iteration_statement,
                   [sym_byte(189), sym_byte(40), sym_rule(r_declaration),
                    sym_rule(r_expression_statement), sym_byte(41), sym_rule(r_statement)])
    add_production(gb, r_iteration_statement,
                   [sym_byte(189), sym_byte(40), sym_rule(r_declaration),
                    sym_rule(r_expression_statement), sym_rule(r_expression), sym_byte(41),
        sym_rule(r_statement)])
    add_production(gb, r_jump_statement, [sym_byte(190), sym_byte(128), sym_byte(59)])
    add_production(gb, r_jump_statement, [sym_byte(191), sym_byte(59)])
    add_production(gb, r_jump_statement, [sym_byte(192), sym_byte(59)])
    add_production(gb, r_jump_statement, [sym_byte(193), sym_byte(59)])
    add_production(gb, r_jump_statement, [sym_byte(193), sym_rule(r_expression), sym_byte(59)])
    add_production(gb, r_translation_unit, [sym_rule(r_external_declaration)])
    add_production(gb, r_translation_unit,
                   [sym_rule(r_translation_unit), sym_rule(r_external_declaration)])
    add_production(gb, r_external_declaration, [sym_rule(r_function_definition)])
    add_production(gb, r_external_declaration, [sym_rule(r_declaration)])
    add_production(gb, r_function_definition,
                   [sym_rule(r_declaration_specifiers), sym_rule(r_declarator),
                    sym_rule(r_declaration_list), sym_rule(r_compound_statement)])
    add_production(gb, r_function_definition,
                   [sym_rule(r_declaration_specifiers), sym_rule(r_declarator),
                    sym_rule(r_compound_statement)])
    add_production(gb, r_declaration_list, [sym_rule(r_declaration)])
    add_production(gb, r_declaration_list, [sym_rule(r_declaration_list), sym_rule(r_declaration)])
    return r_translation_unit
}

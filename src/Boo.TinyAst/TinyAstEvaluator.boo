﻿namespace Boo.TinyAst

import System
import Boo.OMeta
import Boo.OMeta.Parser
import Boo.Lang.Compiler
import Boo.Lang.Compiler.Ast
import Boo.Lang.Compiler.Ast as AST
import Boo.Lang.PatternMatching

macro keywordsAndTokens:
"""
Generates rules for tokens and keywords for TinyAst.

From:
	keywordsAndTokens:
		eq = "="
		OR = "or"
	
it generates:

	EQ = Identifier(Name: "=" >> name) ^ makeToken("EQ", name)
	OR = Identifier(Name: "or" >> name) ^ makeToken("OR", name)
"""
	block as AST.Block = keywordsAndTokens.ParentNode
	for stmt in keywordsAndTokens.Body.Statements:
		match stmt:
			case ExpressionStatement(Expression: [| $name = $pattern |]):
				e = [| $(ReferenceExpression(Name: name.ToString().ToUpper())) = Identifier(Name: $pattern >> name) ^ makeToken($(StringLiteralExpression(name.ToString().ToUpper())) , name) |]
				e.LexicalInfo = stmt.LexicalInfo
				block.Add(e)

ometa TinyAstEvaluator(compilerParameters as CompilerParameters):
	
	keywordsAndTokens:
		OR = "or"
		AND = "and"
		TRUE = "true"
		FALSE = "false"
		AS = "as"
		FOR = "for"
		WHILE = "while"
		UNLESS = "unless"
		IN = "in"
		NOT_IN = "not in"
		assign = "="
		OF = "of"
		IF = "if"
		NOT = "not"
		IS = "is"
		IS_NOT = "is not"
		increment = "++"
		decrement = "--"
		plus = "+"
		minus = "-"
		star = "*"
		division = "/"
		modulus = "%"
		assign_inplace = "+=" | "-=" | "*=" | "/=" | "%=" | "^=" | "&=" | "|=" | "<<=" | ">>="
		bitwise_shift_left = "<<"
		bitwise_shift_right = ">>"
		equality = "=="
		inequality = "!="
		greater_than_eq = ">="
		greater_than = ">"
		less_than_eq = "<="
		less_than = "<"
		ENUM = "enum"
		PASS = "pass"
		DEF = "def"
		CLASS = "class"
		CALLABLE = "callable"
		DOT = "."		
		PRIVATE = "private"
		PUBLIC = "public"
		INTERNAL = "internal"
		PROTECTED = "protected"
		FINAL = "final"
		STATIC = "static"
		VIRTUAL = "virtual"
		OVERRIDE = "override"
		TRANSIENT = "transient"
		ABSTRACT = "abstract"
		NEW = "new"
		EVENT = "event"
		GET = "get"
		SET = "set"
		RETURN = "return"
		THEN = "then"
		SPLICE_BEGIN = "$"

	expansion = module_member | stmt
	
	stmt = stmt_block | stmt_line
	
	module_member = assembly_attribute | type_def | method
	type_member_stmt = (type_def | method) >> tm ^ TypeMemberStatement(TypeMember: tm)

	type_def = class_def | enum_def | callable_def
	
	class_def = --attributes_line >> att, here >> i, class_body >> body, inline_attributes >> in_att, member_modifiers >> mod \
					, prefix[CLASS], id >> className, next[i] ^ newClass([att, in_att], mod, className, null, null, body)
	
	class_body = Pair(Left: _ >> newInput, Right: (Block(Forms: ( (empty_block ^ null) | ((++(class_member)) >> body, nothing)) ) ^ body) ), $(success(newInput, body)) 

	nothing = ~_

	class_member = type_def | method  | field | event_def | property_def | enum_def
	
	enum_def = --attributes_line >> att, here >> i, enum_body >> body, inline_attributes >> in_att, member_modifiers >> mod \
					, prefix[ENUM], id >> name, next[i] ^ newEnum([att, in_att], mod, name, body)
	
	enum_body = Pair(
						Left: _ >> newInput, \
						Right: (
							(empty_block ^ null) \
							| (Block(Forms: (++enum_field >> fields) ) ^ fields)
						) >> body
					), $(success(newInput, body)) 
	
	enum_field = --attributes_line >> att, here >> i, inline_attributes >> in_att, \
					(Infix(Operator:ASSIGN, Left: id >> name, Right: assignment >> e) | id >> name), next[i] ^ newEnumField([att, in_att], name, e)
	
	callable_def = here >> i, member_modifiers >> mod, prefix[CALLABLE], optional_type >> type, prefix[id] >> name, \
					method_parameters >> parameters, next[i] ^ newCallable(mod, name, null, parameters, type)
	
	
	method = (--attributes_line >> att, here >> i, method_body >> body, inline_attributes >> in_att, member_modifiers >> mod, \
				prefix[DEF], optional_type >> type, method_result_attributes >> ra, prefix[id] >> name, method_parameters >> parameters), next[i] ^ newGenericMethod([att, in_att], mod, name, null, parameters, ra, type, body)

	here = $(success(input, input))
	next[i] = $(success((i as OMetaInput).Tail, (i as OMetaInput).Tail))
	
	method_body = Pair(	Left: _ >> newInput, Right: (block >> body)), $(success(newInput, body))
	
	method_parameters = Brackets(Kind: BracketType.Parenthesis, Form: (method_parameter_list | ((_ >> p and (p is null)) ^ [null, null])) >> p) ^ p

	method_parameter_list = (parameter >> p ^ [[p], null]) \
							| (param_array >> pa ^ [null, pa]) \
							| (Tuple(Forms: (++parameter >> p, (param_array | "") >> pa, ~_)) ^ [p, pa])
			
	parameter = --attributes_line >> att, here >> i, inline_attributes >> in_att, optional_type >> type, id >> name, next[i] ^ newParameterDeclaration([att, in_att], name, type)
	param_array = --attributes_line >> att, inline_attributes >> in_att, optional_array_type >> type, prefix[STAR], id >> name ^ newParameterDeclaration([att, in_att], name, type)
	
	
	optional_array_type = (Infix(Operator: AS, Left: _ >> newInput, Right: type_reference_array >> e), $(success(newInput, e)) ) | ""
	
	method_result_attributes = (Prefix(Operator: _ >> newInput, Operand: inline_attributes >> attr and (len(attr) > 0)), $(success(newInput, attr))) | ""
	
	assembly_attribute = Brackets(Kind: BracketType.Square,
									Form: (
												(
													(assembly_attribute_first >> a ^ [a])
													| (	Tuple( Forms: (assembly_attribute_first >> a , ++attribute >> attr, ~_) ) ^ prepend(a, attr) ) 
												) >> attr
										
									) 
						) ^ attr
						
	assembly_attribute_first = Pair(Left: identifier["assembly"], Right: attribute >> a) ^ a
	
	field = --attributes_line >> att, here >> i, inline_attributes >> in_att, member_modifiers >> mod, field_initializer >> initializer \
				, optional_type >> type, id >> name, next[i] ^ newField([att, in_att], mod, name, type, initializer)
				
	event_def = --attributes_line >> att, here >> i, inline_attributes >> in_att, member_modifiers >> mod, optional_type >> type, prefix[EVENT], \
					optional_type >> type, id >> name, next[i] ^ newEvent([att, in_att], mod, name, type)


	property_def = --attributes_line >> att, here >> i, property_body >> gs, inline_attributes >> in_att, member_modifiers >> mod, \
						optional_type >> type, (id |prefix[id])  >> name, property_parameters >> params, next[i] ^ newProperty([att, in_att], mod, name, params, type, (gs as List)[0], (gs as List)[1]) /*TODO*/
						
	property_body = Pair(Left: _ >> newInput, Right: get_set >> gs), $(success(newInput, gs)) 
	
	property_parameters = Brackets(
									Kind: BracketType.Square, 
									Form: (
											Tuple(Forms: ((++parameter >> p, ~_) ^ p) )
											| (parameter >> p ^ [p]) 
											| ( (_ >> p and (p is null)) ^ [null])
									) >> p
							) ^ p | ""
	
	get_set = Block(Forms: (
							(property_getter >> pg, property_setter >> ps, ~_)
							| (property_setter >> ps, property_getter >> pg, ~_)
							| (property_setter >> ps, ~_)
							| (property_getter >> pg, ~_)
							)
					) ^ [pg, ps]
					
	property_getter = accessor[GET]
	property_setter = accessor[SET]


	accessor[key] = --attributes_line >> att, Pair(Left: (inline_attributes >> in_att, member_modifiers >> mod, key >> name), Right: (block) >> body) \
						^ newMethod([att, in_att], mod, tokenValue(name), [[],null], null, null, body)

	prefix[rule] = Prefix(Operator: rule >> e, Operand: _ >> newInput), $(success(newInput, e))
	
	inline_attributes = inline_attributes_prescan | ("" ^ [])
							
	inline_attributes_prescan = (Prefix(Operator: attributes_group >> l, Operand: (inline_attributes_prescan >> r, _ >> newInput)), $(success(newInput, prepend(l, r))) )\
							| (Prefix(Operator: attributes_group >> l, Operand: (~inline_attributes_prescan, _ >> newInput)), $(success(newInput, l)) )\
							| attributes_group

	def success(input, value):
		return SuccessfulMatch(input, value) if input isa OMetaInput
		return SuccessfulMatch(OMetaInput.Singleton(input), value)

	attributes_line =  Prefix(Operator: attributes_group >> l, Operand: attributes_line >> r) ^ prepend(l, r) | (attributes_group >> a ^ a)
	attributes_group = Brackets(Kind:BracketType.Square, Form: attribute_list >> attrs) ^ attrs
	
	attribute_list = Tuple(Forms: ++attribute >> a) ^ a | (attribute >> a ^ [a])
	
	attribute = (Prefix(Operator: qualified_name >> name, Operand: optional_invocation_arguments >> args) | qualified_name >> name) ^ newAttribute(name, args)
	
	member_modifiers = member_modifiers_prescan | ("" ^ [])
	
	member_modifiers_prescan = (Prefix(Operator: modifier >> l, Operand: (member_modifiers_prescan >> r, _ >> newInput)), $(success(newInput, prepend(l, r))) )\
						| (Prefix(Operator: modifier >> l, Operand: (~member_modifiers_prescan, _ >> newInput)), $(success(newInput, [l])) )
	
	modifier = (
				(PRIVATE ^ TypeMemberModifiers.Private) |
				(PUBLIC ^ TypeMemberModifiers.Public) |
				(INTERNAL ^ TypeMemberModifiers.Internal) |
				(PROTECTED ^ TypeMemberModifiers.Protected) | 
				(FINAL ^ TypeMemberModifiers.Final) | 
				(STATIC ^ TypeMemberModifiers.Static) | 
				(VIRTUAL ^ TypeMemberModifiers.Virtual) | 
				(OVERRIDE ^ TypeMemberModifiers.Override) | 
				(TRANSIENT ^ TypeMemberModifiers.Transient) | 
				(ABSTRACT ^ TypeMemberModifiers.Abstract) | 
				(NEW ^ TypeMemberModifiers.New)
			)
	
	field_initializer = (Infix(Operator: ASSIGN, Left: _ >> newInput, Right: assignment >> e), $(success(newInput, e)) )| ""
	
	optional_type = (Infix(Operator: AS, Left: _ >> newInput, Right: type_reference >> e), $(success(newInput, e)) )| ""
	
	id = Identifier(Name: _ >> name) ^ name
	
	identifier[n] = Identifier(Name: _ >> name and (name == n)) ^ name
	
	qualified_name = (Infix(Operator: DOT, Left: qualified_name >> l, Right: id >> r) ^ ("$l.$r")) | id
	
	stmt_line = stmt_declaration | stmt_expression | stmt_return | stmt_macro
	
	stmt_expression = assignment >> a ^ ExpressionStatement(a as Expression)
	stmt_block = stmt_if | stmt_for | stmt_while
	
	atom = reference | array_literal | list_literal | boolean | literal | parenthesized_expression | quasi_quote | splice_expression
	
	literal = (Literal(Value: _ >> f and (f isa string), Value: booparser_string_interpolation >> si) ^ si) | (Literal() >> l ^ (l as Literal).astLiteral)
	integer = Literal(Value: _ >> v and (v isa long)) >> l ^ (l as Literal).astLiteral
	
	splice_expression = prefix[SPLICE_BEGIN], atom >> e ^ SpliceExpression(Expression: e)
	
	string_interpolation = Literal(Value: _ >> f and (f isa string), Value: booparser_string_interpolation >> si) ^ si
	
	booparser_string_interpolation = $(callExternalParser("string_interpolation_items", "Boo.OMeta.Parser.BooParser", input)) >> items ^ newStringInterpolation(items)
	
	array_literal = array_literal_multi
	
	array_literal_multi = Brackets(Kind: BracketType.Parenthesis, 
									Form: (
										Tuple(Forms: array_literal_multi_items >> items) | 
										Prefix(Operator: OF, Operand: Tuple(Forms: (array_item_with_type >> type, array_literal_multi_items >> items) ))
									)
							) ^ newArrayLiteral(getArrayType(type), getArrayItmes(type, items))

	def getArrayType(type as List):
		return type[0] if type is not null
		
	def getArrayItmes(type as List, items):
		return items if type is null
		return prepend(type[1], items)


	#First item is a pair of array type and first item of array
	array_item_with_type = Pair(Left: type_reference >> type, Right: assignment >> a) ^ [ArrayTypeReference(ElementType: type, Rank: null), a]
	
	array_literal_type = Prefix(Operator: OF, Operand: type_reference >> type) ^ ArrayTypeReference(ElementType: type, Rank: null)
	
	array_literal_multi_items = (++assignment >> a, ~_) ^ a

	list_literal = Brackets(Kind: BracketType.Square,
								Form: (
									Tuple(Forms: ((++assignment >> a, ~_) ^ a) >> items)
								)
							) ^ newListLiteral(items)

	boolean = true_literal | false_literal
	
	true_literal = TRUE ^ [| true |]
	false_literal = FALSE ^ [| false |]
	
	parenthesized_expression = Brackets(Kind: BracketType.Parenthesis, Form: assignment >> e) ^ e
	
	binary_operator = OR | AND | ASSIGN_INPLACE | ASSIGN | IN | NOT_IN | IS | IS_NOT | PLUS | MINUS | STAR \
					| DIVISION | BITWISE_SHIFT_LEFT | BITWISE_SHIFT_RIGHT | GREATER_THAN_EQ | GREATER_THAN \
					| LESS_THAN_EQ | LESS_THAN | EQUALITY | INEQUALITY | MODULUS

	
	binary_expression = Infix(Operator: binary_operator >> op, Left: assignment >> l, Right: assignment >> r) ^ newInfixExpression(op, l, r)
	
	reference = id >> r ^ ReferenceExpression(Name: r)
	
	assignment = binary_expression | try_cast | prefix_expression | invocation | atom | member_reference | expression
	
	expression = generator_expression
	
	generator_expression = here >> i, prefix[assignment] >> projection, ++generator_expression_body >> body, nothing, next[i] ^ newGeneratorExpression(projection, body)	
	
	generator_expression_body = prefix[FOR], (declaration_list[IN] >> dl | Prefix(Operator: declaration_list[IN], Operand: filter >> f) ) \
							^ newGeneratorExpressionBody((dl cast List)[0], newRValue((dl cast List)[1]), f)
	
	filter = "" #TODO
	
	declaration_list[next_op] = Tuple(Forms: (--declaration >> left, Infix(Operator: next_op, Left: declaration >> l, Right: assignment >> r), --declaration >> right) ) \
								^ [prepend(left,[l]), prepend(r, right)] \
								| Infix(Operator: next_op, Left: declaration >> l, Right: assignment >> r) ^ [[l], [r]]

	try_cast = Infix(Operator: AS, Left: assignment >> e, Right: type_reference >> typeRef)  ^ TryCastExpression(Target: e, Type: typeRef)

	stmt_declaration = (typed_declaration >> d
						| Infix(Operator: ASSIGN, Left: typed_declaration >> d, Right: assignment >> e)) ^ newDeclarationStatement(d, e)
	
	typed_declaration = Infix(Operator: AS, Left: Identifier(Name: _ >> name), Right: type_reference >> typeRef) ^ newDeclaration(name, typeRef)
	
	declaration = optional_type >> typeRef, id >> name ^ newDeclaration(name, typeRef)		
	

	prefix_expression = Prefix(Operator: prefix_operator >> op, Operand: assignment >> e) ^ newPrefixExpression(op, e)
	prefix_operator = NOT | MINUS | INCREMENT | DECREMENT

	
	invocation = invocation_expression
	invocation_expression = here >> i, member_reference_left >> mr, Prefix(Operator: (reference | invocation | atom) >> target, Operand: invocation_arguments >> args) \
								, next[i] ^ newInvocation(getTarget(mr, target), args, null)
	
	def getTarget(l, r):
		return r if l is null
		return newMemberReference(l, (r as ReferenceExpression).Name)
	
	member_reference_left = (Infix(Operator: DOT, Left: member_reference >> e, Right: _ >> newInput), $(success(newInput, e))) | ""
	
	member_reference = Infix(Operator: DOT, Left: member_reference >> e, Right: id >> name) ^ newMemberReference(e, name) | (reference | invocation | invocation_expression | atom)
	
	invocation_arguments = Brackets(
								Kind: BracketType.Parenthesis,
								Form: (
										(Tuple(Forms: (++(invocation_argument) >> a, ~_) ) ^ a) \
										| (invocation_argument >> a ^ [a]) \
										| ((_ >> a and (a == null)) ^ [])
								) >> args
							) ^ args

	
	invocation_argument = named_argument | assignment
	
	named_argument = Pair(IsMultiline: _ >> ml and (ml == false), Left: id >> name, Right: assignment >> value) ^ newNamedArgument(name, value)
	
	optional_invocation_arguments = invocation_arguments | (~~_ ^ null)
	block = empty_block | (Block(Forms: (++(stmt >> s ^ getStatement(s)) >> a, nothing) ) ^ newBlock(null, null, a, null)) | (stmt >> s ^ newBlock(null, null, s, null))
	
	empty_block = Block(Forms: (PASS, ~_)) ^ AST.Block()
	
	
	stmt_for = Pair(Left:
						Prefix(Operator: FOR, Operand: declaration_list[IN] >> dl),
					Right:
						block >> body) ^ newForStatement((dl as List)[0], newRValue((dl as List)[1]), body, null, null)
						
	stmt_if = Pair(Left:
						Prefix(Operator: IF, Operand: assignment >> e),
					Right: 
						block >> trueBlock) ^ newIfStatement(e, trueBlock, null)
				
	stmt_while = Pair(Left: (prefix[WHILE], assignment >> e), Right: block >> body), or_block >> orBlock, then_block >> thenBlock ^ newWhileStatement(e, body, orBlock, thenBlock)
	
	or_block = Pair(Left: OR, Right: block >> orBlock) | "" ^ orBlock
	then_block = Pair(Left: THEN, Right: block >> thenBlock) | "" ^ thenBlock
	
	stmt_macro = (stmt_macro_head >> head | Pair(Left: stmt_macro_head >> head, Right: block >> b) ) ^ newMacro((head as List)[0], (head as List)[1], b, null)
	
	stmt_macro_head = Prefix(Operator: Identifier(Name: _ >> name), Operand: (optional_assignment_list >> args, ~_) ) ^ [name, args]
	
	stmt_return = (RETURN | Prefix(Operator: RETURN, Operand: (assignment >> e | (prefix[assignment] >> e, stmt_modifier >> m) ))) ^ ReturnStatement(Expression: e, Modifier: m)
	
	stmt_modifier = prefix[stmt_modifier_type] >> t, assignment >> e ^ newStatementModifier(t, e)
	
	stmt_modifier_type = (IF ^ StatementModifierType.If) | (UNLESS ^ StatementModifierType.Unless)
	
	optional_assignment_list = Tuple(Forms: (++assignment >> a, ~_)) ^ a | (assignment >> a ^ [a]) | ""
	
	type_reference = type_reference_simple | type_reference_array | type_reference_splice | type_reference_callable
	
	type_reference_simple = qualified_name >> name ^ SimpleTypeReference(Name: name)
	
	type_reference_splice = prefix[SPLICE_BEGIN], atom >> e ^ SpliceTypeReference(Expression: e)
	
	type_reference_array = Brackets(Kind: BracketType.Parenthesis, Form: ranked_type_reference >> tr)  ^ tr
	
	ranked_type_reference = (type_reference >> type) | Tuple(Forms: (type_reference >> type, integer >> rank)) ^ ArrayTypeReference(ElementType: type, Rank: rank)
	
	type_reference_callable = optional_type >> type, prefix[CALLABLE], \
								Brackets(Kind: BracketType.Parenthesis,
									Form: (
										(type_reference >> params)
										| (param_array_reference >> paramArray)
										| Tuple(
												Forms: (++type_reference >> params, (param_array_reference|"") >> paramArray, ~_)
											)									
									)								
								) ^ newCallableTypeReference((params if (params isa List) else [params]), paramArray, type)


	param_array_reference = here >> i, prefix[STAR], type_reference >> type, next[i] ^ newParameterDeclaration(null, "arg0", type)

	quasi_quote = quasi_quote_member | quasi_quote_module | quasi_quote_expression | quasi_quote_stmt
	
	quasi_quote_module = Brackets(Kind: BracketType.QQ, Form: Block(Forms: (--module_member >> members, --stmt >> stmts, ~_))) ^ newQuasiquoteExpression(newModule(null, null, [], members, stmts))
	
	quasi_quote_member = Brackets(Kind: BracketType.QQ, Form: Block(Forms: (class_member >> e, ~_))) ^ newQuasiquoteExpression(e)
	
	quasi_quote_expression = Brackets(Kind: BracketType.QQ, Form: assignment >> e) ^ newQuasiquoteExpression(e)
	
	quasi_quote_stmt = Brackets(Kind: BracketType.QQ, Form: (qq_return | qq_macro) >> e) ^ newQuasiquoteExpression(e)
	
	qq_return = (RETURN | Prefix(Operator: RETURN, Operand: assignment >> e)) ^ ReturnStatement(Expression: e, Modifier: null)
	qq_macro = prefix[id] >> name, optional_assignment_list >> args ^ newMacro(name, args, null, null) 
	
	def getStatement(s):
		return s if s isa Statement		
		return ExpressionStatement(s as Expression)	
						
	def callExternalParser(id, parser, input as OMetaInput):
		for r in compilerParameters.References:
			assemblyRef = r as Boo.Lang.Compiler.TypeSystem.Reflection.IAssemblyReference
			continue if assemblyRef is null
			
			assembly = assemblyRef.Assembly
			type = assembly.GetType(parser)
			break if type is not null
			
		return FailedMatch(input, RuleFailure("callExternalParser", PredicateFailure(parser))) if type is null
		
		#Save indent and wsa parameters (wsaLevel, indentStack, indentLevel)
		wsaLevel = input.GetMemo("wsaLevel")
		indentStack = input.GetMemo("indentStack")
		indentLevel = input.GetMemo("indentLevel")
		
		externalParser = Activator.CreateInstance(type)
		result = type.InvokeMember(id, BindingFlags.InvokeMethod, null as Binder, externalParser, (input,))
		
		//Restore indent and wsa parameters (wsaLevel, indentStack, indentLevel) after executing of external parser
		sm = result as SuccessfulMatch
		if sm is not null:
			sm.Input.SetMemo("wsaLevel", wsaLevel)
			sm.Input.SetMemo("indentStack", indentStack)
			sm.Input.SetMemo("indentLevel", indentLevel)
			return sm
			
		return result
// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework Version 1.0.0.260614-r1
// 脚本引擎 - 语法解析器 & AST

package main

import (
	"fmt"
)

// ===== AST 节点 =====

type NodeKind int

const (
	NodeProgram     NodeKind = iota // 程序根节点
	NodeOnEvent                     // onXxx(...) { ... }
	NodeIf                          // if (...) { ... } else { ... }
	NodeAssign                      // x = expr
	NodeCall                        // func(arg1, arg2, ...)
	NodeDotAccess                   // event.content
	NodeBinary                      // a == b, a && b
	NodeUnary                       // !a
	NodeIdentifier                  // 变量名
	NodeNumberLit                   // 数字字面量
	NodeStringLit                   // 字符串字面量
	NodeBoolLit                     // true/false
	NodeNullLit                     // null
	NodeReturn                      // return expr
	NodeBlock                       // { ... }
	NodeFor                         // for (init; cond; step) { body }
	NodeWhile                       // while (cond) { body }
	NodeBreak                       // break
	NodeContinue                    // continue
	NodeArrayLit                    // [1, 2, 3]
	NodeIndexAccess                 // arr[0]
)

type Node struct {
	Kind     NodeKind
	Token    Token
	Children []*Node
	// 特定节点字段
	EventType string // NodeOnEvent: 事件类型名
	Op        string // NodeBinary/NodeUnary: 运算符
	Value     string // NodeStringLit/NodeNumberLit: 字面值
	ElseBlock *Node  // NodeIf: else块
}

func (n *Node) String() string {
	switch n.Kind {
	case NodeProgram:
		return fmt.Sprintf("Program(%d stmts)", len(n.Children))
	case NodeOnEvent:
		return fmt.Sprintf("On(%s, %d params, %d stmts)", n.EventType, len(n.Children)-1, len(n.Children[len(n.Children)-1].Children))
	case NodeIf:
		s := fmt.Sprintf("If(cond=%s", n.Children[0])
		if n.ElseBlock != nil {
			s += fmt.Sprintf(", else=%d stmts", len(n.ElseBlock.Children))
		}
		return s + ")"
	case NodeAssign:
		return fmt.Sprintf("Assign(%s = %s)", n.Children[0], n.Children[1])
	case NodeCall:
		return fmt.Sprintf("Call(%s, %d args)", n.Token.Literal, len(n.Children))
	case NodeDotAccess:
		return fmt.Sprintf("Dot(%s.%s)", n.Children[0], n.Token.Literal)
	case NodeBinary:
		return fmt.Sprintf("Bin(%s %s %s)", n.Children[0], n.Op, n.Children[1])
	case NodeUnary:
		return fmt.Sprintf("Unary(%s%s)", n.Op, n.Children[0])
	case NodeIdentifier:
		return fmt.Sprintf("ID(%s)", n.Token.Literal)
	case NodeNumberLit:
		return fmt.Sprintf("Num(%s)", n.Value)
	case NodeStringLit:
		return fmt.Sprintf("Str(%q)", n.Value)
	case NodeBoolLit:
		return fmt.Sprintf("Bool(%s)", n.Value)
	case NodeNullLit:
		return "Null"
	case NodeReturn:
		return fmt.Sprintf("Return(%s)", n.Children[0])
	case NodeBlock:
		return fmt.Sprintf("Block(%d stmts)", len(n.Children))
	case NodeFor:
		return fmt.Sprintf("For(init=%s, cond=%s, step=%s)", n.Children[0], n.Children[1], n.Children[2])
	case NodeWhile:
		return fmt.Sprintf("While(cond=%s)", n.Children[0])
	case NodeBreak:
		return "Break"
	case NodeContinue:
		return "Continue"
	case NodeArrayLit:
		return fmt.Sprintf("Array(%d elems)", len(n.Children))
	case NodeIndexAccess:
		return fmt.Sprintf("Index(%s[%s])", n.Children[0], n.Children[1])
	default:
		return fmt.Sprintf("Node(%d)", n.Kind)
	}
}

// ===== 解析器 =====

// Parser 语法解析器
type Parser struct {
	tokens []Token
	pos    int
	errors []string
}

// NewParser 创建解析器
func NewParser(tokens []Token) *Parser {
	return &Parser{tokens: tokens, pos: 0}
}

func (p *Parser) cur() Token {
	if p.pos >= len(p.tokens) {
		return Token{Type: TokEOF}
	}
	return p.tokens[p.pos]
}

func (p *Parser) peek() Token {
	if p.pos+1 >= len(p.tokens) {
		return Token{Type: TokEOF}
	}
	return p.tokens[p.pos+1]
}

func (p *Parser) advance() Token {
	tok := p.cur()
	if p.pos < len(p.tokens) {
		p.pos++
	}
	return tok
}

func (p *Parser) expect(tt TokenType) Token {
	tok := p.advance()
	if tok.Type != tt {
		p.errors = append(p.errors, fmt.Sprintf("line %d: expected %s, got %s(%q)", tok.Line, tt, tok.Type, tok.Literal))
	}
	return tok
}

func (p *Parser) expectLiteral(tt TokenType, lit string) Token {
	tok := p.advance()
	if tok.Type != tt || tok.Literal != lit {
		p.errors = append(p.errors, fmt.Sprintf("line %d: expected %s(%q), got %s(%q)", tok.Line, tt, lit, tok.Type, tok.Literal))
	}
	return tok
}

func (p *Parser) addError(msg string) {
	p.errors = append(p.errors, msg)
}

// Parse 解析整个脚本
func (p *Parser) Parse() (*Node, []string) {
	root := &Node{Kind: NodeProgram}
	for p.cur().Type != TokEOF {
		stmt := p.parseStatement()
		if stmt != nil {
			root.Children = append(root.Children, stmt)
		}
	}
	return root, p.errors
}

func (p *Parser) parseStatement() *Node {
	tok := p.cur()

	// onXxx(...) { ... } 事件回调
	if tok.Type == TokIdentifier && len(tok.Literal) > 2 && tok.Literal[:2] == "on" && p.peek().Type == TokLParen {
		return p.parseOnEvent()
	}

	// if (...) { ... } [else { ... }]
	if tok.Type == TokIf {
		return p.parseIf()
	}

	// for (...) { ... }
	if tok.Type == TokFor {
		return p.parseFor()
	}

	// while (...) { ... }
	if tok.Type == TokWhile {
		return p.parseWhile()
	}

	// break
	if tok.Type == TokBreak {
		p.advance()
		return &Node{Kind: NodeBreak, Token: tok}
	}

	// continue
	if tok.Type == TokContinue {
		p.advance()
		return &Node{Kind: NodeContinue, Token: tok}
	}

	// return expr
	if tok.Type == TokReturn {
		return p.parseReturn()
	}

	// 赋值: identifier = expr
	if tok.Type == TokIdentifier && p.peek().Type == TokAssign {
		return p.parseAssign()
	}

	// 表达式语句（通常是函数调用）
	expr := p.parseExpression()
	return expr
}

func (p *Parser) parseOnEvent() *Node {
	nameTok := p.advance() // onXxx
	node := &Node{
		Kind:      NodeOnEvent,
		Token:     nameTok,
		EventType: nameTok.Literal,
	}

	p.expect(TokLParen)
	// 解析参数列表
	for p.cur().Type != TokRParen && p.cur().Type != TokEOF {
		param := p.advance()
		node.Children = append(node.Children, &Node{Kind: NodeIdentifier, Token: param})
		if p.cur().Type == TokComma {
			p.advance()
		}
	}
	p.expect(TokRParen)

	// 解析回调体
	block := p.parseBlock()
	// block作为最后一个child
	node.Children = append(node.Children, block)
	return node
}

func (p *Parser) parseIf() *Node {
	p.advance() // if
	node := &Node{Kind: NodeIf}
	p.expect(TokLParen)
	node.Children = append(node.Children, p.parseExpression())
	p.expect(TokRParen)
	node.Children = append(node.Children, p.parseBlock())

	// else / else if
	if p.cur().Type == TokElse {
		p.advance()
		if p.cur().Type == TokIf {
			// else if -> 嵌套一个if作为else块
			node.ElseBlock = &Node{Kind: NodeBlock, Children: []*Node{p.parseIf()}}
		} else {
			node.ElseBlock = p.parseBlock()
		}
	}
	return node
}

func (p *Parser) parseFor() *Node {
	p.advance() // for
	node := &Node{Kind: NodeFor}
	p.expect(TokLParen)

	// init (可以是赋值或空)
	var init *Node
	if p.cur().Type != TokSemicolon {
		if p.cur().Type == TokIdentifier && p.peek().Type == TokAssign {
			init = p.parseAssign()
		} else {
			init = p.parseExpression()
		}
	} else {
		init = &Node{Kind: NodeNullLit}
	}
	p.expect(TokSemicolon)
	node.Children = append(node.Children, init)

	// condition
	var cond *Node
	if p.cur().Type != TokSemicolon {
		cond = p.parseExpression()
	} else {
		cond = &Node{Kind: NodeBoolLit, Value: "true"}
	}
	p.expect(TokSemicolon)
	node.Children = append(node.Children, cond)

	// step (可以是赋值或表达式)
	var step *Node
	if p.cur().Type != TokRParen {
		if p.cur().Type == TokIdentifier && p.peek().Type == TokAssign {
			step = p.parseAssign()
		} else {
			step = p.parseExpression()
		}
	} else {
		step = &Node{Kind: NodeNullLit}
	}
	p.expect(TokRParen)
	node.Children = append(node.Children, step)

	// body
	node.Children = append(node.Children, p.parseBlock())
	return node
}

func (p *Parser) parseWhile() *Node {
	p.advance() // while
	node := &Node{Kind: NodeWhile}
	p.expect(TokLParen)
	node.Children = append(node.Children, p.parseExpression())
	p.expect(TokRParen)
	node.Children = append(node.Children, p.parseBlock())
	return node
}

func (p *Parser) parseReturn() *Node {
	p.advance() // return
	node := &Node{Kind: NodeReturn}
	if p.cur().Type != TokRBrace && p.cur().Type != TokEOF {
		node.Children = append(node.Children, p.parseExpression())
	} else {
		node.Children = append(node.Children, &Node{Kind: NodeNullLit})
	}
	return node
}

func (p *Parser) parseAssign() *Node {
	nameTok := p.advance() // identifier
	p.expect(TokAssign)
	node := &Node{Kind: NodeAssign, Token: nameTok}
	node.Children = append(node.Children, &Node{Kind: NodeIdentifier, Token: nameTok})
	node.Children = append(node.Children, p.parseExpression())
	return node
}

func (p *Parser) parseBlock() *Node {
	p.expect(TokLBrace)
	block := &Node{Kind: NodeBlock}
	for p.cur().Type != TokRBrace && p.cur().Type != TokEOF {
		stmt := p.parseStatement()
		if stmt != nil {
			block.Children = append(block.Children, stmt)
		}
	}
	p.expect(TokRBrace)
	return block
}

// ===== 表达式解析（优先级爬升） =====

func (p *Parser) parseExpression() *Node {
	return p.parseOr()
}

func (p *Parser) parseOr() *Node {
	left := p.parseAnd()
	for p.cur().Type == TokOr {
		op := p.advance()
		right := p.parseAnd()
		left = &Node{Kind: NodeBinary, Op: op.Literal, Children: []*Node{left, right}}
	}
	return left
}

func (p *Parser) parseAnd() *Node {
	left := p.parseEquality()
	for p.cur().Type == TokAnd {
		op := p.advance()
		right := p.parseEquality()
		left = &Node{Kind: NodeBinary, Op: op.Literal, Children: []*Node{left, right}}
	}
	return left
}

func (p *Parser) parseEquality() *Node {
	left := p.parseComparison()
	for p.cur().Type == TokEq || p.cur().Type == TokNeq {
		op := p.advance()
		right := p.parseComparison()
		left = &Node{Kind: NodeBinary, Op: op.Literal, Children: []*Node{left, right}}
	}
	return left
}

func (p *Parser) parseComparison() *Node {
	left := p.parseAdditive()
	for p.cur().Type == TokLt || p.cur().Type == TokGt || p.cur().Type == TokLe || p.cur().Type == TokGe {
		op := p.advance()
		right := p.parseAdditive()
		left = &Node{Kind: NodeBinary, Op: op.Literal, Children: []*Node{left, right}}
	}
	return left
}

func (p *Parser) parseAdditive() *Node {
	left := p.parseMultiplicative()
	for p.cur().Type == TokPlus || p.cur().Type == TokMinus {
		op := p.advance()
		right := p.parseMultiplicative()
		left = &Node{Kind: NodeBinary, Op: op.Literal, Children: []*Node{left, right}}
	}
	return left
}

func (p *Parser) parseMultiplicative() *Node {
	left := p.parseUnary()
	for p.cur().Type == TokStar || p.cur().Type == TokSlash || p.cur().Type == TokPercent {
		op := p.advance()
		right := p.parseUnary()
		left = &Node{Kind: NodeBinary, Op: op.Literal, Children: []*Node{left, right}}
	}
	return left
}

func (p *Parser) parseUnary() *Node {
	if p.cur().Type == TokNot {
		op := p.advance()
		operand := p.parseUnary()
		return &Node{Kind: NodeUnary, Op: op.Literal, Children: []*Node{operand}}
	}
	if p.cur().Type == TokMinus {
		op := p.advance()
		operand := p.parseUnary()
		return &Node{Kind: NodeUnary, Op: op.Literal, Children: []*Node{operand}}
	}
	return p.parsePostfix()
}

func (p *Parser) parsePostfix() *Node {
	node := p.parsePrimary()

	for {
		if p.cur().Type == TokDot {
			p.advance()
			field := p.expect(TokIdentifier)
			node = &Node{Kind: NodeDotAccess, Token: field, Children: []*Node{node}}
		} else if p.cur().Type == TokLBracket {
			// 数组下标访问 arr[expr]
			p.advance()
			index := p.parseExpression()
			p.expect(TokRBracket)
			node = &Node{Kind: NodeIndexAccess, Children: []*Node{node, index}}
		} else if p.cur().Type == TokLParen && node.Kind == NodeIdentifier {
			// 函数调用
			node = p.parseCall(node)
		} else {
			break
		}
	}
	return node
}

func (p *Parser) parseArrayLit() *Node {
	p.advance() // [
	node := &Node{Kind: NodeArrayLit}
	for p.cur().Type != TokRBracket && p.cur().Type != TokEOF {
		node.Children = append(node.Children, p.parseExpression())
		if p.cur().Type == TokComma {
			p.advance()
		} else {
			break
		}
	}
	p.expect(TokRBracket)
	return node
}

func (p *Parser) parseCall(callee *Node) *Node {
	p.expect(TokLParen)
	node := &Node{Kind: NodeCall, Token: callee.Token, Children: nil}
	for p.cur().Type != TokRParen && p.cur().Type != TokEOF {
		arg := p.parseExpression()
		node.Children = append(node.Children, arg)
		if p.cur().Type == TokComma {
			p.advance()
		}
	}
	p.expect(TokRParen)
	return node
}

func (p *Parser) parsePrimary() *Node {
	tok := p.cur()

	switch tok.Type {
	case TokNumber:
		p.advance()
		return &Node{Kind: NodeNumberLit, Value: tok.Literal, Token: tok}
	case TokString:
		p.advance()
		return &Node{Kind: NodeStringLit, Value: tok.Literal, Token: tok}
	case TokTrue:
		p.advance()
		return &Node{Kind: NodeBoolLit, Value: "true", Token: tok}
	case TokFalse:
		p.advance()
		return &Node{Kind: NodeBoolLit, Value: "false", Token: tok}
	case TokNull:
		p.advance()
		return &Node{Kind: NodeNullLit, Token: tok}
	case TokIdentifier:
		p.advance()
		return &Node{Kind: NodeIdentifier, Token: tok}
	case TokLParen:
		p.advance()
		expr := p.parseExpression()
		p.expect(TokRParen)
		return expr
	case TokLBracket:
		return p.parseArrayLit()
	default:
		p.addError(fmt.Sprintf("line %d: unexpected token %s(%q)", tok.Line, tok.Type, tok.Literal))
		p.advance()
		return &Node{Kind: NodeNullLit, Token: tok}
	}
}

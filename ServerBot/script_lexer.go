// Copyright (c) Chemsource Studio. All rights reserved.
// CsAC ServerBot Framework Version 1.0.0.260614-r1
// 脚本引擎 - 词法分析器

package main

import (
	"fmt"
	"strings"
	"unicode"
)

// TokenType 词法单元类型
type TokenType int

const (
	TokEOF        TokenType = iota
	TokIdentifier           // 标识符: onGroupMsg, sendGroupMsg, x, room_id
	TokNumber               // 数字: 123, 42
	TokString               // 字符串: "hello"
	TokLBrace               // {
	TokRBrace               // }
	TokLParen               // (
	TokRParen               // )
	TokComma                // ,
	TokDot                  // .
	TokAssign               // =
	TokEq                   // ==
	TokNeq                  // !=
	TokLt                   // <
	TokGt                   // >
	TokLe                   // <=
	TokGe                   // >=
	TokAnd                  // &&
	TokOr                   // ||
	TokNot                  // !
	TokPlus                 // +
	TokMinus                // -
	TokStar                 // *
	TokSlash                // /
	TokPercent              // %
	TokSemicolon            // ;
	TokLBracket             // [
	TokRBracket             // ]
	TokIf                   // if
	TokElse                 // else
	TokReturn               // return
	TokTrue                 // true
	TokFalse                // false
	TokNull                 // null
	TokFor                  // for
	TokWhile                // while
	TokBreak                // break
	TokContinue             // continue
	TokComment              // // 或 /* */
)

// Token 词法单元
type Token struct {
	Type    TokenType
	Literal string
	Line    int
	Col     int
}

// Lexer 词法分析器
type Lexer struct {
	input  []rune // 以rune切片存储，正确处理UTF-8多字节字符（如中文）
	pos    int
	line   int
	col    int
	ch     rune
	peekCh rune
	tokens []Token
}

var keywords = map[string]TokenType{
	"if":       TokIf,
	"else":     TokElse,
	"return":   TokReturn,
	"true":     TokTrue,
	"false":    TokFalse,
	"null":     TokNull,
	"for":      TokFor,
	"while":    TokWhile,
	"break":    TokBreak,
	"continue": TokContinue,
}

// NewLexer 创建词法分析器
func NewLexer(input string) *Lexer {
	l := &Lexer{
		input: []rune(input), // 转为rune切片，每个中文占一个元素
		line:  1,
		col:   0,
	}
	l.readChar()
	return l
}

func (l *Lexer) readChar() {
	if l.pos >= len(l.input) {
		l.ch = 0
	} else {
		l.ch = l.input[l.pos]
	}
	l.pos++
	l.col++
	if l.ch == '\n' {
		l.line++
		l.col = 0
	}
	// 预读
	if l.pos >= len(l.input) {
		l.peekCh = 0
	} else {
		l.peekCh = l.input[l.pos]
	}
}

func (l *Lexer) skipWhitespace() {
	for l.ch != 0 && unicode.IsSpace(l.ch) {
		l.readChar()
	}
}

func (l *Lexer) skipComment() bool {
	if l.ch == '/' && l.peekCh == '/' {
		for l.ch != 0 && l.ch != '\n' {
			l.readChar()
		}
		return true
	}
	if l.ch == '/' && l.peekCh == '*' {
		l.readChar()
		l.readChar()
		for l.ch != 0 {
			if l.ch == '*' && l.peekCh == '/' {
				l.readChar()
				l.readChar()
				return true
			}
			l.readChar()
		}
		return true
	}
	return false
}

// Tokenize 执行词法分析，返回所有词法单元
func (l *Lexer) Tokenize() []Token {
	var tokens []Token
	for {
		l.skipWhitespace()
		if l.ch == 0 {
			tokens = append(tokens, Token{Type: TokEOF, Line: l.line, Col: l.col})
			break
		}
		if l.skipComment() {
			continue
		}

		line, col := l.line, l.col
		var tok Token

		switch l.ch {
		case '{':
			tok = Token{Type: TokLBrace, Literal: "{", Line: line, Col: col}
			l.readChar()
		case '}':
			tok = Token{Type: TokRBrace, Literal: "}", Line: line, Col: col}
			l.readChar()
		case '(':
			tok = Token{Type: TokLParen, Literal: "(", Line: line, Col: col}
			l.readChar()
		case ')':
			tok = Token{Type: TokRParen, Literal: ")", Line: line, Col: col}
			l.readChar()
		case ',':
			tok = Token{Type: TokComma, Literal: ",", Line: line, Col: col}
			l.readChar()
		case '.':
			tok = Token{Type: TokDot, Literal: ".", Line: line, Col: col}
			l.readChar()
		case ';':
			tok = Token{Type: TokSemicolon, Literal: ";", Line: line, Col: col}
			l.readChar()
		case '[':
			tok = Token{Type: TokLBracket, Literal: "[", Line: line, Col: col}
			l.readChar()
		case ']':
			tok = Token{Type: TokRBracket, Literal: "]", Line: line, Col: col}
			l.readChar()
		case '=':
			if l.peekCh == '=' {
				l.readChar()
				l.readChar()
				tok = Token{Type: TokEq, Literal: "==", Line: line, Col: col}
			} else {
				tok = Token{Type: TokAssign, Literal: "=", Line: line, Col: col}
				l.readChar()
			}
		case '!':
			if l.peekCh == '=' {
				l.readChar()
				l.readChar()
				tok = Token{Type: TokNeq, Literal: "!=", Line: line, Col: col}
			} else {
				tok = Token{Type: TokNot, Literal: "!", Line: line, Col: col}
				l.readChar()
			}
		case '<':
			if l.peekCh == '=' {
				l.readChar()
				l.readChar()
				tok = Token{Type: TokLe, Literal: "<=", Line: line, Col: col}
			} else {
				tok = Token{Type: TokLt, Literal: "<", Line: line, Col: col}
				l.readChar()
			}
		case '>':
			if l.peekCh == '=' {
				l.readChar()
				l.readChar()
				tok = Token{Type: TokGe, Literal: ">=", Line: line, Col: col}
			} else {
				tok = Token{Type: TokGt, Literal: ">", Line: line, Col: col}
				l.readChar()
			}
		case '&':
			if l.peekCh == '&' {
				l.readChar()
				l.readChar()
				tok = Token{Type: TokAnd, Literal: "&&", Line: line, Col: col}
			} else {
				tok = Token{Type: TokEOF, Literal: "&", Line: line, Col: col}
				l.readChar()
			}
		case '|':
			if l.peekCh == '|' {
				l.readChar()
				l.readChar()
				tok = Token{Type: TokOr, Literal: "||", Line: line, Col: col}
			} else {
				tok = Token{Type: TokEOF, Literal: "|", Line: line, Col: col}
				l.readChar()
			}
		case '+':
			tok = Token{Type: TokPlus, Literal: "+", Line: line, Col: col}
			l.readChar()
		case '-':
			tok = Token{Type: TokMinus, Literal: "-", Line: line, Col: col}
			l.readChar()
		case '*':
			tok = Token{Type: TokStar, Literal: "*", Line: line, Col: col}
			l.readChar()
		case '/':
			tok = Token{Type: TokSlash, Literal: "/", Line: line, Col: col}
			l.readChar()
		case '%':
			tok = Token{Type: TokPercent, Literal: "%", Line: line, Col: col}
			l.readChar()
		case '"', '\'':
			tok = l.readString()
		default:
			if unicode.IsDigit(l.ch) {
				tok = l.readNumber()
			} else if isIdentStart(l.ch) {
				tok = l.readIdentifier()
			} else {
				tok = Token{Type: TokEOF, Literal: string(l.ch), Line: line, Col: col}
				l.readChar()
			}
		}
		tokens = append(tokens, tok)
	}
	return tokens
}

func (l *Lexer) readString() Token {
	quote := l.ch
	line, col := l.line, l.col
	l.readChar()
	var sb strings.Builder
	for l.ch != 0 && l.ch != quote {
		if l.ch == '\\' {
			l.readChar()
			switch l.ch {
			case 'n':
				sb.WriteRune('\n')
			case 't':
				sb.WriteRune('\t')
			case 'r':
				sb.WriteRune('\r')
			case '\\':
				sb.WriteRune('\\')
			case '"':
				sb.WriteRune('"')
			case '\'':
				sb.WriteRune('\'')
			default:
				sb.WriteRune(l.ch)
			}
		} else {
			sb.WriteRune(l.ch)
		}
		l.readChar()
	}
	l.readChar() // 跳过结尾引号
	return Token{Type: TokString, Literal: sb.String(), Line: line, Col: col}
}

func (l *Lexer) readNumber() Token {
	line, col := l.line, l.col
	var sb strings.Builder
	for l.ch != 0 && unicode.IsDigit(l.ch) {
		sb.WriteRune(l.ch)
		l.readChar()
	}
	return Token{Type: TokNumber, Literal: sb.String(), Line: line, Col: col}
}

func (l *Lexer) readIdentifier() Token {
	line, col := l.line, l.col
	var sb strings.Builder
	for l.ch != 0 && isIdentPart(l.ch) {
		sb.WriteRune(l.ch)
		l.readChar()
	}
	lit := sb.String()
	if tt, ok := keywords[lit]; ok {
		return Token{Type: tt, Literal: lit, Line: line, Col: col}
	}
	return Token{Type: TokIdentifier, Literal: lit, Line: line, Col: col}
}

func isIdentStart(ch rune) bool {
	return unicode.IsLetter(ch) || ch == '_'
}

func isIdentPart(ch rune) bool {
	return unicode.IsLetter(ch) || unicode.IsDigit(ch) || ch == '_'
}

// FormatToken 格式化词法单元（调试用）
func FormatToken(tok Token) string {
	return fmt.Sprintf("%d:%d %s(%q)", tok.Line, tok.Col, tok.Type, tok.Literal)
}

func (tt TokenType) String() string {
	names := map[TokenType]string{
		TokEOF: "EOF", TokIdentifier: "ID", TokNumber: "NUM", TokString: "STR",
		TokLBrace: "{", TokRBrace: "}", TokLParen: "(", TokRParen: ")",
		TokComma: ",", TokDot: ".", TokAssign: "=", TokEq: "==",
		TokNeq: "!=", TokLt: "<", TokGt: ">", TokLe: "<=", TokGe: ">=",
		TokAnd: "&&", TokOr: "||", TokNot: "!",
		TokPlus: "+", TokMinus: "-", TokStar: "*", TokSlash: "/", TokPercent: "%",
		TokSemicolon: ";", TokLBracket: "[", TokRBracket: "]",
		TokIf: "if", TokElse: "else", TokReturn: "return",
		TokTrue: "true", TokFalse: "false", TokNull: "null",
		TokFor: "for", TokWhile: "while", TokBreak: "break", TokContinue: "continue",
	}
	if name, ok := names[tt]; ok {
		return name
	}
	return fmt.Sprintf("Tok(%d)", tt)
}

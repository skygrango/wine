%{
/*
 * Parser for command lines in the Wine debugger
 *
 * Copyright 1993 Eric Youngdale
 * Copyright 1995 Morten Welinder
 * Copyright 2000 Eric Pouech
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#include "config.h"
#include "wine/port.h"

#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "wine/exception.h"
#include "debugger.h"
#include "expr.h"

int yylex(void);
int yyerror(const char*);

%}

%union
{
    struct dbg_lvalue   lvalue;
    char*               string;
    int                 integer;
    IMAGEHLP_LINE       listing;
    struct expr*        expression;
    struct type_expr_t  type;
}

%token tCONT tPASS tSTEP tLIST tNEXT tQUIT tHELP tBACKTRACE tALL tINFO tUP tDOWN
%token tENABLE tDISABLE tBREAK tWATCH tDELETE tSET tMODE tPRINT tEXAM tABORT tVM86
%token tCLASS tMAPS tSTACK tSEGMENTS tSYMBOL tREGS tWND tQUEUE tLOCAL tEXCEPTION
%token tPROCESS tTHREAD tMODREF tEOL tEOF
%token tFRAME tSHARE tCOND tDISPLAY tUNDISPLAY tDISASSEMBLE
%token tSTEPI tNEXTI tFINISH tSHOW tDIR tWHATIS tSOURCE
%token <string> tPATH tIDENTIFIER tSTRING tDEBUGSTR tINTVAR
%token <integer> tNUM tFORMAT
%token tSYMBOLFILE tRUN tATTACH tDETACH tNOPROCESS tMAINTENANCE tTYPE

%token tCHAR tSHORT tINT tLONG tFLOAT tDOUBLE tUNSIGNED tSIGNED
%token tSTRUCT tUNION tENUM

/* %left ',' */
/* %left '=' OP_OR_EQUAL OP_XOR_EQUAL OP_AND_EQUAL OP_SHL_EQUAL \
         OP_SHR_EQUAL OP_PLUS_EQUAL OP_MINUS_EQUAL \
         OP_TIMES_EQUAL OP_DIVIDE_EQUAL OP_MODULO_EQUAL */
/* %left OP_COND */ /* ... ? ... : ... */
%left OP_LOR
%left OP_LAND
%left '|'
%left '^'
%left '&'
%left OP_EQ OP_NE
%left '<' '>' OP_LE OP_GE
%left OP_SHL OP_SHR
%left '+' '-'
%left '*' '/' '%'
%left OP_SIGN '!' '~' OP_DEREF /* OP_INC OP_DEC OP_ADDR */
%left '.' '[' OP_DRF
%nonassoc ':'

%type <expression> expr lvalue
%type <lvalue> expr_lvalue lvalue_addr
%type <integer> expr_rvalue
%type <string> pathname identifier
%type <listing> list_arg
%type <type> type_expr

%%

input:
      line
    | input line
    ;

line:
      command tEOL              { expr_free_all(); }
    | tEOL
    | tEOF                      { return 1; }
    | error tEOL               	{ yyerrok; expr_free_all(); }
    ;

command:
      tQUIT                     { return 1; }
    | tHELP                     { print_help(); }
    | tHELP tINFO               { info_help(); }
    | tPASS                     { dbg_wait_next_exception(DBG_EXCEPTION_NOT_HANDLED, 0, 0); }
    | tCONT                     { dbg_wait_next_exception(DBG_CONTINUE, 1,  dbg_exec_cont); }
    | tCONT tNUM              	{ dbg_wait_next_exception(DBG_CONTINUE, $2, dbg_exec_cont); }
    | tSTEP                    	{ dbg_wait_next_exception(DBG_CONTINUE, 1,  dbg_exec_step_into_line); }
    | tSTEP tNUM                { dbg_wait_next_exception(DBG_CONTINUE, $2, dbg_exec_step_into_line); }
    | tNEXT                     { dbg_wait_next_exception(DBG_CONTINUE, 1,  dbg_exec_step_over_line); }
    | tNEXT tNUM                { dbg_wait_next_exception(DBG_CONTINUE, $2, dbg_exec_step_over_line); }
    | tSTEPI                    { dbg_wait_next_exception(DBG_CONTINUE, 1,  dbg_exec_step_into_insn); }
    | tSTEPI tNUM               { dbg_wait_next_exception(DBG_CONTINUE, $2, dbg_exec_step_into_insn); }
    | tNEXTI                    { dbg_wait_next_exception(DBG_CONTINUE, 1,  dbg_exec_step_over_insn); }
    | tNEXTI tNUM               { dbg_wait_next_exception(DBG_CONTINUE, $2, dbg_exec_step_over_insn); }
    | tFINISH     	       	{ dbg_wait_next_exception(DBG_CONTINUE, 0,  dbg_exec_finish); }
    | tABORT                   	{ abort(); }
    | tBACKTRACE     	       	{ stack_backtrace(dbg_curr_tid, TRUE); }
    | tBACKTRACE tNUM          	{ stack_backtrace($2, TRUE); }
    | tBACKTRACE tALL           { stack_backtrace(-1, TRUE); }
    | tUP     		       	{ stack_set_frame(dbg_curr_frame + 1);  }
    | tUP tNUM     	       	{ stack_set_frame(dbg_curr_frame + $2); }
    | tDOWN     	       	{ stack_set_frame(dbg_curr_frame - 1);  }
    | tDOWN tNUM     	       	{ stack_set_frame(dbg_curr_frame - $2); }
    | tFRAME tNUM              	{ stack_set_frame($2); }
    | tSHOW tDIR     	       	{ source_show_path(); }
    | tDIR pathname            	{ source_add_path($2); }
    | tDIR     		       	{ source_nuke_path(); }
    | tCOND tNUM               	{ break_add_condition($2, NULL); }
    | tCOND tNUM expr     	{ break_add_condition($2, $3); }
    | tSOURCE pathname          { parser($2); }
    | tSYMBOLFILE pathname     	{ symbol_read_symtable($2, 0); }
    | tSYMBOLFILE pathname expr_rvalue { symbol_read_symtable($2, $3); }
    | tWHATIS expr_lvalue       { types_print_type(&$2.type, FALSE); dbg_printf("\n"); }
    | tATTACH tNUM     		{ dbg_attach_debuggee($2, FALSE, TRUE); }
    | tDETACH                   { dbg_detach_debuggee(); }
    | run_command
    | list_command
    | disassemble_command
    | set_command
    | x_command
    | print_command     
    | break_command
    | watch_command
    | display_command
    | info_command
    | maintenance_command
    | noprocess_state
    ;

pathname:
      identifier                { $$ = $1; }
    | tPATH                     { $$ = $1; }
    ;

identifier:
      tIDENTIFIER               { $$ = $1; }
    | tIDENTIFIER '!' tIDENTIFIER { char* ptr = HeapAlloc(GetProcessHeap(), 0, strlen($1) + 1 + strlen($3) + 1);
                                    sprintf(ptr, "%s!%s", $1, $3); $$ = lexeme_alloc(ptr);
                                    HeapFree(GetProcessHeap(), 0, ptr); }
    | identifier ':' ':' tIDENTIFIER { char* ptr = HeapAlloc(GetProcessHeap(), 0, strlen($1) + 2 + strlen($4) + 1);
                                       sprintf(ptr, "%s::%s", $1, $4); $$ = lexeme_alloc(ptr);
                                       HeapFree(GetProcessHeap(), 0, ptr); }
    ;

list_arg:
      tNUM		        { $$.FileName = NULL; $$.LineNumber = $1; }
    | pathname ':' tNUM	        { $$.FileName = $1; $$.LineNumber = $3; }
    | identifier	        { symbol_get_line(NULL, $1, &$$); }
    | pathname ':' identifier   { symbol_get_line($3, $1, &$$); }
    | '*' expr_lvalue	        { $$.SizeOfStruct = sizeof($$);
                                  SymGetLineFromAddr(dbg_curr_process->handle, (unsigned long)memory_to_linear_addr(& $2.addr), NULL, & $$); }
    ;

run_command:
      tRUN                      { dbg_run_debuggee(NULL); }
    | tRUN tSTRING              { dbg_run_debuggee($2); }
    ;

list_command:
      tLIST                     { source_list(NULL, NULL, 10); }
    | tLIST '-'                 { source_list(NULL,  NULL, -10); }
    | tLIST list_arg            { source_list(& $2, NULL, 10); }
    | tLIST ',' list_arg        { source_list(NULL, & $3, -10); }
    | tLIST list_arg ',' list_arg      { source_list(& $2, & $4, 0); }
    ;

disassemble_command:
      tDISASSEMBLE              { memory_disassemble(NULL, NULL, 10); }
    | tDISASSEMBLE expr_lvalue  { memory_disassemble(&$2, NULL, 10); }
    | tDISASSEMBLE expr_lvalue ',' expr_lvalue { memory_disassemble(&$2, &$4, 0); }
    ;

set_command:
      tSET lvalue_addr '=' expr_rvalue { memory_write_value(&$2, sizeof(int), &$4); }
    | tSET '+' tIDENTIFIER      { info_wine_dbg_channel(TRUE, NULL, $3); }
    | tSET '-' tIDENTIFIER      { info_wine_dbg_channel(FALSE, NULL, $3); }
    | tSET tIDENTIFIER '+' tIDENTIFIER { info_wine_dbg_channel(TRUE, $2, $4); }
    | tSET tIDENTIFIER '-' tIDENTIFIER { info_wine_dbg_channel(FALSE, $2, $4); }
    ;

x_command:
      tEXAM expr_rvalue         { memory_examine((void*)$2, 1, 'x'); }
    | tEXAM tFORMAT expr_rvalue { memory_examine((void*)$3, $2 >> 8, $2 & 0xff); }
    ;

print_command:
      tPRINT expr_lvalue         { print_value(&$2, 0, 0); }
    | tPRINT tFORMAT expr_lvalue { if (($2 >> 8) == 1) print_value(&$3, $2 & 0xff, 0); else dbg_printf("Count is meaningless in print command\n"); }
    ;

break_command:
      tBREAK '*' expr_lvalue    { break_add_break_from_lvalue(&$3); }
    | tBREAK identifier         { break_add_break_from_id($2, -1); }
    | tBREAK identifier ':' tNUM { break_add_break_from_id($2, $4); }
    | tBREAK tNUM     	        { break_add_break_from_lineno($2); }
    | tBREAK                    { break_add_break_from_lineno(-1); }
    | tENABLE tNUM              { break_enable_xpoint($2, TRUE); }
    | tENABLE tBREAK tNUM     	{ break_enable_xpoint($3, TRUE); }
    | tDISABLE tNUM             { break_enable_xpoint($2, FALSE); }
    | tDISABLE tBREAK tNUM     	{ break_enable_xpoint($3, FALSE); }
    | tDELETE tNUM      	{ break_delete_xpoint($2); }
    | tDELETE tBREAK tNUM      	{ break_delete_xpoint($3); }
    ;

watch_command:
      tWATCH '*' expr_lvalue    { break_add_watch_from_lvalue(&$3); }
    | tWATCH identifier         { break_add_watch_from_id($2); }
    ;

display_command:
      tDISPLAY     	       	{ display_print(); }
    | tDISPLAY expr            	{ display_add($2, 1, 0); }
    | tDISPLAY tFORMAT expr     { display_add($3, $2 >> 8, $2 & 0xff); }
    | tENABLE tDISPLAY tNUM     { display_enable($3, TRUE); }
    | tDISABLE tDISPLAY tNUM    { display_enable($3, FALSE); }
    | tDELETE tDISPLAY tNUM     { display_delete($3); }
    | tDELETE tDISPLAY         	{ display_delete(-1); }
    | tUNDISPLAY tNUM          	{ display_delete($2); }
    | tUNDISPLAY               	{ display_delete(-1); }
    ;

info_command:
      tINFO tBREAK              { break_info(); }
    | tINFO tSHARE     		{ info_win32_module(0); }
    | tINFO tSHARE expr_rvalue  { info_win32_module($3); }
    | tINFO tREGS               { be_cpu->print_context(dbg_curr_thread->handle, &dbg_context); }
    | tINFO tSEGMENTS expr_rvalue { info_win32_segments($3, 1); }
    | tINFO tSEGMENTS           { info_win32_segments(0, -1); }
    | tINFO tSTACK              { stack_info(); }
    | tINFO tSYMBOL tSTRING     { symbol_info($3); }
    | tINFO tLOCAL              { symbol_info_locals(); }
    | tINFO tDISPLAY            { display_info(); }
    | tINFO tCLASS              { info_win32_class(NULL, NULL); }
    | tINFO tCLASS tSTRING     	{ info_win32_class(NULL, $3); }
    | tINFO tWND                { info_win32_window(NULL, FALSE); }
    | tINFO tWND expr_rvalue    { info_win32_window((HWND)$3, FALSE); }
    | tINFO '*' tWND            { info_win32_window(NULL, TRUE); }
    | tINFO '*' tWND expr_rvalue { info_win32_window((HWND)$4, TRUE); }
    | tINFO tPROCESS            { info_win32_processes(); }
    | tINFO tTHREAD             { info_win32_threads(); }
    | tINFO tEXCEPTION          { info_win32_exceptions(dbg_curr_tid); }
    | tINFO tEXCEPTION expr_rvalue { info_win32_exceptions($3); }
    | tINFO tMAPS               { info_win32_virtual(dbg_curr_pid); }
    | tINFO tMAPS expr_rvalue   { info_win32_virtual($3); }
    ;

maintenance_command:
      tMAINTENANCE tTYPE        { print_types(); }
    ;

noprocess_state:
      tNOPROCESS                 {} /* <CR> shall not barf anything */
    | tNOPROCESS tBACKTRACE tALL { stack_backtrace(-1, TRUE); } /* can backtrace all threads with no attached process */
    | tNOPROCESS tSTRING         { dbg_printf("No process loaded, cannot execute '%s'\n", $2); }
    ;

type_expr:
      tCHAR			{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_char; }
    | tINT			{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_signed_int; }
    | tLONG tINT		{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_signed_long_int; }
    | tLONG     		{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_signed_long_int; }
    | tUNSIGNED tINT		{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_unsigned_int; }
    | tUNSIGNED 		{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_unsigned_int; }
    | tLONG tUNSIGNED tINT	{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_unsigned_long_int; }
    | tLONG tUNSIGNED   	{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_unsigned_long_int; }
    | tSHORT tINT		{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_signed_short_int; }
    | tSHORT    		{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_signed_short_int; }
    | tSHORT tUNSIGNED tINT	{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_unsigned_short_int; }
    | tSHORT tUNSIGNED  	{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_unsigned_short_int; }
    | tSIGNED tCHAR		{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_signed_char_int; }
    | tUNSIGNED tCHAR		{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_unsigned_char_int; }
    | tLONG tLONG tUNSIGNED tINT{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_unsigned_longlong_int; }
    | tLONG tLONG tUNSIGNED     { $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_unsigned_longlong_int; }
    | tLONG tLONG tINT          { $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_signed_longlong_int; }
    | tLONG tLONG               { $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_signed_longlong_int; }
    | tFLOAT			{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_short_real; }
    | tDOUBLE			{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_real; }
    | tLONG tDOUBLE		{ $$.type = type_expr_type_id; $$.deref_count = 0; $$.u.type.module = 0; $$.u.type.id = dbg_itype_long_real; }
    | type_expr '*'		{ $$ = $1; $$.deref_count++; }
    | tCLASS identifier	        { $$.type = type_expr_udt_class; $$.deref_count = 0; $$.u.name = lexeme_alloc($2); }
    | tSTRUCT identifier	{ $$.type = type_expr_udt_struct; $$.deref_count = 0; $$.u.name = lexeme_alloc($2); }
    | tUNION identifier	        { $$.type = type_expr_udt_union; $$.deref_count = 0; $$.u.name = lexeme_alloc($2); }
    | tENUM identifier	        { $$.type = type_expr_enumeration; $$.deref_count = 0; $$.u.name = lexeme_alloc($2); }
    ;

expr_lvalue:
      expr                      { $$ = expr_eval($1); }
    ;

expr_rvalue:
      expr_lvalue               { $$ = types_extract_as_integer(&$1); }
    ;

/*
 * The expr rule builds an expression tree.  When we are done, we call
 * EvalExpr to evaluate the value of the expression.  The advantage of
 * the two-step approach is that it is possible to save expressions for
 * use in 'display' commands, and in conditional watchpoints.
 */
expr:
      tNUM                      { $$ = expr_alloc_sconstant($1); }
    | tSTRING			{ $$ = expr_alloc_string($1); }
    | tINTVAR                   { $$ = expr_alloc_internal_var($1); }
    | identifier		{ $$ = expr_alloc_symbol($1); }
    | expr OP_DRF tIDENTIFIER	{ $$ = expr_alloc_pstruct($1, $3); }
    | expr '.' tIDENTIFIER      { $$ = expr_alloc_struct($1, $3); }
    | identifier '(' ')'	{ $$ = expr_alloc_func_call($1, 0); }
    | identifier '(' expr ')'	{ $$ = expr_alloc_func_call($1, 1, $3); }
    | identifier '(' expr ',' expr ')' { $$ = expr_alloc_func_call($1, 2, $3, $5); }
    | identifier '(' expr ',' expr ',' expr ')'	{ $$ = expr_alloc_func_call($1, 3, $3, $5, $7); }
    | identifier '(' expr ',' expr ',' expr ',' expr ')' { $$ = expr_alloc_func_call($1, 4, $3, $5, $7, $9); }
    | identifier '(' expr ',' expr ',' expr ',' expr ',' expr ')' { $$ = expr_alloc_func_call($1, 5, $3, $5, $7, $9, $11); }
    | expr '[' expr ']'		 { $$ = expr_alloc_binary_op(EXP_OP_ARR, $1, $3); }
    | expr ':' expr		 { $$ = expr_alloc_binary_op(EXP_OP_SEG, $1, $3); }
    | expr OP_LOR expr           { $$ = expr_alloc_binary_op(EXP_OP_LOR, $1, $3); }
    | expr OP_LAND expr          { $$ = expr_alloc_binary_op(EXP_OP_LAND, $1, $3); }
    | expr '|' expr              { $$ = expr_alloc_binary_op(EXP_OP_OR, $1, $3); }
    | expr '&' expr              { $$ = expr_alloc_binary_op(EXP_OP_AND, $1, $3); }
    | expr '^' expr              { $$ = expr_alloc_binary_op(EXP_OP_XOR, $1, $3); }
    | expr OP_EQ expr            { $$ = expr_alloc_binary_op(EXP_OP_EQ, $1, $3); }
    | expr '>' expr              { $$ = expr_alloc_binary_op(EXP_OP_GT, $1, $3); }
    | expr '<' expr              { $$ = expr_alloc_binary_op(EXP_OP_LT, $1, $3); }
    | expr OP_GE expr            { $$ = expr_alloc_binary_op(EXP_OP_GE, $1, $3); }
    | expr OP_LE expr            { $$ = expr_alloc_binary_op(EXP_OP_LE, $1, $3); }
    | expr OP_NE expr            { $$ = expr_alloc_binary_op(EXP_OP_NE, $1, $3); }
    | expr OP_SHL expr           { $$ = expr_alloc_binary_op(EXP_OP_SHL, $1, $3); }
    | expr OP_SHR expr           { $$ = expr_alloc_binary_op(EXP_OP_SHR, $1, $3); }
    | expr '+' expr              { $$ = expr_alloc_binary_op(EXP_OP_ADD, $1, $3); }
    | expr '-' expr              { $$ = expr_alloc_binary_op(EXP_OP_SUB, $1, $3); }
    | expr '*' expr              { $$ = expr_alloc_binary_op(EXP_OP_MUL, $1, $3); }
    | expr '/' expr              { $$ = expr_alloc_binary_op(EXP_OP_DIV, $1, $3); }
    | expr '%' expr              { $$ = expr_alloc_binary_op(EXP_OP_REM, $1, $3); }
    | '-' expr %prec OP_SIGN     { $$ = expr_alloc_unary_op(EXP_OP_NEG, $2); }
    | '+' expr %prec OP_SIGN     { $$ = $2; }
    | '!' expr                   { $$ = expr_alloc_unary_op(EXP_OP_NOT, $2); }
    | '~' expr                   { $$ = expr_alloc_unary_op(EXP_OP_LNOT, $2); }
    | '(' expr ')'               { $$ = $2; }
    | '*' expr %prec OP_DEREF    { $$ = expr_alloc_unary_op(EXP_OP_DEREF, $2); }
    | '&' expr %prec OP_DEREF    { $$ = expr_alloc_unary_op(EXP_OP_ADDR, $2); }
    | '(' type_expr ')' expr %prec OP_DEREF { $$ = expr_alloc_typecast(&$2, $4); }
    ;

/*
 * The lvalue rule builds an expression tree.  This is a limited form
 * of expression that is suitable to be used as an lvalue.
 */
lvalue_addr: 
      lvalue                     { $$ = expr_eval($1); }
    ;

lvalue: tNUM                     { $$ = expr_alloc_sconstant($1); }
    | tINTVAR                    { $$ = expr_alloc_internal_var($1); }
    | identifier		 { $$ = expr_alloc_symbol($1); }
    | lvalue OP_DRF tIDENTIFIER	 { $$ = expr_alloc_pstruct($1, $3); }
    | lvalue '.' tIDENTIFIER	 { $$ = expr_alloc_struct($1, $3); }
    | lvalue '[' expr ']'	 { $$ = expr_alloc_binary_op(EXP_OP_ARR, $1, $3); }
    | '*' expr			 { $$ = expr_alloc_unary_op(EXP_OP_FORCE_DEREF, $2); }
    ;

%%

static WINE_EXCEPTION_FILTER(wine_dbg_cmd)
{
    switch (GetExceptionCode())
    {
    case DEBUG_STATUS_INTERNAL_ERROR:
        dbg_printf("\nWineDbg internal error\n");
        break;
    case DEBUG_STATUS_NO_SYMBOL:
        dbg_printf("\nUndefined symbol\n");
        break;
    case DEBUG_STATUS_DIV_BY_ZERO:
        dbg_printf("\nDivision by zero\n");
        break;
    case DEBUG_STATUS_BAD_TYPE:
        dbg_printf("\nNo type or type mismatch\n");
        break;
    case DEBUG_STATUS_NO_FIELD:
        dbg_printf("\nNo such field in structure or union\n");
        break;
    case DEBUG_STATUS_CANT_DEREF:
        dbg_printf("\nDereference failed (not a pointer, or out of array bounds)\n");
        break;
    case DEBUG_STATUS_ABORT:
        break;
    case DEBUG_STATUS_NOT_AN_INTEGER:
        dbg_printf("\nNeeding an integral value\n");
        break;
    case CONTROL_C_EXIT:
        /* this is generally sent by a ctrl-c when we run winedbg outside of wineconsole */
        /* stop the debuggee, and continue debugger execution, we will be reentered by the
         * debug events generated by stopping
         */
        dbg_interrupt_debuggee();
        return EXCEPTION_CONTINUE_EXECUTION;
    default:
        dbg_printf("\nException %lx\n", GetExceptionCode());
        break;
    }

    return EXCEPTION_EXECUTE_HANDLER;
}

#ifndef whitespace
#define whitespace(c) (((c) == ' ') || ((c) == '\t'))
#endif

/* Strip whitespace from the start and end of STRING. */
static void stripwhite(char *string)
{
    int         i, last;

    for (i = 0; whitespace(string[i]); i++);
    if (i) strcpy(string, string + i);

    last = i = strlen(string) - 1;
    if (string[last] == '\n') i--;

    while (i > 0 && whitespace(string[i])) i--;
    if (string[last] == '\n')
        string[++i] = '\n';
    string[++i] = '\0';
}

static HANDLE dbg_parser_input;
static HANDLE dbg_parser_output;

/* command passed in the command line arguments */
char *arg_command = NULL;

int      input_fetch_entire_line(const char* pfx, char** line, size_t* alloc, BOOL check_nl)
{
    char 	buf_line[256];
    DWORD	nread, nwritten;
    size_t      len;
    
    if (arg_command) {
        *line = arg_command;
        arg_command = "quit\n"; /* we only run one command before exiting */
        return 1;
    }

    /* as of today, console handles can be file handles... so better use file APIs rather than
     * console's
     */
    WriteFile(dbg_parser_output, pfx, strlen(pfx), &nwritten, NULL);

    len = 0;
    do
    {
	if (!ReadFile(dbg_parser_input, buf_line, sizeof(buf_line) - 1, &nread, NULL) || nread == 0)
            break;
	buf_line[nread] = '\0';

        if (check_nl && len == 0 && nread == 1 && buf_line[0] == '\n')
            return 0;

        /* store stuff at the end of last_line */
        if (len + nread + 1 > *alloc)
        {
            while (len + nread + 1 > *alloc) *alloc *= 2;
            *line = dbg_heap_realloc(*line, *alloc);
        }
        strcpy(*line + len, buf_line);
        len += nread;
    } while (nread == 0 || buf_line[nread - 1] != '\n');

    if (!len)
    {
        *line = HeapReAlloc(GetProcessHeap(), 0, *line, *alloc = 1);
        **line = '\0';
    }

    /* Remove leading and trailing whitespace from the line */
    stripwhite(*line);
    return 1;
}

int input_read_line(const char* pfx, char* buf, int size)
{
    char*       line = NULL;
    size_t      len = 0;

    /* first alloc of our current buffer */
    line = HeapAlloc(GetProcessHeap(), 0, len = 2);
    assert(line);
    line[0] = '\n';
    line[1] = '\0';		      

    input_fetch_entire_line(pfx, &line, &len, FALSE);
    len = strlen(line);
    /* remove trailing \n */
    if (len > 0 && line[len - 1] == '\n') len--;
    len = min(size - 1, len);
    memcpy(buf, line, len);
    buf[len] = '\0';
    HeapFree(GetProcessHeap(), 0, line);
    return 1;
}

/***********************************************************************
 *           parser
 *
 * Debugger command line parser
 */
void	parser(const char* filename)
{
    BOOL 	        ret_ok;
    HANDLE              in_copy  = dbg_parser_input;
    HANDLE              out_copy = dbg_parser_output;

#ifdef YYDEBUG
    yydebug = 0;
#endif

    ret_ok = FALSE;

    if (filename)
    {
        HANDLE  h = CreateFile(filename, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0L, 0);
        if (h == INVALID_HANDLE_VALUE) return;
        dbg_parser_output = 0;
        dbg_parser_input  = h;
    }
    else
    {
        dbg_parser_output = GetStdHandle(STD_OUTPUT_HANDLE);
        dbg_parser_input  = GetStdHandle(STD_INPUT_HANDLE);
    }

    do
    {
       __TRY
       {
	  ret_ok = TRUE;
	  yyparse();
       }
       __EXCEPT(wine_dbg_cmd)
       {
	  ret_ok = FALSE;
       }
       __ENDTRY;
       lexeme_flush();
    } while (!ret_ok);

    if (filename) CloseHandle(dbg_parser_input);
    dbg_parser_input  = in_copy;
    dbg_parser_output = out_copy;
}

int yyerror(const char* s)
{
    dbg_printf("%s\n", s);
    return 0;
}

module regexp9;

import std::io;

alias Rune = Char32;

faultdef REG_OUT_OF_MEMORY, REG_UNMATCHED_LEFT_PAREN;

//
// regexp9.h
//

<*
 Sub expression matches
*>
struct Resub
{
	union s
	{
		char *sp;
		Rune *rsp;
	}
	union e
	{
		char *ep;
		Rune *rep;
	}
}

 const usz NCCRUNE = 64;
<*
 character class, each pair of rune's defines a range
*>
struct Reclass
{
	Rune         *end;
	Rune[NCCRUNE] spans;
}

<*
 Machine instructions
*>
struct Reinst
{
	OpCode	type;
	union	u1
	{
		Reclass *cp;		/* class pointer */
		Rune     r;		/* character */
		OpCode   subid;		/* sub-expression id for RBRA and LBRA */
		Reinst  *right;		/* right child of OR */
	}
	union   u2			/* regexp relies on these two being in the same union */
	{
		Reinst *left;		/* left child of OR */
		Reinst *next;		/* next instruction for CAT & LBRA */
	}
}

const usz MAXCLASS = 16;
<*
 Reprogram definition
*>
struct Reprog
{
	Reinst     *startinst;	/* start pc */
	Reclass[MAXCLASS] class;	/* .data */
	Reinst[5]   firstinst;	/* .text */
}


//
// regcomp.h
//
const usz NSUBEXP = 32;

struct Resublist
{
	Resub[NSUBEXP] m;
}

<*
 Actions and Tokens (Reinst types)

	02xx are operators, value == precedence
	03xx are tokens, i.e. operands for operators
*>
enum OpCode : const char {
	RUNE		= 0o177,
	<* Bitmask of all operators *>
	OPERATOR	= 0o200,
	<* Start, used for marker on stack *>
	START		= 0o200,
	<* Right bracket, ) *>
	RBRA		= 0o201,
	<* Left bracket, ( *>
	LBRA		= 0o202,
	<* Alternation, | *>
	OR		= 0o203,
	<* Concatentation, implicit operator *>
	CAT		= 0o204,
	<* Closure, * *>
	STAR		= 0o205,
	<* a+ == aa* *>
	PLUS		= 0o206,
	<* a? == a|nothing, i.e. 0 or 1 a's *>
	QUEST		= 0o207,
	<* Any character except newline, . *>
	ANY		= 0o300,
	<* Any character including newline, . *>
	ANYNL		= 0o301,
	<* No operation, internal use only *>
	NOP		= 0o302,
	<* Beginning of line, ^ *>
	BOL		= 0o303,
	<* End of line, $ *>
	EOL		= 0o304,
	<* Character class, [] *>
	CCLASS		= 0o305,
	<* Negated character class, [] *>
	NCCLASS		= 0o306,
	<* Terminate: match found *>
	END		= 0o377,
}

<*
 regexec execution lists
*>
const usz LISTSIZE = 10;
const usz BIGLISTSIZE = (25*LISTSIZE);

struct Relist
{
	<* Reinstruction of the thread *>
	Reinst*   inst;
	<* matched subexpressions in this thread *>
	Resublist se;
}

struct	Reljunk
{
	Relist*[2] relist;
	Relist*[2] reliste;
	int        starttype;
	Rune       startchar;
	char*      starts;
	char*      eol;
	Rune*      rstarts;
	Rune*      reol;
}

//
// regcomp.c
//
// module regexp9::comp;

<*
 Parser Information
*>
struct Node
{
	Reinst* first;
	Reinst* last;
}

<* max rune ranges per character class is nelem(classp->spans)/2 *>
// TODO
// #define NCCRUNE	nelem(classp->spans)

const usz NSTACK = 20;

struct Recomp
{
	Node[NSTACK]   andstack;
	Node          *andp;
	OpCode[NSTACK] atorstack;
	OpCode        *atorp;
	OpCode         cursubid;	/* id of current subexpression */
	OpCode[NSTACK] subidstack;	/* parallel to atorstack */
	OpCode*        subidp;
	bool           lastwasand;	/* Last token was operand */
	int            nbra;
	char*          exprp;		/* pointer to next character in source expression */
	int            lexdone;
	int            nclass;
	Reclass*       classp;
	Reinst*        freep;
	int            errors;
	Rune           yyrune;		/* last lex'd rune */
	Reclass*       yyclassp;	/* last lex'd class */
}

fn void rcerror(Recomp *rc, char *s)
{
	rc.errors++;
	// FIXME: Improve error handling
	// regerror(s);
	// longjmp(regkaboom, 1);
}

fn Reinst* newinst(Recomp *rc, OpCode t)
{
	rc.freep.type = t;
	rc.freep.u2.left = null;
	rc.freep.u1.right = null;
	return rc.freep++;
}

fn void operand(Recomp *rc, OpCode t)
{
	Reinst *i;

	if (rc.lastwasand)
	{
		operator(rc, CAT);	/* catenate is implicit */
	}
	i = newinst(rc, t);

	if (t == CCLASS || t == NCCLASS)
	{
		i.u1.cp = rc.yyclassp;
	}
	if (t == RUNE)
	{
		i.u1.r = rc.yyrune;
	}

	pushand(rc, i, i);
	rc.lastwasand = true;
}

fn void operator(Recomp *rc, OpCode t)
{
	if (t == RBRA && --rc.nbra<0)
	{
		rcerror(rc, "unmatched right paren");
	}
	if (t == LBRA){
		if (++rc.cursubid >= NSUBEXP)
		{
			rcerror (rc, "too many subexpressions");
		}
		rc.nbra++;
		if (rc.lastwasand)
		{
			operator(rc, CAT);
		}
	}
	else
	{
		evaluntil(rc, t);
	}
	if (t != RBRA)
	{
		pushator(rc, t);
	}
	rc.lastwasand = false;
	if (t == STAR || t == QUEST || t == PLUS || t == RBRA)
	{
		rc.lastwasand = true;	/* these look like operands */
	}
}

fn void regerr2(char *s, int c)
{
	// FIXME
	// char[100] buf;
	// char *cp = buf;
	// while(*s)
	// {
	// 	*cp++ = *s++;
	// }
	// *cp++ = c;
	// *cp = '\0';
	// rcerror(buf);
}

fn void cant(char *s)
{
	// FIXME
	// char[100] buf;
	// strcpy(buf, "can't happen: ");
	// strcat(buf, s);
	// rcerror(buf);
}

fn void pushand(Recomp *rc, Reinst *f, Reinst *l)
{
	if(rc.andp > &rc.andstack[NSTACK-1])
	{
		cant("operand stack overflow");
	}
	rc.andp.first = f;
	rc.andp.last = l;
	rc.andp++;
}

fn void pushator(Recomp *rc, OpCode t)
{
	if(rc.atorp > &rc.atorstack[NSTACK-1])
	{
		cant("operator stack overflow");
	}
	*rc.atorp++ = t;
	*rc.subidp++ = rc.cursubid;
}

fn Node* popand(Recomp *rc, int op)
{
	Reinst *inst;

	if(rc.andp <= &rc.andstack[0])
	{
		regerr2("missing operand for ", op);
		inst = newinst(rc, NOP);
		pushand(rc, inst, inst);
	}
	return --rc.andp;
}

fn OpCode popator(Recomp *rc)
{
	if(rc.atorp <= &rc.atorstack[0])
	{
		cant("operator stack underflow");
	}
	--rc.subidp;
	return *--rc.atorp;
}

fn void evaluntil(Recomp *rc, OpCode pri)
{
	Node *op1; Node *op2;
	Reinst *inst1; Reinst *inst2;

	while (pri == RBRA || rc.atorp[-1] >= pri){
		switch(popator(rc))
		{
		default:
			rcerror(rc, "unknown operator in evaluntil");
		case LBRA:		/* must have been RBRA */
			op1 = popand(rc, '(');
			inst2 = newinst(rc, RBRA);
			inst2.u1.subid = *rc.subidp;
			op1.last.u2.next = inst2;
			inst1 = newinst(rc, LBRA);
			inst1.u1.subid = *rc.subidp;
			inst1.u2.next = op1.first;
			pushand(rc, inst1, inst2);
			return;
		case OR:
			op2 = popand(rc, '|');
			op1 = popand(rc, '|');
			inst2 = newinst(rc, NOP);
			op2.last.u2.next = inst2;
			op1.last.u2.next = inst2;
			inst1 = newinst(rc, OR);
			inst1.u1.right = op1.first;
			inst1.u2.left = op2.first;
			pushand(rc, inst1, inst2);
		case CAT:
			op2 = popand(rc, 0);
			op1 = popand(rc, 0);
			op1.last.u2.next = op2.first;
			pushand(rc, op1.first, op2.last);
		case STAR:
			op2 = popand(rc, '*');
			inst1 = newinst(rc, OR);
			op2.last.u2.next = inst1;
			inst1.u1.right = op2.first;
			pushand(rc, inst1, inst1);
		case PLUS:
			op2 = popand(rc, '+');
			inst1 = newinst(rc, OR);
			op2.last.u2.next = inst1;
			inst1.u1.right = op2.first;
			pushand(rc, op2.first, inst1);
		case QUEST:
			op2 = popand(rc, '?');
			inst1 = newinst(rc, OR);
			inst2 = newinst(rc, NOP);
			inst1.u2.left = inst2;
			inst1.u1.right = op2.first;
			op2.last.u2.next = inst2;
			pushand(rc, inst1, inst2);
		}
	}
}

fn Reprog* optimize(Recomp *rc, Reprog *pp)
{
	Reinst *inst; Reinst *target;
	int size;
	Reprog *npp;
	Reclass *cl;
	isz diff;

	/*
	 *  get rid of NOOP chains
	 */
	for(inst = &pp.firstinst[0]; inst.type != END; inst++)
	{
		target = inst.u2.next;
		while(target.type == NOP)
		{
			target = target.u2.next;
		}
		inst.u2.next = target;
	}

	/*
	 *  The original allocation is for an area larger than
	 *  necessary.  Reallocate to the actual space used
	 *  and then relocate the code.
	 */
	size = (int)Reprog.sizeof + (int)(rc.freep - &pp.firstinst[0]) * (int)Reinst.sizeof;
	npp = mem::realloc(pp, size);
	if(npp == null || npp == pp)
	{
		return pp;
	}
	diff = (char *)npp - (char *)pp;
	rc.freep = (Reinst *)((char *)rc.freep + diff);
	for (inst = &npp.firstinst[0]; inst < rc.freep; inst++)
	{
		switch(inst.type)
		{
		case OR:
		case STAR:
		case PLUS:
		case QUEST:
			inst.u1.right = (void*)((char*)inst.u1.right + diff);
		case CCLASS:
		case NCCLASS:
			inst.u1.right = (void*)((char*)inst.u1.right + diff);
			cl = inst.u1.cp;
			cl.end = (void*)((char*)cl.end + diff);
		}
		inst.u2.left = (void*)((char*)inst.u2.left + diff);
	}
	npp.startinst = (void*)((char*)npp.startinst + diff);
	return npp;
}

fn void dumpstack(Recomp *rc)
{
	Node *stk;
	OpCode *ip;

	io::printf("operators\n");
	for (ip = &rc.atorstack; ip < rc.atorp; ip++)
	{
		io::printf("0%o\n", *ip);
	}
	io::printf("operands\n");
	for (stk = &rc.andstack; stk < rc.andp; stk++)
	{
		io::printf("0%o\t0%o\n", stk.first.type, stk.last.type);
	}
}

fn void dump(Reprog *pp)
{
	Reinst *l;
	Rune *p;

	l = &pp.firstinst[0];
	do {
		io::printf("%d:\t0%o\t%d\t%d", l - &pp.firstinst[0], l.type,
			l.u2.left - &pp.firstinst[0], l.u1.right - &pp.firstinst[0]);
		if (l.type == RUNE)
		{
			io::printf("\t%c\n", l.u1.r);
		}
		else if(l.type == CCLASS || l.type == NCCLASS)
		{
			io::printf("\t[");
			if (l.type == NCCLASS)
			{
				io::printf("^");
			}
			for (p = &l.u1.cp.spans[0]; p < l.u1.cp.end; p += 2)
			{
				if(p[0] == p[1])
				{
					io::printf("%c", p[0]);
				}
				else
				{
					io::printf("%c-%c", p[0], p[1]);
				}
			}
			io::printf("]\n");
		}
		else
		{
			io::printf("\n");
		}
	} while (l++.type);
}

fn Reclass* newclass(Recomp *rc)
{
	if (rc.nclass >= MAXCLASS)
	{
		rcerror(rc, "too many character classes; increase Reprog.class size");
	}
	return &(rc.classp[rc.nclass++]);
}

// Mock Plan9's chartorune
fn usz chartorune(Rune* rp, char* s)
{
	usz size = 4;
	if (try rune = conv::utf8_to_char32(s, &size))
	{
		*rp = rune;
		return size;
	}
	*rp = 0;
	return 0;
}

fn int nextc(Recomp *rc, Rune *rp)
{
	if (rc.lexdone)
	{
		*rp = 0;
		return 1;
	}
	rc.exprp += chartorune(rp, rc.exprp);
	if (*rp == '\\')
	{
		rc.exprp += chartorune(rp, rc.exprp);
		return 1;
	}
	if (*rp == 0)
	{
		rc.lexdone = 1;
	}
	return 0;
}

fn OpCode lex(Recomp *rc, int literal, OpCode dot_type)
{
	int quoted;

	quoted = nextc(rc, &rc.yyrune);
	if (literal || quoted)
	{
		if(rc.yyrune == 0) return END;
		return RUNE;
	}

	switch(rc.yyrune)
	{
	case 0:
		return END;
	case '*':
		return STAR;
	case '?':
		return QUEST;
	case '+':
		return PLUS;
	case '|':
		return OR;
	case '.':
		return dot_type;
	case '(':
		return LBRA;
	case ')':
		return RBRA;
	case '^':
		return BOL;
	case '$':
		return EOL;
	case '[':
		return bldcclass(rc);
	}
	return RUNE;
}

<*
 Helper function: nelem
*>
macro usz nelem(list)
{
	return $sizeof(list) / $sizeof(list[0]);
}

fn OpCode bldcclass(Recomp *rc)
{
	OpCode type;
	Rune[NCCRUNE] r;
	Rune *p; Rune *ep; Rune *np;
	Rune rune;
	int quoted;

	/* we have already seen the '[' */
	type = CCLASS;
	rc.yyclassp = newclass(rc);

	/* look ahead for negation */
	/* SPECIAL CASE!!! negated classes don't match \n */
	ep = &r[0];
	quoted = nextc(rc, &rune);
	if (!quoted && rune == '^')
	{
		type = NCCLASS;
		quoted = nextc(rc, &rune);
		*ep++ = '\n';
		*ep++ = '\n';
	}

	/* parse class into a set of spans */
	while (ep < &r[NCCRUNE-1])
	{
		if (rune == 0)
		{
			rcerror(rc, "malformed '[]'");
			return 0;
		}
		if (!quoted && rune == ']')
		{
			break;
		}
		if (!quoted && rune == '-')
		{
			if (ep == &r[0])
			{
				rcerror(rc, "malformed '[]'");
				return 0;
			}
			quoted = nextc(rc, &rune);
			if ((!quoted && rune == ']') || rune == 0)
			{
				rcerror(rc, "malformed '[]'");
				return 0;
			}
			*(ep-1) = rune;
		}
		else
		{
			*ep++ = rune;
			*ep++ = rune;
		}
		quoted = nextc(rc, &rune);
	}
	if (ep >= &r[NCCRUNE-1])
	{
		rcerror(rc, "char class too large; increase Reclass.spans size");
		return 0;
	}

	/* sort on span start */
	for (p = &r[0]; p < ep; p += 2)
	{
		for (np = p; np < ep; np += 2)
		{
			if (*np < *p)
			{
				rune = np[0];
				np[0] = p[0];
				p[0] = rune;
				rune = np[1];
				np[1] = p[1];
				p[1] = rune;
			}
		}
	}

	/* merge spans */
	np = &rc.yyclassp.spans[0];
	p = &r[0];
	if (&r[0] == ep)
	{
		rc.yyclassp.end = np;
	}
	else
	{
		np[0] = *p++;
		np[1] = *p++;
		for(; p < ep; p += 2)
		{
			/* overlapping or adjacent ranges? */
			if (p[0] <= np[1] + 1)
			{
				if (p[1] >= np[1])
				{
					np[1] = p[1];	/* coalesce */
				}
			}
			else
			{
				np += 2;
				np[0] = p[0];
				np[1] = p[1];
			}
		}
		rc.yyclassp.end = np+2;
	}

	return type;
}

fn Reprog*? regcomp1(String s, int literal, OpCode dot_type)
{
	OpCode token;
	Reprog *pp;
	Recomp rc;

	/* get memory for the program */
	pp = mem::malloc(Reprog.sizeof + 6 * Reinst.sizeof * s.len);
	if (pp == null){
		return REG_OUT_OF_MEMORY?;
	}
	defer catch mem::free(pp);

	rc.freep = &pp.firstinst[0];
	rc.classp = &pp.class[0];
	rc.errors = 0;

	// TODO: what to do with that?
	// if(setjmp(regkaboom))
	// 	goto out;

	/* compile it */
	rc.lexdone = 0;
	rc.exprp = s.ptr;
	rc.nclass = 0;
	rc.nbra = 0;
	rc.atorp = &rc.atorstack[0];
	rc.andp = &rc.andstack[0];
	rc.subidp = &rc.subidstack[0];
	rc.lastwasand = false;
	rc.cursubid = 0;

	/* Start with a low priority operator to prime parser */
	pushator(&rc, OpCode.START-1);
	while((token = lex(&rc, literal, dot_type)) != END)
	{
		if (((int)token&0300) == (int)OpCode.OPERATOR)
		{
			operator(&rc, token);
		}
		else
		{
			operand(&rc, token);
		}
	}

	/* Close with a low priority operator */
	evaluntil(&rc, START);

	/* Force END */
	operand(&rc, END);
	evaluntil(&rc, START);

	// TODO: only for debug
	dumpstack(&rc);

	if(rc.nbra)
	{
		return REG_UNMATCHED_LEFT_PAREN?;
	}
	--rc.andp;	/* points to first and only operand */
	pp.startinst = rc.andp.first;

	// TODO: only for debug
	dump(pp);

	pp = optimize(&rc, pp);

	// TODO: only for debug
	io::printf("start: %d\n", rc.andp.first - &pp.firstinst[0]);
	dump(pp);

	return pp;
}

//
// Public API
//

fn Reprog*? regcomp(String s)
{
	return regcomp1(s, 0, ANY);
}

fn Reprog*? regcomplit(String s)
{
	return regcomp1(s, 1, ANY);
}

fn Reprog*? regcompnl(String s)
{
	return regcomp1(s, 0, ANYNL);
}



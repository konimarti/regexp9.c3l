module regexp9;

import std::io;
import regexp9::plan9 @public;

alias Rune = Char32;
const Rune RUNESELF = 0x80;
const Rune RUNESYNC = 0x80;

faultdef REG_OUT_OF_MEMORY, REG_UNMATCHED_LEFT_PAREN, REG_EXEC_ERROR;

//
// C3 API
//

<*
 Compile the pattern in the zero-terminated string s into a program.

 The memory for Reprog is allocated on the provided allocator and needs to be
 freed by the caller.
*>
fn Reprog*? compile(Allocator allocator, ZString s) @inline => regcomp1(allocator, s, false, ANY);
fn Reprog*? tcompile(ZString s) @inline => compile(tmem, s);

<*
 Run the compiled regular expression against the zero-terminated string str.
 Capture groups (Resub[]) store a reference to string str.
 Returns true when matched.
*>
fn bool? match(Reprog *progp, ZString str, Resub[] subs = {})
{
	int ret;
	ret = regexec(progp, str, subs.ptr, subs.len);
	switch
	{
		case ret > 0: return true;
		case ret == 0: return false;
		default: return REG_EXEC_ERROR?;
	}
}

<*
 Returns true if string s matches zero-terminated regular-expression pattern.
*>
fn bool? match_string(ZString pattern, String s) => @pool()
{
	if (try prog = tcompile(pattern))
	{
		Resub rs;
		if (try ok = match(prog, s.zstr_tcopy(), (&rs)[:1]) && ok)
		{
			return rs.match() == s;
		}
	}
	return false;
}

//
// Plan9 API
//

fn Reprog*? regcomp(ZString s)
{
	return regcomp1(mem, s, false, ANY);
}

fn Reprog*? regcomplit(ZString s)
{
	return regcomp1(mem, s, true, ANY);
}

fn Reprog*? regcompnl(ZString s)
{
	return regcomp1(mem, s, false, ANYNL);
}

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

fn String Resub.match(&self)
{
	isz len;
	if (self.e.ep == null || self.s.sp == null) return "";
	len = self.e.ep - self.s.sp;
	if (len < 0) return "";
	return (String)self.s.sp[:len];
}

const usz NCCRUNE = 64;
const usz MAXCLASS = 16;

<*
 Reprogram definition
*>
struct Reprog
{
	Reinst           *startinst;	/* start pc */
	Reclass[MAXCLASS] class;	/* .data */
	Reinst[5]         firstinst;	/* .text */
}


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
		int      subid;		/* sub-expression id for RBRA and LBRA */
		Reinst  *right;		/* right child of OR */
	}
	union   u2			/* regexp relies on these two being in the same union */
	{
		Reinst *left;		/* left child of OR */
		Reinst *next;		/* next instruction for CAT & LBRA */
	}
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
	OpCode     starttype;
	Rune       startchar;
	char*      starts;
	char*      eol;
	Rune*      rstarts;
	Rune*      reol;
}

//
// regcomp.c
//

<*
 Parser Information
*>
struct Node
{
	Reinst* first;
	Reinst* last;
}

const usz NSTACK = 20;

struct Recomp
{
	Node[NSTACK]   andstack;
	Node          *andp;
	OpCode[NSTACK] atorstack;
	OpCode        *atorp;
	int            cursubid;	/* id of current subexpression */
	int[NSTACK]    subidstack;	/* parallel to atorstack */
	int*           subidp;
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
	Allocator      allocator;
}

fn void rcerror(Recomp *rc, String s)
{
	rc.errors++;
	io::eprintfn("regexp9 error: %s", s);
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
	*(rc.atorp++) = t;
	*(rc.subidp++) = rc.cursubid;
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

	while (pri == RBRA || rc.atorp[-1] >= pri)
	{
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
	for (inst = &pp.firstinst[0]; inst.type != END; inst++)
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
	npp = allocator::realloc(rc.allocator, pp, size);
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
	for (ip = &rc.atorstack[0]; ip < rc.atorp; ip++)
	{
		io::printf("0%o\n", *ip);
	}
	io::printf("operands\n");
	for (stk = &rc.andstack[0]; stk < rc.andp; stk++)
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
	// TODO: Check why the != END part is necessary here; it's not used in plan9
	} while ((l++).type != END);
}

fn Reclass* newclass(Recomp *rc)
{
	if (rc.nclass >= MAXCLASS)
	{
		rcerror(rc, "too many character classes; increase Reprog.class size");
	}
	return &(rc.classp[rc.nclass++]);
}

fn int nextc(Recomp *rc, Rune *rp)
{
	if (rc.lexdone)
	{
		*rp = 0;
		return 1;
	}
	rc.exprp += plan9::chartorune(rp, rc.exprp);
	if (*rp == '\\')
	{
		rc.exprp += plan9::chartorune(rp, rc.exprp);
		return 1;
	}
	if (*rp == 0)
	{
		rc.lexdone = 1;
	}
	return 0;
}

fn OpCode lex(Recomp *rc, bool literal, OpCode dot_type)
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

fn Reprog*? regcomp1(Allocator allocator, ZString s, bool literal, OpCode dot_type)
{
	OpCode token;
	Reprog *pp;
	Recomp rc;

	/* get memory for the program */
	pp = allocator::malloc(allocator, Reprog.sizeof + 6 * Reinst.sizeof * s.len());
	if (pp == null){
		return REG_OUT_OF_MEMORY?;
	}
	defer catch allocator::free(allocator, pp);

	rc.allocator = allocator;
	rc.freep = &pp.firstinst[0];
	rc.classp = &pp.class[0];
	rc.errors = 0;

	// TODO: what to do with that?
	// if(setjmp(regkaboom))
	// 	goto out;

	/* compile it */
	rc.lexdone = 0;
	rc.exprp = s;
	rc.nclass = 0;
	rc.nbra = 0;
	rc.atorp = &rc.atorstack[0];
	rc.andp = &rc.andstack[0];
	rc.subidp = &rc.subidstack[0];
	rc.lastwasand = false;
	rc.cursubid = 0;

	/* Start with a low priority operator to prime parser */
	pushator(&rc, OpCode.START - 1);
	while((token = lex(&rc, literal, dot_type)) != END)
	{
		if ((((char)token)&0o300) == (char)OpCode.OPERATOR)
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

	$if $feature(DEBUG):
	dumpstack(&rc);
	$endif

	if(rc.nbra)
	{
		return REG_UNMATCHED_LEFT_PAREN?;
	}
	--rc.andp;	/* points to first and only operand */
	pp.startinst = rc.andp.first;

	$if $feature(DEBUG):
	dump(pp);
	$endif

	pp = optimize(&rc, pp);

	$if $feature(DEBUG):
	io::printf("start: %d\n", rc.andp.first - &pp.firstinst[0]);
	dump(pp);
	$endif

	return pp;
}

//
// regaux.c
//


<*
 Save a new match in mp
*>
fn void _renewmatch(Resub *mp, int ms, Resublist *sp)
{
	int i;

	if(mp == null || ms <= 0)
	{
		return;
	}
	if(mp[0].s.sp == null || sp.m[0].s.sp<mp[0].s.sp ||
	   (sp.m[0].s.sp==mp[0].s.sp && sp.m[0].e.ep>mp[0].e.ep))
	   {
		for (i = 0; i < ms && i < NSUBEXP; i++)
		{
			mp[i] = sp.m[i];
		}
		for (; i < ms; i++)
		{
			mp[i].s.sp = mp[i].e.ep = null;
		}
	}
}

<*
 Note optimization in _renewthread:
 	*lp must be pending when _renewthread called; if *l has been looked
		at already, the optimization is a bug.
*>
fn Relist* _renewthread(
	Relist *lp,	/* _relist to add to */
	Reinst *ip,		/* instruction to add */
	int ms,
	Resublist *sep)		/* pointers to subexpressions */
{
	Relist *p;

	for (p=lp; p.inst; p++)
	{
		if (p.inst == ip)
		{
			if (sep.m[0].s.sp < p.se.m[0].s.sp)
			{
				if(ms > 1)
				{
					p.se = *sep;
				}
				else
				{
					p.se.m[0] = sep.m[0];
				}
			}
			return null;
		}
	}
	p.inst = ip;
	if(ms > 1)
	{
		p.se = *sep;
	}
	else
	{
		p.se.m[0] = sep.m[0];
	}
	(++p).inst = null;
	return p;
}

<*
 Same as renewthread, but called with
 initial empty start pointer.
*>
fn Relist* _renewemptythread(
	Relist *lp,	/* _relist to add to */
	Reinst *ip,	/* instruction to add */
	int ms,
	char *sp,    	/* pointers to subexpressions */
)
{
	Relist *p;

	for (p  =lp; p.inst; p++)
	{
		if (p.inst == ip)
		{
			if (sp < p.se.m[0].s.sp) {
				if(ms > 1)
				{
					mem::set(&p.se, 0, $sizeof(p.se));
				}
				p.se.m[0].s.sp = sp;
			}
			return null;
		}
	}
	p.inst = ip;
	if(ms > 1)
	{
		mem::set(&p.se, 0, $sizeof(p.se));
	}
	p.se.m[0].s.sp = sp;
	(++p).inst = null;
	return p;
}

fn Relist* _rrenewemptythread(
	Relist *lp,	/* _relist to add to */
	Reinst *ip,	/* instruction to add */
	int ms,
	Rune *rsp,	/* pointers to subexpressions */
)
{
	Relist *p;

	for (p = lp; p.inst; p++)
	{
		if (p.inst == ip)
		{
			if (rsp < p.se.m[0].s.rsp)
			{
				if(ms > 1)
				{
					mem::set(&p.se, 0, $sizeof(p.se));
				}
				p.se.m[0].s.rsp = rsp;
			}
			return null;
		}
	}
	p.inst = ip;
	if(ms > 1)
	{
		mem::set(&p.se, 0, $sizeof(p.se));
	}
	p.se.m[0].s.rsp = rsp;
	(++p).inst = null;
	return p;
}

//
// regexec.c
//

<*
  return	0 if no match
		>0 if a match
		<0 if we ran out of _relist space
*>
fn int regexec1(
	Reprog *progp,	/* program to run */
	char *bol,	/* string to run machine on */
	Resub *mp,	/* subexpression elements */
	int ms,		/* number of elements at mp */
	Reljunk *j
)
{
	int flag = 0;
	Reinst *inst;
	Relist *tlp;
	char *s;
	int i;
	bool checkstart;
	Rune r; Rune *rp; Rune *ep;
	int n;
	Relist* tl;		/* This list, next list */
	Relist* nl;
	Relist* tle;		/* ends of this and next list */
	Relist* nle;
	int match;
	char *p;

	match = 0;
	checkstart = j.starttype > 0;
	if (mp)
	{
		for (i = 0; i < ms; i++)
		{
			mp[i].s.sp = null;
			mp[i].e.ep = null;
		}
	}
	j.relist[0][0].inst = null;
	j.relist[1][0].inst = null;

	/* Execute machine once for each character, including terminal NUL */
	s = j.starts;
	do {
		/* fast check for first char */
		if (checkstart)
		{
			switch (j.starttype)
			{
			case RUNE:
				p = plan9::utfrune(s, j.startchar);
				if (p == null || s == j.eol)
				{
					return match;
				}
				s = p;
			case BOL:
				if (s == bol) break;
				p = plan9::utfrune(s, '\n');
				if (p == null || s == j.eol)
				{
					return match;
				}
				s = p+1;
			}
		}
		r = (Rune)*s;
		if (r < RUNESELF)
		{
			n = 1;
		}
		else
		{
			n = (int)plan9::chartorune(&r, s);
		}

		/* switch run lists */
		tl = j.relist[flag];
		tle = j.reliste[flag];
		nl = j.relist[flag^=1];
		nle = j.reliste[flag];
		nl.inst = null;

		/* Add first instruction to current list */
		if(match == 0)
		{
			_renewemptythread(tl, progp.startinst, ms, s);
		}

		/* Execute machine until current list is empty */
		for (tlp = tl; tlp.inst; tlp++)
		{
			for (inst = tlp.inst; ; inst = inst.u2.next)
			{
				switch(inst.type)
				{
				case RUNE:	/* regular character */
					if (inst.u1.r == r)
					{
						if (_renewthread(nl, inst.u2.next, ms, &tlp.se) == nle)
						{
							return -1;
						}
					}
				case LBRA:
					tlp.se.m[inst.u1.subid].s.sp = s;
					continue;
				case RBRA:
					tlp.se.m[inst.u1.subid].e.ep = s;
					continue;
				case ANY:
					if(r != '\n')
					{
						if(_renewthread(nl, inst.u2.next, ms, &tlp.se) == nle)
						{
							return -1;
						}
					}
				case ANYNL:
					if (_renewthread(nl, inst.u2.next, ms, &tlp.se) == nle)
					{
							return -1;
					}
				case BOL:
					if (s == bol || *(s-1) == '\n')
					{
						continue;
					}
				case EOL:
					if (s == j.eol || r == 0 || r == '\n')
					{
						continue;
					}
				case CCLASS:
					ep = inst.u1.cp.end;
					for (rp = &inst.u1.cp.spans[0]; rp < ep; rp += 2)
					{
						if (r >= rp[0] && r <= rp[1])
						{
							if (_renewthread(nl, inst.u2.next, ms, &tlp.se) == nle)
							{
								return -1;
							}
						}
					}
				case NCCLASS:
					ep = inst.u1.cp.end;
					for (rp = &inst.u1.cp.spans[0]; rp < ep; rp += 2)
					{
						if (r >= rp[0] && r <= rp[1])
						{
							break;
						}
					}
					if (rp == ep)
					{
						if (_renewthread(nl, inst.u2.next, ms, &tlp.se) == nle)
						{
							return -1;
						}
					}
				case OR:
					/* evaluate right choice later */
					if (_renewthread(tlp, inst.u1.right, ms, &tlp.se) == tle)
					{
						return -1;
					}
					/* efficiency: advance and re-evaluate */
					continue;
				case END:	/* Match! */
					match = 1;
					tlp.se.m[0].e.ep = s;
					if (mp != null)
					{
						_renewmatch(mp, ms, &tlp.se);
					}
				}
				break;
			}
		}

		if(s == j.eol)
		{
			break;
		}

		checkstart = j.starttype && nl.inst==null;

		s += n;
	} while(r);
	return match;
}

fn int regexec2(
	Reprog *progp,	/* program to run */
	char *bol,	/* string to run machine on */
	Resub *mp,	/* subexpression elements */
	int ms,		/* number of elements at mp */
	Reljunk *j
)
{
	int rv;
	Relist *relist0; Relist *relist1;

	/* mark space */
	relist0 = mem::malloc(BIGLISTSIZE * Relist.sizeof);
	if (relist0 == null)
	{
		return -1;
	}
	relist1 = mem::malloc(BIGLISTSIZE * Relist.sizeof);
	if (relist1 == null)
	{
		free(relist0);
		return -1;
	}
	j.relist[0] = relist0;
	j.relist[1] = relist1;
	j.reliste[0] = relist0 + BIGLISTSIZE - 2;
	j.reliste[1] = relist1 + BIGLISTSIZE - 2;

	rv = regexec1(progp, bol, mp, ms, j);
	mem::free(relist0);
	mem::free(relist1);
	return rv;
}

fn int regexec(
	Reprog *progp,	/* program to run */
	char *bol,	/* string to run machine on */
	Resub *mp,	/* subexpression elements */
	int ms,		/* number of elements at mp */
)
{
	Reljunk j;
	Relist[LISTSIZE] relist0; Relist[LISTSIZE] relist1;
	int rv;

	/*
 	 *  use user-specified starting/ending location if specified
	 */
	j.starts = bol;
	j.eol = null;
	if (mp && ms > 0)
	{
		if (mp.s.sp) j.starts = mp.s.sp;
		if (mp.e.ep) j.eol = mp.e.ep;
	}
	j.starttype = 0;
	j.startchar = 0;
	if (progp.startinst.type == RUNE && progp.startinst.u1.r < RUNESELF)
	{
		j.starttype = RUNE;
		j.startchar = progp.startinst.u1.r;
	}
	if (progp.startinst.type == BOL)
	{
		j.starttype = BOL;
	}

	/* mark space */
	j.relist[0] = &relist0[0];
	j.relist[1] = &relist1[0];
	j.reliste[0] = &relist0[0] + nelem(relist0) - 2;
	j.reliste[1] = &relist1[0] + nelem(relist1) - 2;

	rv = regexec1(progp, bol, mp, ms, &j);
	if(rv >= 0) return rv;

	rv = regexec2(progp, bol, mp, ms, &j);
	if(rv >= 0) return rv;

	return -1;
}

//
// regsub.c
//

<*
 Substitute into one string using the matches from the last regexec()
*>
fn void regsub(
	char *sp,	/* source string */
	char *dp,	/* destination string */
	int dlen,
	Resub *mp,	/* subexpression elements */
	int ms,   	/* number of elements pointed to by mp */
)
{
	char *ssp; char *ep;
	int i;

	ep = dp + dlen - 1;
	while (*sp != '\0')
	{
		if (*sp == '\\')
		{
			switch(*++sp)
			{
			case '0':
			case '1':
			case '2':
			case '3':
			case '4':
			case '5':
			case '6':
			case '7':
			case '8':
			case '9':
				i = *sp - '0';
				if (mp != null && mp[i].s.sp != null && ms > i)
				{
					for(ssp = mp[i].s.sp; ssp < mp[i].e.ep; ssp++)
					{
						if (dp < ep)
						{
							*dp++ = *ssp;
						}
					}
				}
			case '\\':
				if (dp < ep)
				{
					*dp++ = '\\';
				}
			case '\0':
				sp--;
			default:
				if(dp < ep)
				{
					*dp++ = *sp;
				}
			}
		}
		else if (*sp == '&')
		{
			if (mp != null && mp[0].s.sp != null && ms > 0)
			{
				for(ssp = mp[0].s.sp; ssp < mp[0].e.ep; ssp++)
				{
					if(dp < ep)
					{
						*dp++ = *ssp;
					}
				}
			}
		}
		else
		{
			if(dp < ep)
			{
				*dp++ = *sp;
			}
		}
		sp++;
	}
	*dp = '\0';
}

<*
 Substitute into one string using the matches from the last regexec(). Returned
 string is allocated on the provided allocator.
*>
fn String substitute(
	Allocator allocator,
	String s,	/* source string */
	Resub[] mp,	/* subexpression elements */
) => @pool()
{
	char pos;
	DString buf = dstring::temp();
	for (usz i = 0; i < s.len; i++)
	{
		if (s[i] == '\\' && i + 1 < s.len)
		{
			i++; // Consume \
			switch(s[i])
			{
			case '0': case '1': case '2': case '3': case '4':
			case '5': case '6': case '7': case '8': case '9':
				pos = s[i] - '0';
				if (pos < mp.len)
				{
					buf.append_chars(mp[pos].match());
				}
				else
				{
					nextcase;
				}
			default:
				buf.append_char(s[i]);
			}
		}
		else if (s[i] == '&' && mp.len)
		{
			buf.append_chars(mp[0].match());
		}
		else
		{
			buf.append_char(s[i]);
		}
	}
	return buf.copy_str(allocator);
}
fn String tsubstiute(String s, Resub[] mp) => substitute(tmem, s, mp);


<*
 Utility functions ported from Plan9
*>
module regexp9::plan9 @private;

import libc;

fn char* utfrune(char *s, long c)
{
	long c1;
	Rune r;
	usz n;

	if(c < regexp9::RUNESYNC)		/* not part of utf sequence */
	{
		return libc::strchr(s, (CInt)c);
	}

	for(;;) {
		c1 = *(char*)s;
		if(c1 < regexp9::RUNESELF) {	/* one byte rune */
			if(c1 == 0) return null;
			if(c1 == c) return s;
			s++;
			continue;
		}
		n = chartorune(&r, s);
		if(r == c) return s;
		s += n;
	}
}

fn usz chartorune(Rune* rp, char* s)
{
	usz size = 4;
	if (try rune = conv::utf8_to_char32(s, &size) && *s)
	{
		*rp = rune;
		return size;
	}
	*rp = 0;
	return 0;
}


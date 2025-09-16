module regexp9_test @test;

import std::io;
import regexp9;

struct TestCase
{
	ZString re;
	ZString s;
	Reprog *p;
}

TestCase[*] tests = {
	{ "^[^!@]+$", "/bin/upas/aliasmail '&'", null },
	{ "^local!(.*)$", "/mail/box/\\1/mbox", null },
	{ "^plan9!(.*)$", "\\1", null },
	{ "^helix!(.*)$", "\\1", null },
	{ "^([^!]+)@([^!@]+)$", "\\2!\\1", null },
	{ "^(uk\\.[^!]*)(!.*)$", "/bin/upas/uk2uk '\\1' '\\2'", null },
	{ "^[^!]*\\.[^!]*!.*$", "inet!&", null },
	{ "^☺$", "smiley", null },
	{ "^(coma|research|pipe|pyxis|inet|hunny|gauss)!(.*)$", "/mail/lib/qmail '\\s' 'net!\\1' '\\2'", null },
	{ "^.*$", "/mail/lib/qmail '\\s' 'net!research' '&'", null },
	{ "", "", null },
	{ "([a-b]*)", "matched str: '&'", null },
};

fn void regexp9_test()
{
	Resub[10] rs;
	char[128] dst;
	ZString str = "abab";
	foreach (&tp : tests)
	{
		io::printfn("regexp: %s", tp.re);
		io::printfn("string: %s", str);
		tp.p = regexp9::regcomp(tp.re)!!;

		mem::set(rs[..], 0, $sizeof(rs));

		int ret = regexp9::regexec(tp.p, str, rs[..], 10);
		assert(ret >= 0, "regexec returned error: %d", ret);
		if (ret)
		{
			regexp9::regsub(tp.s, dst[..], $sizeof(dst), rs[..], 10);
			io::printfn("   sub: %s -> %s", tp.s, (ZString)dst[..]);

			io::printfn("-- %d matches --", ret);
		}
		else
		{
			io::printn("-- no match --");
		}

		mem::free(tp.p);
	}
	// assert(false);
}

fn void regexp9_test_submatches()
{
	usz len;
	String match;
	Resub[4] rs;

	mem::set(rs[..], 0, $sizeof(rs));

	Reprog *reprog = regexp9::regcomp("([0-9]+)-([0-9]+)-([0-9]+)")!!;
	defer mem::free(reprog);
	assert(regexp9::regexec(reprog, "650-253-0001", rs[..], 4) >= 0);

	String[4] want = {"650-253-0001", "650", "253", "0001"};
	for (usz i = 0; i < 4; i++)
	{
		len = rs[i].e.ep - rs[i].s.sp;
		match = (String)rs[i].s.sp[:len];
		assert(match == want[i], "got: %s, want: %s", match, want[i]);
	}
}

fn void regexp9_test_restarts()
{
	usz len, want;
	String match;
	int ret;
	Resub rs;

	Reprog *reprog = regexp9::regcomp("ab")!!;
	defer mem::free(reprog);

	want = 0;
	ZString str = "abababab";
	while ((ret = regexp9::regexec(reprog, str, &rs, 1)) && ret){
		assert(ret >= 0);
		len = rs.e.ep - rs.s.sp;
		match = (String)rs.s.sp[:len];
		assert(match == "ab");
		want++;
		rs.s.sp = rs.e.ep;
		rs.e.ep = null;
	}
	assert(want == 4);
}

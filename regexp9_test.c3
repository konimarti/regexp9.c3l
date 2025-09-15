module regexp9_test @test;

import regexp9;

struct TestCase
{
	String re;
	String s;
	Reprog *p;
}

TestCase[] tests = {
	{ "^[^!@]+$", "/bin/upas/aliasmail '&'", null },
	{ "^local!(.*)$", "/mail/box/\\1/mbox", null },
	{ "^plan9!(.*)$", "\\1", null },
	{ "^helix!(.*)$", "\\1", null },
	{ "^([^!]+)@([^!@]+)$", "\\2!\\1", null },
	{ "^(uk\\.[^!]*)(!.*)$", "/bin/upas/uk2uk '\\1' '\\2'", null },
	{ "^[^!]*\\.[^!]*!.*$", "inet!&", null },
	{ "^\xE2\x98\xBA$", "smiley", null },
	{ "^(coma|research|pipe|pyxis|inet|hunny|gauss)!(.*)$", "/mail/lib/qmail '\\s' 'net!\\1' '\\2'", null },
	{ "^.*$", "/mail/lib/qmail '\\s' 'net!research' '&'", null },
	{ "", "", null },
};

fn void regexp9_test()
{
	Resub[10] rs;
	foreach (&tp : tests)
	{
		tp.p = regexp9::regcomp(tp.re)!!;

		mem::set(&rs[0], 0, $sizeof(rs));
		assert(regexp9::regexec(tp.p, "", &rs[0], 10) != -1, "regexec failed");

		mem::free(tp.p);
	}
}

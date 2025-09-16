module regexp9_bench;

import regexp9;

Reprog* bench1;
Reprog* bench2;

fn void init() @init
{
	if (try prog = regexp9::regcomp("([0-9]+)-([0-9]+)-([0-9]+)"))
	{
		bench1 = prog;
	}
	if (try prog = regexp9::regcomp("[0-9]+."))
	{
		bench2 = prog;
	}
	set_benchmark_warmup_iterations(5);
	set_benchmark_max_iterations(100_000);
}

fn void regexp9_bench1() @benchmark
{
	Resub[3] rs;
	regexp9::regexec(bench1, "650-253-0001", rs[..], 3);
}

fn void regexp9_bench2() @benchmark
{
	regexp9::regexec(bench1, "650-253-0001", null, 0);
}

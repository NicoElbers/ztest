const ztest = @import("ztest");
const exp = ztest.exp;
const exp_fn = ztest.exp_fn;
const expect = exp.expect;
const expectAll = exp.expectAll;
const parameterizedTest = ztest.parameterizedTest;

const util = @import("../tests.zig").util;

test "Different errors in a set" {
    const Err = error{ a, b, c };

    const a: Err = Err.a;
    const b: Err = Err.b;

    try expect(a).not().isEqualTo(b);
}

test "Same errors in a set" {
    const Err = error{ a, b, c };

    const a: Err = Err.a;
    const b: Err = Err.a;

    try expect(a).isEqualTo(b);
}

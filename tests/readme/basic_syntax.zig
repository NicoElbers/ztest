const ztest = @import("ztest");
const exp_fn = ztest.exp_fn;
const exp_meta_fn = ztest.exp_meta_fn;

const expect = ztest.expect;
const expectAll = ztest.expectAll;

test "basic expectation" {
    try expect(@as(u32, 123)).isEqualTo(123);
}

test "multiple expectations" {
    try expectAll(@as(u32, 123), &.{
        exp_fn.isEqualTo(@as(u32, 123)),
        exp_fn.isValue(u32),
        exp_meta_fn.not(u32, exp_fn.isEqualTo(@as(u32, 456))),
    });
}

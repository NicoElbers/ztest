const std = @import("std");
const testing = std.testing;

const ztest = @import("ztest");
const expect = ztest.exp.expect;

test {
    try expect(false).isEqualTo(false);
}

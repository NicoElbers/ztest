// TEST: Test the runner with some failing tests.
// TEST: Make sure to test that the output to stdout is correct.
// TEST: Make sure that I can print to stdout and stderr in my tests.

const ztest = @import("ztest");

fn fail() !void {
    return error.Err;
}

test "failure" {
    try ztest.parameterizedTest(fail, .{
        .{},
    });

    try fail();
}

pub fn skip() !void {
    return error.ZigSkipTest;
}

test "skip" {
    try ztest.parameterizedTest(skip, .{
        .{},
    });

    try skip();
}

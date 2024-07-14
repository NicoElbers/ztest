const ztest = @import("ztest");

test {
    // TODO: fix this so that I can run these tests with the normal runner,
    // just interact with a mock runner. Only exception being tests that rely
    // on the shared state
    if (!ztest.util.isUsingZtestRunner) return;

    _ = @import("failing.zig");
    _ = @import("passing.zig");
}

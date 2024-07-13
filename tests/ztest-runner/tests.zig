const ztest = @import("ztest");

test {
    if (!ztest.util.isUsingZtestRunner) return;

    _ = @import("runner_contact.zig");
    _ = @import("failing.zig");
    _ = @import("passing.zig");
}

const ztest = @import("ztest");

test {
    if (!ztest.util.isUsingZtestRunner) return;

    _ = @import("runner_contact.zig");
}

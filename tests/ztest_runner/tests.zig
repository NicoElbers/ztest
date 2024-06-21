const ztest = @import("ztest");

test {
    if (!ztest.utils.isUsingZtestRunner()) return;

    _ = @import("runner_contact.zig");
}

const readme = @import("readme/root.zig");

test {
    const testing = @import("std").testing;

    testing.refAllDeclsRecursive(readme);
}

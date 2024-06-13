pub const utils = @import("utils/utils.zig");

test {
    const testing = @import("std").testing;

    testing.refAllDeclsRecursive(readme);
}

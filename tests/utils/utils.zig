pub fn DummyGen(comptime T: type) type {
    return struct { val: T };
}

pub const DummyStruct = struct {
    val: u8 = 123,
};

pub const AllRuntimeTypes = struct {
    const val: u8 = 123;
    const Errors = error{SomeErr};
    const SomeEnum = enum { a, b };
    const SomeUnion = union { thing: SomeEnum, other_thing: Errors };
    const SomeVec = @Vector(5, u8);

    bool: bool = true,
    int: u32 = 123,
    float: f32 = 12.54,
    pointer: *const u8 = &val,
    array: [4]u8 = [4]u8{ 1, 2, 3, 4 },
    optional_null: ?u8 = null,
    optional_val: ?u8 = 123,
    error_set: Errors = Errors.SomeErr,
    errorunion_err: Errors!u8 = Errors.SomeErr,
    errorunion_val: Errors!u8 = 123,
    enum_literal: SomeEnum = .a,
};

pub const AllComptimeTypes = struct {
    const Errors = error{SomeErr};
    const SomeEnum = enum { a, b };
    const SomeUnion = union { thing: SomeEnum, other_thing: Errors };
    const SomeVec = @Vector(5, u8);

    enum_thing: type = SomeEnum,
    union_thing: type = SomeUnion,
    func: fn (u32) void = nukeStack,
    vector: type = SomeVec,
    struct_thing: type = DummyStruct,
    comptime_float: comptime_float = 12.43,
    comptime_int: comptime_int = 123,
    type: DummyGen(u8) = DummyGen(u8){ .val = 123 },
    void: type = void,
};

pub fn nukeStack(depth: u32) void {
    if (depth == 0) return;

    @call(.never_tail, nukeStack, .{depth - 1});
}

pub fn nukeComptimeStack(depth: comptime_int) void {
    comptime {
        if (depth == 0) return;

        @call(.auto, nukeComptimeStack, .{depth - 1});
    }
}

header: Header,
bytes: []const u8,

pub const ipc_start: [15]u8 = [_]u8{ 215, 217 } ++ "ZTESTIPCMSG".* ++ [_]u8{ 220, 235 };

pub const Header = packed struct(u64) {
    // TODO: Think of putting a crc in here to verify that we didn't just
    // randomly find a IPC messsage key
    tag: Tag,
    bytes_len: u32,
};

pub const Tag = enum(u32) {
    /// Has no body, can only be sent by server
    exit,

    /// Body consists of 1 usize, representing index in builtin.test_functions
    /// Can only be sent by the server
    runTest,

    /// Body consists of 1 usize, indicating the index of the test being run.
    /// Can only be sent by the client.
    testStart,

    /// Body consists of 1 usize, indicating the index of the test that succeeded.
    /// Can only be sent by the client.
    testSuccess,

    /// Body consists of 1 usize, indicating the index of the test that was skipped.
    /// Can only be sent by the client.
    testSkipped,

    /// Body consists TestFailure struct which explains the rest of the body,
    /// Can only be sent by the client.
    testFailure,

    /// Body is stringified arguments, can only be sent by client
    parameterizedStart,

    /// Body starts with ParameterizedError which explains the rest of the body,
    /// can only be sent by client
    parameterizedError,

    /// Has no body, can only be sent by client
    parameterizedSkipped,

    /// Has no body, can only be sent by client
    parameterizedComplete,
};

pub const TestFailure = packed struct(u64) {
    /// The test index that failed, first item
    test_idx: u32,

    /// The error name length, after test_idx
    error_name_len: u32,
};

pub const ParameterizedError = packed struct(u16) {
    /// error name length, first item
    error_name_len: u16,
};

const Message = @This();

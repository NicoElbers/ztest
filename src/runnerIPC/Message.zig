header: Header,
bytes: []const u8,

pub const Header = packed struct(u64) {
    // TODO: Think of putting a crc in here to verify that we didn't just
    // randomly find a IPC messsage key
    tag: Tag,
    bytes_len: u32,
};

pub const Tag = enum(u32) {
    rawString, // TODO : remove, because not useful

    /// Has no body, can only be sent by server
    exit,

    /// Body consists of 2 usizes, the first the start index in builtin.test_functions
    /// and the second the end index (exclusive). Can only be sent by the server
    runTests,

    /// Body consists of 1 usize, indicating the index of the test being run.
    /// Can only be sent by the client.
    testStart,

    /// Body consists of 1 usize, indicating the index of the test that succeeded.
    /// Can only be sent by the client.
    testSuccess,

    /// Body consists of 1 usize, indicating the index of the test that succeeded.
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
    parameterizedSuccess,
};

pub const ParameterizedError = packed struct(u32) {
    /// error name length, after start
    error_name_len: u16,

    /// stack trace len, after error name
    stack_trace_fmt_len: u16,
};

const Message = @This();

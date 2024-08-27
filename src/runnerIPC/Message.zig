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
    exit,
    parameterizedError,
    parameterizedSkipped,
};

pub const ParameterizedError = packed struct(u64) {
    // arg fmt
    arg_fmt_len: u16,
    // error name
    error_name_len: u16,
    // stack trace?
    stack_trace_fmt_len: u16,
    // If we have source information, relay it
    optional_src_info_len: u16,
};

pub const parameterizedSkipped = packed struct(u64) {
    // arg fmt
    arg_fmt_len: u32,
    _reserved: u32,
};

const Message = @This();

pub fn Node(comptime node_type: NodeType) type {
    const Poller = IPC.Poller(node_type);

    return struct {
        process_streamer: Poller,
        out: File,

        pub const MessageStatus = union(enum) {
            streamClosed: void,
            timedOut: void,
            message: Message,
        };

        pub const ReceiveError = error{
            Unexpected,
            OutOfMemory,
            InputOutput,
            AccessDenied,
            BrokenPipe,
            SystemResources,
            OperationAborted,
            WouldBlock,
            ConnectionResetByPeer,
            IsDir,
            ConnectionTimedOut,
            NotOpenForReading,
            SocketNotConnected,
            Canceled,
            Unsupported,
            StreamClosed,
            IncompleteMessage,
            NetworkSubsystemFailed,
        };

        pub const init = switch (node_type) {
            .server => initServer,
            .client => initClient,
        };

        /// Child must have stdout and stderr behavior of Pipe, this ensures that the
        /// stdout and stderr are valid once the child is spawned. The child must also
        /// already be spawned
        fn initServer(alloc: Allocator, child: Child) @This() {
            comptime assert(node_type == .server);

            assert(child.stdin != null);
            assert(child.stdout != null);
            assert(child.stderr != null);

            return .{
                .process_streamer = .init(
                    alloc,
                    child.stdout.?,
                    child.stderr.?,
                ),
                .out = child.stdin.?,
            };
        }

        fn initClient(alloc: Allocator) @This() {
            comptime assert(node_type == .client);

            return .{
                .process_streamer = .init(alloc, std.io.getStdIn()),
                .out = std.io.getStdOut(),
            };
        }

        pub const initManual = switch (node_type) {
            .server => initServerManual,
            .client => initClientManual,
        };

        fn initServerManual(alloc: Allocator, send: File, recv: File, err: File) @This() {
            comptime assert(node_type == .server);

            return .{
                .process_streamer = .init(alloc, recv, err),
                .out = send,
            };
        }

        fn initClientManual(alloc: Allocator, send: File, recv: File) @This() {
            comptime assert(node_type == .client);

            return .{
                .process_streamer = .init(alloc, recv),
                .out = send,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.process_streamer.deinit();
            self.* = undefined;
        }

        pub fn serveMessage(
            self: *@This(),
            header: Message.Header,
            bufs: []const []const u8,
        ) File.WriteError!void {
            assert(bufs.len < 9);
            var iovecs: [10]std.posix.iovec_const = undefined;
            const header_le = bswap(header);

            iovecs[0] = .{
                .base = &Message.ipc_start,
                .len = Message.ipc_start.len,
            };
            iovecs[1] = .{
                .base = @as([*]const u8, @ptrCast(&header_le)),
                .len = @sizeOf(Message.Header),
            };

            for (bufs, iovecs[2 .. bufs.len + 2]) |buf, *iovec| {
                iovec.* = .{
                    .base = buf.ptr,
                    .len = buf.len,
                };
            }

            try self.out.writevAll(iovecs[0 .. bufs.len + 2]);
        }

        pub fn serveExit(self: *@This()) !void {
            comptime assert(node_type == .server);

            const header: Message.Header = .{
                .tag = .exit,
                .bytes_len = 0,
            };

            try self.serveMessage(header, &.{});
        }

        pub fn serveRunTest(self: *@This(), idx: usize) !void {
            comptime assert(node_type == .server);

            const header: Message.Header = .{
                .tag = .runTest,
                .bytes_len = @sizeOf(usize),
            };

            try self.serveMessage(header, &.{
                std.mem.asBytes(&idx),
            });
        }

        pub fn serveStringMessage(
            self: *@This(),
            tag: Message.Tag,
            string: []const u8,
        ) !void {
            const header: Message.Header = .{
                .tag = tag,
                .bytes_len = @intCast(string.len),
            };
            try self.serveMessage(header, &.{
                string,
            });
        }

        pub fn serveTestStart(self: *@This(), idx: usize) !void {
            comptime assert(node_type == .client);

            const header = Message.Header{
                .tag = .testStart,
                .bytes_len = @sizeOf(usize),
            };

            try self.serveMessage(header, &.{
                std.mem.asBytes(&idx),
            });
        }

        pub fn serveTestSuccess(self: *@This(), idx: usize) !void {
            comptime assert(node_type == .client);

            const header = Message.Header{
                .tag = .testSuccess,
                .bytes_len = @sizeOf(usize),
            };

            try self.serveMessage(header, &.{
                std.mem.asBytes(&idx),
            });
        }

        pub fn serveTestFailure(self: *@This(), idx: usize) !void {
            comptime assert(node_type == .client);

            const header = Message.Header{
                .tag = .testFailure,
                .bytes_len = @sizeOf(usize),
            };

            try self.serveMessage(header, &.{
                std.mem.asBytes(&idx),
            });
        }

        pub fn serveTestSkipped(self: *@This(), idx: usize) !void {
            comptime assert(node_type == .client);

            const header = Message.Header{
                .tag = .testSkipped,
                .bytes_len = @sizeOf(usize),
            };

            try self.serveMessage(header, &.{
                std.mem.asBytes(&idx),
            });
        }

        pub fn serveParameterizedStart(self: *@This(), args_str: []const u8) !void {
            comptime assert(node_type == .client);

            const header = Message.Header{
                .tag = .parameterizedStart,
                .bytes_len = @intCast(args_str.len),
            };

            try self.serveMessage(header, &.{
                args_str,
            });
        }

        pub fn serveParameterizedComplete(self: *@This()) !void {
            comptime assert(node_type == .client);

            const header = Message.Header{
                .tag = .parameterizedComplete,
                .bytes_len = 0,
            };

            try self.serveMessage(header, &.{});
        }

        pub fn serveParameterizedSkipped(self: *@This()) !void {
            comptime assert(node_type == .client);

            const header = Message.Header{
                .tag = .parameterizedSkipped,
                .bytes_len = 0,
            };

            try self.serveMessage(header, &.{});
        }

        pub fn serveParameterizedError(self: *@This(), error_name: []const u8) !void {
            comptime assert(node_type == .client);

            const len: usize = @sizeOf(Message.ParameterizedError) + error_name.len;

            const header = Message.Header{
                .tag = .parameterizedError,
                .bytes_len = @intCast(len),
            };

            const message_info = Message.ParameterizedError{
                .error_name_len = @intCast(error_name.len),
            };

            try self.serveMessage(header, &.{
                &std.mem.toBytes(message_info),
                error_name,
            });
        }

        pub fn receiveMessage(self: *@This(), alloc: Allocator) ReceiveError!MessageStatus {
            const Header = Message.Header;

            const array_list: *ArrayList(u8) = switch (node_type) {
                .server => &self.process_streamer.stdout_content,
                .client => &self.process_streamer.stdin_content,
            };

            const ipc_msg_start: usize = blk: while (true) {
                if (std.mem.indexOf(u8, array_list.items, &Message.ipc_start)) |pos| {
                    break :blk pos;
                } else switch (try self.process_streamer.read()) {
                    .readLen => continue,
                    .timedOut => return .timedOut,
                    .streamClosed => return .streamClosed,
                }
            };
            const pos = ipc_msg_start + Message.ipc_start.len;

            var is_last_round = false;
            const header: Header = blk: while (true) {
                switch (try self.process_streamer.read()) {
                    .streamClosed => {
                        if (is_last_round) return .streamClosed;
                        is_last_round = true;
                    },
                    else => {},
                }

                const message_slice = array_list.items[pos..];

                if (message_slice.len < @sizeOf(Header)) continue;

                assert(@sizeOf(Header) == 8);

                const tag_int = std.mem.readInt(u32, message_slice[0..4], .little);
                const byte_len = std.mem.readInt(u32, message_slice[4..8], .little);

                break :blk Header{
                    .tag = @enumFromInt(tag_int),
                    .bytes_len = byte_len,
                };
            };

            is_last_round = false;

            const bytes_pos = pos + @sizeOf(Header);
            while (true) {
                switch (try self.process_streamer.read()) {
                    .streamClosed => {
                        if (is_last_round) return .streamClosed;
                        is_last_round = true;
                    },
                    else => {},
                }

                const after_slice = array_list.items[bytes_pos..];

                if (after_slice.len < header.bytes_len) continue;

                const bytes = try alloc.alloc(u8, header.bytes_len);
                @memcpy(bytes, after_slice[0..header.bytes_len]);

                std.mem.copyForwards(
                    u8,
                    array_list.items[ipc_msg_start..],
                    after_slice[header.bytes_len..],
                );

                array_list.shrinkRetainingCapacity(ipc_msg_start + after_slice.len - header.bytes_len);

                return .{ .message = Message{ .header = header, .bytes = bytes } };
            }

            return error.IncompleteMessage;
        }
    };
}

pub fn bswap(x: anytype) @TypeOf(x) {
    if (@import("builtin").target.cpu.arch.endian() == .little) return x;

    const T = @TypeOf(x);
    switch (@typeInfo(T)) {
        .@"enum" => return @as(T, @enumFromInt(@byteSwap(@intFromEnum(x)))),
        .int => return @byteSwap(x),
        .@"struct" => |info| switch (info.layout) {
            .@"extern" => {
                var result: T = undefined;
                inline for (info.fields) |field| {
                    @field(result, field.name) = bswap(@field(x, field.name));
                }
                return result;
            },
            .@"packed" => {
                const I = info.backing_integer.?;
                return @as(T, @bitCast(@byteSwap(@as(I, @bitCast(x)))));
            },
            .auto => @compileError("auto layout struct"),
        },
        else => @compileError("bswap on type " ++ @typeName(T)),
    }
}

const assert = std.debug.assert;

const File = std.fs.File;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Child = std.process.Child;
const Message = IPC.Message;
const NodeType = IPC.NodeType;

const std = @import("std");
const IPC = @import("root.zig");

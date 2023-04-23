const std = @import("std");
const c = @import("nvim_c");

test {
    std.testing.refAllDeclsRecursive(@This());
}

/// Convenient wrapper for nvim's Error
pub const Error = struct {
    err: c.Error = .{ .type = c.kErrorTypeNone, .msg = null },

    pub fn handle(self: Error) !void {
        switch (self.err.type) {
            c.kErrorTypeNone => {},
            c.kErrorTypeValidation => return error.NvimValidation,
            c.kErrorTypeException => return error.NvimException,
            else => unreachable,
        }
    }

    pub fn handleLog(self: Error) !void {
        self.handle() catch |e| {
            if (self.msg()) |m|
                std.log.scoped(.nvim).err("{s}", .{m});
            return e;
        };
    }

    pub fn msg(self: Error) ?[*:0]u8 {
        return self.err.msg;
    }
};

pub fn nvimString(data: []u8) c.String {
    return .{
        .data = data.ptr,
        .size = data.len,
    };
}

pub fn constNvimString(data: []const u8) c.String {
    return nvimString(@constCast(data));
}

pub fn zigString(data: c.String) []u8 {
    return data.data[0..data.size];
}

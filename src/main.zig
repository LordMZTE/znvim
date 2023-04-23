const std = @import("std");
const c = @import("nvim_c");

/// Convenient wrapper for nvim's Error
pub const Error = struct {
    err: c.Error = .{ .type = c.kErrorTypeNone, .msg = null },

    pub fn handle(self: Error) !void {
        switch (self.err.type) {
            c.kErrorTypeNone => {},
            c.kErrorTypeValidation => return error.NvimValidation,
            c.kErrorTypeException => return error.NvimException,
        }
    }

    pub fn handleLog(self: Error) !void {
        self.handle() catch |e| {
            if (self.msg()) |m|
                std.log.scoped(.nvim).err("{s}", .{m});
            return e;
        };
    }

    pub fn msg(self: Error) ?[:0]u8 {
        return self.err.msg;
    }
};

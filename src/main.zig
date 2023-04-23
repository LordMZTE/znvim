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

pub fn nvimObject(val: anytype) c.Object {
    const T = @TypeOf(val);

    return switch (T) {
        bool => .{
            .type = c.kObjectTypeBoolean,
            .data = .{ .boolean = val },
        },

        c_int => .{
            .type = c.kObjectTypeInteger,
            .data = .{ .integer = val },
        },

        f32, f64 => .{
            .type = c.kObjectTypeFloat,
            .data = .{ .floating = val },
        },

        []const u8, []u8 => .{
            .type = c.kObjectTypeString,
            .data = .{ .string = constNvimString(val) },
        },

        c.Array => .{
            .type = c.kObjectTypeArray,
            .data = .{ .array = val },
        },

        c.Dictionary => .{
            .type = c.kObjectTypeDictionary,
            .data = .{ .dictionary = val },
        },

        else => @compileError("Unsupported Type " ++ @typeName(T)),
    };
}

/// Wrapper for nvim.Dictionary
pub const Dictionary = struct {
    alloc: std.mem.Allocator,
    dict: c.Dictionary = .{ .size = 0, .capacity = 0, .items = null },

    pub fn reserve(self: *Dictionary, cap: usize) !void {
        if (self.dict.capacity == 0) {
            self.dict.items = (try self.alloc.alloc(c.KeyValuePair, cap)).ptr;
            self.dict.capacity = cap;
            return;
        }

        if (self.dict.capacity < cap) {
            self.dict.items = (try self.alloc.realloc(
                self.dict.items[0..self.dict.capacity],
                cap,
            )).ptr;
            self.dict.capacity = cap;
        }
    }

    pub fn deinit(self: *Dictionary) void {
        if (self.dict.capacity != 0) {
            self.alloc.free(self.dict.items[0..self.dict.capacity]);
        }
    }

    /// Does not copy the key or value!
    pub fn push(self: *Dictionary, key: []u8, item: c.Object) !void {
        try self.reserve(self.dict.size + 1);
        self.dict.items[self.dict.size] = .{ .key = nvimString(key), .value = item };
        self.dict.size += 1;
    }
};

test "Dictionary" {
    var dict = Dictionary{ .alloc = std.testing.allocator };
    defer dict.deinit();

    try dict.push(@constCast("string"), nvimObject(@as([]const u8, "Hello, World!")));
    try dict.push(@constCast("number"), nvimObject(@as(c_int, 42)));
    try dict.push(@constCast("bool"), nvimObject(true));
}

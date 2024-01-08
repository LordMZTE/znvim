const std = @import("std");
const c = @import("nvim_c");

const log = std.log.scoped(.znvim);

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

/// Wrapper around nvim's typval_T
pub const TypVal = union(enum) {
    number: c.varnumber_T,
    bool: bool,
    special: c_uint,
    float: f64,
    string: [*:0]u8,

    // TODO: implement some more advanced types

    /// Convert to the neovim type
    pub fn toNvim(self: TypVal) c.typval_T {
        return switch (self) {
            .number => |v| .{
                .v_type = c.VAR_NUMBER,
                .v_lock = c.VAR_UNLOCKED,
                .vval = .{ .v_number = v },
            },
            .bool => |v| .{
                .v_type = c.VAR_BOOL,
                .v_lock = c.VAR_UNLOCKED,
                .vval = .{ .v_bool = @intFromBool(v) },
            },
            .special => |v| .{
                .v_type = c.VAR_SPECIAL,
                .v_lock = c.VAR_UNLOCKED,
                .vval = .{ .v_special = v },
            },
            .float => |v| .{
                .v_type = c.VAR_FLOAT,
                .v_lock = c.VAR_UNLOCKED,
                .vval = .{ .v_float = v },
            },
            .string => |v| .{
                .v_type = c.VAR_STRING,
                .v_lock = c.VAR_UNLOCKED,
                .vval = .{ .v_string = v },
            },
        };
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

/// Thin wrapper around TriState booleans
pub const TriState = enum(c_int) {
    none = c.kNone,
    false = c.kFalse,
    true = c.kTrue,

    pub inline fn ofBool(b: bool) TriState {
        return if (b) .true else .false;
    }

    pub inline fn fromNvim(n: c.TriState) TriState {
        return @enumFromInt(n);
    }

    pub inline fn toNvim(self: TriState) c.TriState {
        return @intFromEnum(self);
    }
};

/// API for nvim options
pub const OptionValue = union(enum) {
    nil,
    tristate: TriState,
    number: i64,
    string: []const u8,

    /// Scope of an option
    pub const Scope = enum(c_int) {
        local = c.OPT_LOCAL,
        global = c.OPT_GLOBAL,
        both = 0,

        pub inline fn toNvim(self: Scope) c_int {
            return @intFromEnum(self);
        }
    };

    pub fn of(x: anytype) OptionValue {
        if (@TypeOf(x) == TriState) {
            return .{ .tristate = x };
        } else {
            return switch (@typeInfo(@TypeOf(x))) {
                .Null => .nil,
                .Bool => .{ .tristate = TriState.ofBool(x) },
                .Int, .ComptimeInt => .{ .number = x },
                .Pointer => .{ .string = @constCast(x) },
                else => @compileError("Unsupported OptionValue type: " ++ @typeName(@TypeOf(x))),
            };
        }
    }

    pub fn fromNvim(v: c.OptVal) OptionValue {
        return switch (v.type) {
            c.kOptValTypeNil => .nil,
            c.kOptValTypeBoolean => .{ .tristate = TriState.fromNvim(v.data.boolean) },
            c.kOptValTypeNumber => .{ .number = v.data.number },
            c.kOptValTypeString => .{ .string = v.data.string.data[0..v.data.string.size] },
            else => unreachable,
        };
    }

    pub fn toNvim(self: OptionValue) c.OptVal {
        return switch (self) {
            .nil => std.mem.zeroInit(c.OptVal, .{ .type = c.kOptValTypeNil }),
            .tristate => |b| .{
                .type = c.kOptValTypeBoolean,
                .data = .{ .boolean = b.toNvim() },
            },
            .number => |n| .{
                .type = c.kOptValTypeNumber,
                .data = .{ .number = n },
            },
            .string => |s| .{
                .type = c.kOptValTypeString,
                .data = .{ .string = nvimString(@constCast(s)) },
            },
        };
    }

    /// Gets the option for a given scope and key.
    pub inline fn get(key: [*:0]const u8, scope: Scope) OptionValue {
        const idx = c.find_option(key);
        if (idx == c.kOptInvalid) return .nil;
        return OptionValue.fromNvim(c.get_option_value(idx, scope.toNvim()));
    }

    /// Sets the option to this value for a given key and scope.
    /// Returns null on success and an error message on error.
    pub inline fn set(self: OptionValue, key: [*:0]const u8, scope: Scope) ?[*:0]const u8 {
        const idx = c.find_option(key);
        if (idx == c.kOptInvalid)
            return "No such option!";

        return c.set_option_value(idx, self.toNvim(), scope.toNvim());
    }

    /// Sets the option to this value for a given key and scope.
    /// In case of an error, log that error and return error.SetOption
    pub fn setLog(self: OptionValue, key: [*:0]const u8, scope: Scope) !void {
        if (self.set(key, scope)) |e| {
            log.err("setting option: {s}", .{e});
            return error.SetOption;
        }
    }
};

test "Dictionary" {
    var dict = Dictionary{ .alloc = std.testing.allocator };
    defer dict.deinit();

    try dict.push(@constCast("string"), nvimObject(@as([]const u8, "Hello, World!")));
    try dict.push(@constCast("number"), nvimObject(@as(c_int, 42)));
    try dict.push(@constCast("bool"), nvimObject(true));
}

test "OptionValue.of" {
    try std.testing.expectEqual(OptionValue.nil, OptionValue.of(null));
    try std.testing.expectEqual(OptionValue{ .tristate = .true }, OptionValue.of(true));
    try std.testing.expectEqual(OptionValue{ .tristate = .none }, OptionValue.of(TriState.none));
    try std.testing.expectEqual(OptionValue{ .number = 42 }, OptionValue.of(42));
    try std.testing.expectEqual(OptionValue{ .string = "Hello" }, OptionValue.of("Hello"));
}

//! Main entry-point for the CLIG Library which provides :
//!   - Config Loading
//!   - Compile-Time evaluation
//!   - CLI Argument Loading
//!
//! In the Config type, if including a struct, it will be parsed
//! under the CLI argument `--<struct-name>.<field-name> <field-value>`

const std = @import("std");
const testing = std.testing;

/// The Init Options for displaying the
/// `--help` message
pub const HelpOptions = struct {
    /// The title of the CLI application, should be
    /// short such as 'CLIG App' or 'Packet Analyzer'
    title: []const u8,
    /// The full on description of the application, should
    /// include '\n' for new-lines. Should be longer than the title,
    /// and explaining the general usage of the CLI app.
    preambule: []const u8,
    /// The Helper type (see README.md) that should satisfy :
    ///   - All fields in the Config type should be in the helper
    ///   - All fields should be of type []const u8 or struct
    ///   - All fields should be default-initialized with the description
    ///
    /// CLIG will then traverse the Config type, generating the help message
    /// at compile-time using the information pulled from the helper type.
    description: type,
};

/// The Init Options for loading a config file for the
/// CLIG library.
pub const InitOptions = struct {
    /// The filepath (starting from the CWD) of the
    /// config file that should be written to and read from
    filepath: []const u8 = "./config.json",

    /// The `--help` CLI message options
    help: HelpOptions,
};

fn loadFromFile(Config: type, allocator: std.mem.Allocator, options: InitOptions) !?Config {
    const data: std.fs.File = std.fs.cwd().openFile(options.filepath, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer data.close();

    var reader = std.json.reader(allocator, data.reader());
    defer reader.deinit();

    const parsed = try std.json.parseFromTokenSource(Config, allocator, &reader, .{
        .duplicate_field_behavior = .use_last,
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });

    return parsed.value;
}

fn saveToFile(config: anytype, options: InitOptions) !void {
    const data = try std.fs.cwd().createFile(options.filepath, .{});
    defer data.close();

    try std.json.stringify(config, .{
        .whitespace = .indent_tab,
    }, data.writer());
}

const ArgsError = error{
    UnkownArgument,
    InvalidArgument,
    InvalidValueForArgument,
    MissingArgumentValue,
    HelpMessageShown,
};

fn innerParseArgument(Field: type, comptime fieldName: []const u8, arg0: []const u8, arg1: ?[]const u8, Config: type, value: *Config, allocator: std.mem.Allocator) !void {
    switch (@typeInfo(Field)) {
        .Bool => {
            if (arg1) |flag| {
                const isTrue = std.mem.eql(u8, flag, "true");

                if (!isTrue and !std.mem.eql(u8, flag, "false")) {
                    return error.InvalidValueForArgument;
                }

                @field(value.*, fieldName) = isTrue;
            } else {
                @field(value.*, fieldName) = true;
            }
            return;
        },
        .Int => {
            if (arg1 == null)
                return error.MissingArgumentValue;

            @field(value.*, fieldName) = try std.fmt.parseInt(Field, arg1.?, 0);
            return;
        },
        .Float => {
            if (arg1 == null)
                return error.MissingArgumentValue;

            @field(value.*, fieldName) = try std.fmt.parseFloat(Field, arg1.?);
            return;
        },
        .Pointer => |arr| {
            if (arg1 == null)
                return error.MissingArgumentValue;

            if (@typeInfo(arr.child).Int.bits != 8) {
                @compileError("Unsupported array type !");
            }

            @field(value.*, fieldName) = try allocator.dupe(u8, arg1.?);
            return;
        },
        .Struct => |str| {
            const hasNextMember = std.mem.indexOf(u8, arg0, ".");

            if (hasNextMember == null)
                return error.InvalidArgument;

            const nextMemberName = arg0[hasNextMember.? + 1 ..];

            inline for (str.fields) |field| {
                if (std.mem.eql(u8, field.name, nextMemberName)) {
                    try innerParseArgument(
                        field.type,
                        field.name,
                        nextMemberName,
                        arg1,
                        Field,
                        &@field(value.*, fieldName),
                        allocator,
                    );
                    return;
                }
            }

            return error.UnkownArgument;
        },
        .Enum => {
            if (arg1 == null)
                return error.MissingArgumentValue;

            const temp = std.meta.stringToEnum(Field, arg1.?);
            if (temp == null)
                return error.InvalidValueForArgument;

            @field(value.*, fieldName) = temp.?;
            return;
        },
        else => @compileError("Unsupported type in config type " ++ @typeName(Field)),
    }
}

fn parseArgument(T: type, value: *T, arg0: []const u8, arg1: ?[]const u8, allocator: std.mem.Allocator) !void {
    const fields: []const std.builtin.Type.StructField = std.meta.fields(T);

    inline for (fields) |field| {
        if (std.mem.startsWith(u8, arg0, field.name)) {
            try innerParseArgument(field.type, field.name, arg0, arg1, T, value, allocator);
            return;
        }
    }

    return error.UnkownArgument;
}

fn loadFromArgs(value: anytype, allocator: std.mem.Allocator, options: InitOptions) !@TypeOf(value) {
    var skipNext = true;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    const Config = @TypeOf(value);
    var temp = value;

    for (args, 0..) |arg, i| {
        if (skipNext) {
            skipNext = false;
            continue;
        }

        if (!std.mem.startsWith(u8, arg, "--") or arg.len <= 2) {
            return ArgsError.InvalidArgument;
        }

        const hasEqual = std.mem.indexOf(u8, arg, "=");
        if (hasEqual) |index| {
            const argName = arg[2..index];
            if (std.mem.eql(u8, argName, "help")) {
                showHelpMessage(Config, allocator, options);
                return error.HelpMessageShown;
            }

            const other: ?[]u8 = blk: {
                const rest = arg[index + 1 ..];

                if (rest.len == 0) {
                    break :blk null;
                }

                break :blk rest;
            };

            try parseArgument(Config, &temp, argName, other, allocator);
        } else {
            const argName = arg[2..];
            if (std.mem.eql(u8, argName, "help")) {
                showHelpMessage(Config, allocator, options);
                return error.HelpMessageShown;
            }

            const other: ?[]u8 = blk: {
                if (args.len > i + 1) {
                    if (std.mem.startsWith(u8, args[i + 1], "--")) {
                        break :blk null;
                    }

                    skipNext = true;
                    break :blk args[i + 1];
                }

                break :blk null;
            };

            try parseArgument(Config, &temp, argName, other, allocator);
        }
    }

    return temp;
}

fn innerPrintHelp(comptime prefix: [:0]const u8, Config: std.builtin.Type.StructField, Helper: std.builtin.Type.StructField, comptime indent: u8) [:0]const u8 {
    const indstr = "  " ** indent;
    comptime var result: [:0]const u8 = "";
    comptime switch (@typeInfo(Config.type)) {
        .Pointer => {
            const description: *align(Helper.alignment) const []const u8 = @ptrCast(@alignCast(Helper.default_value));
            const defValue: *align(Config.alignment) const Config.type = @ptrCast(@alignCast(Config.default_value));

            result = result ++ std.fmt.comptimePrint("{s}--{s}{s} <string>\n", .{ indstr, prefix, Config.name });
            result = result ++ std.fmt.comptimePrint("{s}Default: {s} - {s}\n", .{ indstr, defValue.*, description.* });
        },
        .Enum => {
            const description: *align(Helper.alignment) const []const u8 = @ptrCast(@alignCast(Helper.default_value));
            const defValue: *align(Config.alignment) const Config.type = @ptrCast(@alignCast(Config.default_value));
            const tag = std.enums.tagName(Config.type, defValue.*);

            var tags: [:0]const u8 = "";

            for (std.enums.values(Config.type)) |value| {
                tags = tags ++ "," ++ std.enums.tagName(Config.type, value).?;
            }

            result = result ++ std.fmt.comptimePrint("{s}--{s}{s} <{s}>\n", .{ indstr, prefix, Config.name, tags[1..] });
            result = result ++ std.fmt.comptimePrint("{s}Default: {s} - {s}\n", .{ indstr, tag.?, description.* });
        },
        .Struct => |str| {
            result = result ++ std.fmt.comptimePrint("\n{s}Section {s}\n", .{ indstr, Config.name });
            const nprefix = prefix ++ std.fmt.comptimePrint("{s}.", .{Config.name});
            for (str.fields) |field| {
                for (@typeInfo(Helper.type).Struct.fields) |helper| {
                    if (std.mem.eql(u8, helper.name, field.name)) {
                        result = result ++ innerPrintHelp(nprefix, field, helper, indent + 1);
                        break;
                    }
                }
            }
        },
        else => {
            const description: *align(Helper.alignment) const []const u8 = @ptrCast(@alignCast(Helper.default_value));
            const defValue: *align(Config.alignment) const Config.type = @ptrCast(@alignCast(Config.default_value));

            result = result ++ std.fmt.comptimePrint("{s}--{s}{s} <{s}>\n", .{ indstr, prefix, Config.name, @typeName(Config.type) });
            result = result ++ std.fmt.comptimePrint("{s}Default: {} - {s}\n", .{ indstr, defValue.*, description.* });
        },
    };

    return result;
}

fn showHelpMessage(Config: type, allocator: std.mem.Allocator, options: InitOptions) void {
    _ = allocator;

    const arg0 = std.mem.span(std.os.argv[0]);
    std.debug.print("{s} - {s}\n", .{ std.fs.path.basename(arg0), options.help.title });
    std.debug.print("{s}\n\n", .{options.help.preambule});

    std.debug.print("Arguments :\n\n", .{});

    inline for (@typeInfo(Config).Struct.fields) |field| {
        comptime var found = false;
        inline for (@typeInfo(options.help.description).Struct.fields) |helper| {
            if (comptime std.mem.eql(u8, field.name, helper.name)) {
                std.debug.print("{s}", .{innerPrintHelp("", field, helper, 0)});
                found = true;
                break;
            }
        }

        if (!found) @compileError("Helper description not found for field " ++ field.name);
    }
}

var arena: std.heap.ArenaAllocator = undefined;

/// Initializes the CLIG parsing things, returning the wanted Config type both
/// read from disk and parsed from CLI arguments.
///
/// The CLI arguments take priority over the contents of the config file.
pub fn init(Config: type, allocator: std.mem.Allocator, options: InitOptions) !Config {
    arena = std.heap.ArenaAllocator.init(allocator);

    var config: Config = try loadFromFile(Config, arena.allocator(), options) orelse .{};
    try saveToFile(config, options);

    config = try loadFromArgs(config, arena.allocator(), options);

    return config;
}

/// Frees any memory, **INCLUDING THE CONFIG** from the allocator.
pub fn deinit() void {
    arena.deinit();
}

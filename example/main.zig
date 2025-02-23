const std = @import("std");
const clig = @import("clig");

const Config = struct {
    flag: u8 = 5,
    string: []const u8 = "default value",
    randoming: enum {
        true_random,
        prng,
        cprng,
    } = .true_random,
    advanced: struct {
        testify: bool = false,
        random: u8 = 76,
    } = .{},
};

const ConfigHelp = struct {
    flag: []const u8 = "Flag that does strictly nothing",
    string: []const u8 = "Might want to set a variable as a string as well",
    randoming: []const u8 = "Sets the useless type of randomness to use",
    advanced: struct {
        testify: []const u8 = "Type-ception is fun",
        random: []const u8 = "Sets the randomness as to how much do nothing",
    } = .{},
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    _ = clig.init(Config, allocator, .{ .help = .{
        .title = "Example",
        .preambule = "CLIG Example CLI application that can do nothing ;)",
        .description = ConfigHelp,
    } }) catch |err| switch (err) {
        error.HelpMessageShown => return,
        else => return err,
    };
}

# CLI + Config for zig !

Many of the current libraries in zig only support for CLI command arguments or config loading but not both at the same time.

This library aims to solve that problem ! It aims to be as minimal as possible, and as much in compile-time as possible.

## Installation
Run the following command in your favourite terminal, in a folder containing a `build.zig.zon` :
```sh
$ zig fetch --save git+https://github.com/Lygaen/clig
```

Add the dpendency to your `build.zig` :
```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // -- snip --

    const clig_dep = b.dependency("clig", .{
        .target = target,
        .optimize = optimize,
    });

    // Where `exe` represents your executable/library to link to
    exe.linkLibrary(clig_dep.artifact("clig"));

    // -- snip --
}
```

And voilà ! Everything is in order.

## Usage
You can see the `example/` folder for an example usage of this library. It aims to be as less disruptive as possible :

First import `clig` :
```zig
const clig = @import("clig");
```

Define your config, it should be **default constructible** (aka. all fields should have defaults) :
```zig
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
```

Define a `help` struct that contains the description of the fields of `Config`, having the same name. 
> Until we can add additional information to fields, this is the only solution to add compile-time information
> to a struct.
```zig
const ConfigHelp = struct {
    flag: []const u8 = "Flag that does strictly nothing",
    string: []const u8 = "Might want to set a variable as a string as well",
    randoming: []const u8 = "Sets the useless type of randomness to use",
    advanced: struct {
        testify: []const u8 = "Type-ception is fun",
        random: []const u8 = "Sets the randomness as to how much do nothing",
    } = .{},
};
```

Now you can call `clig.init(#ConfigType, #Allocator, #InitOptions)` freely !
```zig
pub fn main() !void {
    // -- snip --

    _ = clig.init(Config, allocator, .{
        .help = .{
            .title = "Example",
            .preambule = "CLIG Example CLI application that can do nothing ;)",
            .description = ConfigHelp,
        },
    }) catch |err| switch (err) {
        error.HelpMessageShown => return, // Handle the case where help was shown
        else => return err,
    };
    defer clig.deinit();
}
```

And that's it ! If you have already a `Config` type defined, all you need is to add a `Helper` companion of the said type to add the descriptions.
CLI arguments can be parsed using :
`--arg=<value>` or `--arg value` or if the type is a bool `--arg` (to set to true).

The above types will generate the following configs and help message :
```sh
$ zig build run -- --help
clig-example - Example
CLIG Example CLI application that can do nothing ;)

Arguments :

--flag <u8>
Default: 5 - Flag that does strictly nothing
--string <string>
Default: default value - Might want to set a variable as a string as well
--randoming <true_random,prng,cprng>
Default: true_random - Sets the useless type of randomness to use

Section advanced
  --advanced.testify <bool>
  Default: false - Type-ception is fun
  --advanced.random <u8>
  Default: 76 - Sets the randomness as to how much do nothing
```

```json
$ cat config.json
{
	"flag": 5,
	"string": "default value",
	"randoming": "true_random",
	"advanced": {
		"testify": false,
		"random": 76
	}
}
```


## TODOs
- [x] Config file loading
- [x] Argument loading
- [x] `=` in arguments loading
- [x] Comptime Help
- [x] More detailed documentation
- [ ] ENV arguments
- [ ] Better Errors
- [ ] Revamp the example
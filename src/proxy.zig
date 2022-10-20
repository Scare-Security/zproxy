const std = @import("std");
const copy = @import("./copy.zig");
const net = std.net;
const heap = std.heap;
const os = std.os;
const thread = std.Thread;
const process = std.process;
const fmt = std.fmt;
const print = std.debug.print;

// show to user how to use the program
pub fn usage(file: []const u8) void {
    print("usage: {s} [input [port]] [destination [ip/hostname] [port]]\n", .{file});
    print("\n\tex: {s} 8080 anotherWebsite.com 80\n", .{file});
}

// check args number
pub fn parseArgs(argv: [][:0]const u8) void {
    if (argv.len != 4) {
        usage(argv[0]);
        process.exit(1);
    }
}

// do not stop when getting SIGPIPE
pub fn handlePipe(sig: c_int, i: *const os.siginfo_t, d: ?*const anyopaque) callconv(.C) void {
    _ = i;
    _ = d;
    _ = sig;
    return;
}

pub fn main() void {
    // init allocator
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    // get argv
    const argv = process.argsAlloc(allocator) catch {
        print("[-] couldn't alloc main arguments..\n", .{});
        return;
    };
    defer process.argsFree(allocator, argv);

    // parse arguments
    if (argv.len != 4) {
        usage(argv[0]);
        return;
    }

    // setup input and output ip:port
    const in_ip = "0.0.0.0";
    const in_port = argv[1];
    const out_ip = argv[2];
    const out_port = argv[3];

    // setup listen_addr
    var port = fmt.parseUnsigned(u16, in_port, 10) catch {
        print("[-] not a number: {s}\n", .{in_port});
        return;
    };
    // net.tcpConnectToHost
    const in_addr = net.Address.parseIp(in_ip, port) catch {
        print("[-] address error: {s}:{}\n", .{ in_ip, port });
        return;
    };

    // setup output_addr
    port = fmt.parseUnsigned(u16, out_port, 10) catch {
        print("[-] not a number: {s}\n", .{in_port});
        return;
    };

    // listen on input_addr
    var input = net.StreamServer.init(.{ .reuse_address = true });
    defer input.deinit();
    input.listen(in_addr) catch {
        print("[-] listening\n", .{});
        return;
    };
    print("[+] Listening on {}\n", .{in_addr});

    // setup signal catcher
    const sigact = os.Sigaction{ .handler = .{ .sigaction = handlePipe }, .mask = undefined, .flags = undefined, .restorer = undefined };
    os.sigaction(os.SIG.PIPE, &sigact, null) catch {
        print("[-] Signal handling\n", .{});
        print("[-] Still running\n", .{});
    };

    // main loop catching clients
    while (true) {
        // get client
        const conn = input.accept() catch |e| {
            print("[-] accepting a client: {}\n", .{e});
            continue;
        };
        print("[+] accepting a client: {}\n", .{conn.address});
        const cli = conn.stream;

        // get target
        const target = net.tcpConnectToHost(allocator, out_ip, port) catch {
            print("[-] couldn't connecto to: {s}:{}\n", .{ out_ip, port });
            continue;
        };

        // thread to handle the client
        const t = thread.spawn(.{}, copy.copyIO, .{ cli, target }) catch {
            print("[-] thread for client: {}\n", .{conn.address});
            continue;
        };
        print("[+] thread for client: {}\n", .{conn.address});
        t.detach();
    }
}

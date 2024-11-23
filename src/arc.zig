const std = @import("std");
const pd = @import("pd");
const strlen = @cImport({ @cInclude("string.h"); }).strlen;

pub const Entry = struct {
	name: [:0]const u8,
	size: usize,
};

pub const Reader = struct {
	const Self = @This();

	pub const VTable = struct {
		next: *const fn (*anyopaque, []u8) anyerror!?Entry,
		close: *const fn (*anyopaque, *const std.mem.Allocator) void,
	};

	ptr: *anyopaque,
	vtable: *const VTable,
	allocator: *const std.mem.Allocator,
	count: usize = 0,
	size: usize = 0,

	pub fn next(self: *Self, buf: []u8) !?Entry {
		return self.vtable.next(self.ptr, buf);
	}

	pub fn close(self: *Self) void {
		self.vtable.close(self.ptr, self.allocator);
	}
};

const RarReader = struct {
	const rar = @import("unrar");
	const Self = @This();

	head: rar.Header = .{},
	archive: *rar.Archive = undefined,
	buf_ptr: [*]u8 = undefined,

	fn cb(_: rar.CallbackMsg, udata: usize, p1: usize, p2: usize) callconv(.C) c_int {
		const buf: *[*]u8 = @ptrFromInt(udata);
		const addr: [*]u8 = @ptrFromInt(p1);
		@memcpy(buf.*[0..p2], addr[0..p2]);
		buf.* += p2;
		return 0;
	}

	pub fn init(allocator: *const std.mem.Allocator, path: [:0]const u8) !Reader {
		const self = try allocator.create(Self);
		errdefer allocator.destroy(self);
		var base = Reader{ .ptr = self, .vtable = &Self.vtable, .allocator = allocator };

		var data = rar.OpenData{ .arc_name = path.ptr, .open_mode = .list };
		self.archive = blk: {
			const archive = try data.open();
			defer archive.close() catch {};
			// determine space needed for the unpacked size and file count.
			while (try self.head.read(archive)) {
				try archive.processFile(.skip, null, null);
				base.count += 1;
				base.size += self.head.unp_size;
			}
			// prepare for extraction
			data.open_mode = .extract;
			break :blk try data.open();
		};
		self.archive.setCallback(cb, @intFromPtr(&self.buf_ptr));
		return base;
	}

	fn next(self: *Self, buf: []u8) !?Entry {
		if (!try self.head.read(self.archive)) {
			return null;
		}
		// if prev entry was not a music emu file, buf_ptr returns to prev position
		self.buf_ptr = buf.ptr;
		try self.archive.processFile(.read, null, null);
		const name = self.head.file_name[0..strlen(&self.head.file_name) :0];
		return Entry{ .name = name, .size = self.head.unp_size };
	}

	fn close(self: *Self, allocator: *const std.mem.Allocator) void {
		self.archive.close() catch {};
		allocator.destroy(self);
	}

	pub const signature: u32 = @bitCast([4]u8{'R', 'a', 'r', '!'});
	pub const vtable = Reader.VTable {
		.next = @ptrCast(&next),
		.close = @ptrCast(&close),
	};
};

const ZipReader = struct {
	const gz_signature: u24 = @bitCast([3]u8{0x1f, 0x8b, 0x08});
	const Self = @This();

	file: std.fs.File = undefined,
	iterator: std.zip.Iterator(std.fs.File.SeekableStream) = undefined,
	file_name: [pd.max_string:0]u8 = std.mem.zeroes([pd.max_string:0]u8),

	pub fn init(allocator: *const std.mem.Allocator, path: [:0]const u8) !Reader {
		const self = try allocator.create(Self);
		errdefer allocator.destroy(self);
		var base = Reader{ .ptr = self, .vtable = &Self.vtable, .allocator = allocator };

		self.file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
		errdefer self.file.close();

		// determine space needed for the unpacked size and file count.
		const reader = self.file.reader();
		const stream = self.file.seekableStream();
		self.iterator = try std.zip.Iterator(@TypeOf(stream)).init(stream);
		while (try self.iterator.next()) |entry| {
			if (entry.uncompressed_size == 0) { // directory, ignore
				continue;
			}
			base.count += 1;

			try stream.seekTo(entry.file_offset);
			const header = try reader.readStructEndian(std.zip.LocalFileHeader, .little);
			try stream.seekBy(entry.filename_len + header.extra_len);

			base.size += switch (entry.compression_method) {
			.store => blk: { // might be a gzipped file
				if (@as(u24, @bitCast(try reader.readBytesNoEof(3))) == gz_signature) {
					try stream.seekBy(@as(i64, @intCast(entry.compressed_size)) - 3 - 4);
					break :blk try reader.readInt(u32, .little);
				}
				break :blk entry.compressed_size;
			},
			.deflate => blk: {
				var flate = std.compress.flate.decompressor(reader);
				const r = flate.reader();
				if (@as(u24, @bitCast(try r.readBytesNoEof(3))) == gz_signature) {
					// gzip puts uncompressed size in the footer, decompress the whole file
					const buf = try allocator.alloc(u8, entry.uncompressed_size - 3);
					defer allocator.free(buf);
					_ = try r.readAll(buf);
					const bp = buf[(buf.len - 4)..];
					const size: u32 = @bitCast([4]u8{bp[0], bp[1], bp[2], bp[3]});
					break :blk size;
				}
				break :blk entry.uncompressed_size;
			},
			_ => return error.UnsupportedCompressionMethod,
			};
		}

		// prepare for extraction
		self.iterator.cd_record_index = 0;
		self.iterator.cd_record_offset = 0;
		return base;
	}

	fn next(self: *Self, buf: []u8) !?Entry {
		const entry = try self.iterator.next() orelse return null;
		const reader = self.file.reader();
		const stream = self.file.seekableStream();

		// get local file header and file name
		try stream.seekTo(entry.file_offset);
		const header = try reader.readStructEndian(std.zip.LocalFileHeader, .little);
		const n = try reader.readAll(self.file_name[0..@min(entry.filename_len, 259)]);
		self.file_name[n] = 0;

		// read data into buffer
		try stream.seekBy(header.extra_len);
		const name = self.file_name[0..n :0];
		return Entry{ .name = name, .size = switch (entry.compression_method) {
		.store => blk: { // might be a gzipped file
			if (@as(u24, @bitCast(try reader.readBytesNoEof(3))) == gz_signature) {
				const entry_size: i64 = @intCast(entry.compressed_size);
				try stream.seekBy(entry_size - 3 - 4);
				const size = try reader.readInt(u32, .little);

				try stream.seekBy(-entry_size);
				var gzip = std.compress.gzip.decompressor(reader);
				_ = try gzip.reader().readAll(buf[0..size]);
				break :blk size;
			}
			_ = try reader.readAll(buf[0..entry.compressed_size]);
			break :blk entry.compressed_size;
		},
		.deflate => blk: {
			var flate = std.compress.flate.decompressor(reader);
			_ = try flate.reader().readAll(buf[0..entry.uncompressed_size]);
			if (@as(u24, @bitCast([3]u8{buf[0], buf[1], buf[2]})) == gz_signature) {
				const bp = buf[(entry.uncompressed_size - 4)..];
				const size: u32 = @bitCast([4]u8{bp[0], bp[1], bp[2], bp[3]});

				var buf_stream = std.io.fixedBufferStream(buf);
				var gzip = std.compress.gzip.decompressor(buf_stream.reader());
				_ = try gzip.reader().readAll(buf[0..size]);
				break :blk size;
			}
			break :blk entry.uncompressed_size;
		},
		_ => return error.UnsupportedCompressionMethod,
		}};
	}

	fn close(self: *Self, allocator: *const std.mem.Allocator) void {
		self.file.close();
		allocator.destroy(self);
	}

	pub const signature: u32 = @bitCast([4]u8{'P', 'K', 0x3, 0x4});
	pub const vtable = Reader.VTable {
		.next = @ptrCast(&next),
		.close = @ptrCast(&close),
	};
};

pub const types = [_]type { RarReader, ZipReader };

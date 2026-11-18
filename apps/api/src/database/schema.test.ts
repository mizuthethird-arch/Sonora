import { PrismaMariaDb } from "@prisma/adapter-mariadb";
import { afterAll, afterEach, describe, expect, it } from "vitest";
import { PrismaClient } from "../generated/prisma/client.js";

const databaseUrl = process.env["DATABASE_URL"];
if (!databaseUrl) {
  throw new Error("DATABASE_URL is not set, the global setup should have provided it");
}

const prisma = new PrismaClient({ adapter: new PrismaMariaDb(databaseUrl) });

const UNIQUE_VIOLATION = { code: "P2002" };
const FOREIGN_KEY_VIOLATION = { code: "P2003" };
const VALUE_TOO_LONG = { code: "P2000" };
const OUT_OF_RANGE = { code: "P2020" };
const MISSING_ID = "00000000-0000-7000-8000-000000000000";
const UUID_VERSION_7 = /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const HOSTILE_TEXT = "🎵 Rós '; DROP TABLE User; -- <script>alert(1)</script>";

function createUser(email = "listener@example.com") {
  return prisma.user.create({ data: { email, passwordHash: "test-hash", displayName: "Listener" } });
}

function createArtist(externalId = "artist-1", name = "Artist") {
  return prisma.artist.create({ data: { name, externalSource: "JAMENDO", externalId } });
}

function createTrack(artistId: string, externalId = "track-1", title = "Track") {
  return prisma.track.create({
    data: {
      title,
      artistId,
      durationSeconds: 180,
      externalSource: "JAMENDO",
      externalId,
      license: "CC-BY",
      downloadAllowed: true,
      allowsDerivatives: true,
    },
  });
}

function createPlaylist(userId: string) {
  return prisma.playlist.create({ data: { userId, name: "Favourites" } });
}

function addToPlaylist(playlistId: string, trackId: string, position = 1) {
  return prisma.playlistTrack.create({ data: { playlistId, trackId, position } });
}

afterEach(async () => {
  await prisma.playlistTrack.deleteMany();
  await prisma.playlist.deleteMany();
  await prisma.refreshToken.deleteMany();
  await prisma.track.deleteMany();
  await prisma.album.deleteMany();
  await prisma.artist.deleteMany();
  await prisma.user.deleteMany();
});

afterAll(async () => {
  await prisma.$disconnect();
});

describe("users", () => {
  it("stores a user with generated id and timestamps", async () => {
    const user = await createUser();

    expect(user.id).toMatch(UUID_VERSION_7);
    expect(user.createdAt).toBeInstanceOf(Date);
    expect(user.updatedAt).toBeInstanceOf(Date);
  });

  it("rejects a duplicate email", async () => {
    await createUser("a@example.com");

    await expect(createUser("a@example.com")).rejects.toMatchObject(UNIQUE_VIOLATION);
  });

  it("treats emails as case-insensitive", async () => {
    await createUser("Listener@Example.com");

    await expect(createUser("listener@example.com")).rejects.toMatchObject(UNIQUE_VIOLATION);
  });

  it("rejects an email longer than 254 characters", async () => {
    const tooLong = `${"a".repeat(250)}@x.co`;

    await expect(createUser(tooLong)).rejects.toMatchObject(VALUE_TOO_LONG);
  });

  it("accepts an email of exactly 254 characters", async () => {
    const longest = `${"a".repeat(249)}@x.co`;

    await expect(createUser(longest)).resolves.toMatchObject({ email: longest });
  });

  it("lets only one of two simultaneous sign-ups with the same email succeed", async () => {
    const attempts = await Promise.allSettled([createUser("race@example.com"), createUser("race@example.com")]);

    const rejected = attempts.filter((attempt) => attempt.status === "rejected");

    expect(attempts.filter((attempt) => attempt.status === "fulfilled")).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    expect(rejected[0]?.reason).toMatchObject(UNIQUE_VIOLATION);
  });

  it("leaves nothing behind when a transaction fails half way", async () => {
    const failing = prisma.$transaction(async (transaction) => {
      await transaction.user.create({ data: { email: "rollback@example.com", passwordHash: "test-hash", displayName: "Gone" } });
      throw new Error("fail after the insert");
    });

    await expect(failing).rejects.toThrow("fail after the insert");
    expect(await prisma.user.count()).toBe(0);
  });

  it("keeps hostile and unicode text as plain data", async () => {
    const user = await prisma.user.create({
      data: { email: "hostile@example.com", passwordHash: "test-hash", displayName: HOSTILE_TEXT },
    });

    const stored = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });

    expect(stored.displayName).toBe(HOSTILE_TEXT);
  });
});

describe("refresh tokens", () => {
  it("need an existing user", async () => {
    const orphan = prisma.refreshToken.create({
      data: { userId: MISSING_ID, tokenHash: "a".repeat(64), familyId: MISSING_ID, expiresAt: new Date() },
    });

    await expect(orphan).rejects.toMatchObject(FOREIGN_KEY_VIOLATION);
  });

  it("store only a unique hash and start unrevoked", async () => {
    const user = await createUser();
    const data = { userId: user.id, tokenHash: "b".repeat(64), familyId: MISSING_ID, expiresAt: new Date() };

    const token = await prisma.refreshToken.create({ data });

    expect(token.revokedAt).toBeNull();
    await expect(prisma.refreshToken.create({ data })).rejects.toMatchObject(UNIQUE_VIOLATION);
  });

  it("are deleted with their user", async () => {
    const user = await createUser();
    await prisma.refreshToken.create({
      data: { userId: user.id, tokenHash: "c".repeat(64), familyId: MISSING_ID, expiresAt: new Date() },
    });

    await prisma.user.delete({ where: { id: user.id } });

    expect(await prisma.refreshToken.count()).toBe(0);
  });
});

describe("catalog", () => {
  it("keeps one track per external source and id", async () => {
    const artist = await createArtist();
    await createTrack(artist.id, "same-id");

    await expect(createTrack(artist.id, "same-id")).rejects.toMatchObject(UNIQUE_VIOLATION);
  });

  it("keeps one artist per external source and id", async () => {
    await createArtist("same-id");

    await expect(createArtist("same-id")).rejects.toMatchObject(UNIQUE_VIOLATION);
  });

  it("keeps one album per external source and id", async () => {
    const artist = await createArtist();
    const data = { title: "Album", artistId: artist.id, externalSource: "JAMENDO" as const, externalId: "album-1" };
    await prisma.album.create({ data });

    await expect(prisma.album.create({ data })).rejects.toMatchObject(UNIQUE_VIOLATION);
  });

  it("refuses to delete an artist that still has albums", async () => {
    const artist = await createArtist();
    await prisma.album.create({
      data: { title: "Album", artistId: artist.id, externalSource: "JAMENDO", externalId: "album-1" },
    });

    await expect(prisma.artist.delete({ where: { id: artist.id } })).rejects.toMatchObject(FOREIGN_KEY_VIOLATION);
  });

  it("keeps the tracks of a deleted album as singles", async () => {
    const artist = await createArtist();
    const album = await prisma.album.create({
      data: { title: "Album", artistId: artist.id, externalSource: "JAMENDO", externalId: "album-1" },
    });
    const track = await createTrack(artist.id);
    await prisma.track.update({ where: { id: track.id }, data: { albumId: album.id } });

    await prisma.album.delete({ where: { id: album.id } });

    const kept = await prisma.track.findUniqueOrThrow({ where: { id: track.id } });
    expect(kept.albumId).toBeNull();
  });

  it("rejects a licence longer than 64 characters", async () => {
    const artist = await createArtist();

    const track = prisma.track.create({
      data: {
        title: "Long licence",
        artistId: artist.id,
        durationSeconds: 60,
        externalSource: "JAMENDO",
        externalId: "long-licence",
        license: "L".repeat(65),
        downloadAllowed: true,
        allowsDerivatives: true,
      },
    });

    await expect(track).rejects.toMatchObject(VALUE_TOO_LONG);
  });

  it("needs an existing artist for a track", async () => {
    await expect(createTrack(MISSING_ID)).rejects.toMatchObject(FOREIGN_KEY_VIOLATION);
  });

  it("allows a single without an album and a track with one", async () => {
    const artist = await createArtist();
    const album = await prisma.album.create({
      data: { title: "Album", artistId: artist.id, externalSource: "JAMENDO", externalId: "album-1" },
    });

    const single = await createTrack(artist.id, "single");
    const albumTrack = await createTrack(artist.id, "album-track");
    const placed = await prisma.track.update({ where: { id: albumTrack.id }, data: { albumId: album.id } });

    expect(single.albumId).toBeNull();
    expect(placed.albumId).toBe(album.id);
  });

  it("refuses to delete an artist that still has tracks", async () => {
    const artist = await createArtist();
    await createTrack(artist.id);

    await expect(prisma.artist.delete({ where: { id: artist.id } })).rejects.toMatchObject(FOREIGN_KEY_VIOLATION);
  });

  it("stores the licence facts of a track", async () => {
    const artist = await createArtist();

    const track = await prisma.track.create({
      data: {
        title: "Locked",
        artistId: artist.id,
        durationSeconds: 90,
        externalSource: "JAMENDO",
        externalId: "locked",
        license: "CC-BY-NC-ND",
        downloadAllowed: false,
        allowsDerivatives: false,
      },
    });

    expect(track).toMatchObject({ license: "CC-BY-NC-ND", downloadAllowed: false, allowsDerivatives: false });
  });

  it("keeps hostile and unicode text in names", async () => {
    const artist = await createArtist("hostile", HOSTILE_TEXT);

    const stored = await prisma.artist.findUniqueOrThrow({ where: { id: artist.id } });

    expect(stored.name).toBe(HOSTILE_TEXT);
  });
});

describe("optional catalog and playlist columns", () => {
  it("leaves the audio object key empty until audio is stored, and accepts 1024 characters", async () => {
    const artist = await createArtist();
    const track = await createTrack(artist.id);
    const withKey = await prisma.track.update({ where: { id: track.id }, data: { audioObjectKey: "k".repeat(1024) } });

    expect(track.audioObjectKey).toBeNull();
    expect(withKey.audioObjectKey).toHaveLength(1024);
  });

  it("rejects an audio object key longer than 1024 characters", async () => {
    const artist = await createArtist();
    const track = await createTrack(artist.id);

    const update = prisma.track.update({ where: { id: track.id }, data: { audioObjectKey: "k".repeat(1025) } });

    await expect(update).rejects.toMatchObject(VALUE_TOO_LONG);
  });

  it("stores the release date of an album, which is optional", async () => {
    const artist = await createArtist();
    const withoutDate = await prisma.album.create({
      data: { title: "Undated", artistId: artist.id, externalSource: "JAMENDO", externalId: "undated" },
    });
    const withDate = await prisma.album.create({
      data: {
        title: "Dated",
        artistId: artist.id,
        externalSource: "JAMENDO",
        externalId: "dated",
        releasedAt: new Date("2020-05-17"),
      },
    });

    expect(withoutDate.releasedAt).toBeNull();
    expect(withDate.releasedAt?.toISOString().slice(0, 10)).toBe("2020-05-17");
  });

  it("lets a playlist be made public", async () => {
    const user = await createUser();

    const playlist = await prisma.playlist.create({ data: { userId: user.id, name: "Shared", isPublic: true } });

    expect(playlist.isPublic).toBe(true);
  });
});

describe("playlists", () => {
  it("need an existing user", async () => {
    await expect(createPlaylist(MISSING_ID)).rejects.toMatchObject(FOREIGN_KEY_VIOLATION);
  });

  it("are private by default", async () => {
    const playlist = await createPlaylist((await createUser()).id);

    expect(playlist.isPublic).toBe(false);
  });

  it("reject a name longer than 100 characters", async () => {
    const user = await createUser();

    const playlist = prisma.playlist.create({ data: { userId: user.id, name: "n".repeat(101) } });

    await expect(playlist).rejects.toMatchObject(VALUE_TOO_LONG);
  });

  it("reject a negative position", async () => {
    const artist = await createArtist();
    const playlist = await createPlaylist((await createUser()).id);

    await expect(addToPlaylist(playlist.id, (await createTrack(artist.id)).id, -1)).rejects.toMatchObject(OUT_OF_RANGE);
  });

  it("keep one position per item", async () => {
    const artist = await createArtist();
    const playlist = await createPlaylist((await createUser()).id);
    await addToPlaylist(playlist.id, (await createTrack(artist.id, "t1")).id, 1);

    const clash = addToPlaylist(playlist.id, (await createTrack(artist.id, "t2")).id, 1);

    await expect(clash).rejects.toMatchObject(UNIQUE_VIOLATION);
  });

  it("hold a track only once but allow it in other playlists", async () => {
    const artist = await createArtist();
    const track = await createTrack(artist.id);
    const user = await createUser();
    const first = await createPlaylist(user.id);
    const second = await createPlaylist(user.id);
    await addToPlaylist(first.id, track.id, 1);

    await expect(addToPlaylist(first.id, track.id, 2)).rejects.toMatchObject(UNIQUE_VIOLATION);
    await expect(addToPlaylist(second.id, track.id, 1)).resolves.toBeDefined();
  });

  it("delete their items with the playlist but keep the track", async () => {
    const artist = await createArtist();
    const track = await createTrack(artist.id);
    const playlist = await createPlaylist((await createUser()).id);
    await addToPlaylist(playlist.id, track.id);

    await prisma.playlist.delete({ where: { id: playlist.id } });

    expect(await prisma.playlistTrack.count()).toBe(0);
    expect(await prisma.track.count()).toBe(1);
  });

  it("are deleted with their user", async () => {
    const user = await createUser();
    await createPlaylist(user.id);

    await prisma.user.delete({ where: { id: user.id } });

    expect(await prisma.playlist.count()).toBe(0);
  });

  it("lose a track that is removed from the catalog", async () => {
    const artist = await createArtist();
    const track = await createTrack(artist.id);
    const playlist = await createPlaylist((await createUser()).id);
    await addToPlaylist(playlist.id, track.id);

    await prisma.track.delete({ where: { id: track.id } });

    expect(await prisma.playlistTrack.count()).toBe(0);
    expect(await prisma.playlist.count()).toBe(1);
  });
});

describe("search", () => {
  it("finds tracks by words in the title with a full-text index", async () => {
    const artist = await createArtist();
    const match = await createTrack(artist.id, "moon", "Moonlight Sonata");
    await createTrack(artist.id, "day", "Daylight Waltz");

    const rows = await prisma.$queryRaw<{ id: string }[]>`
      SELECT id FROM Track WHERE MATCH(title) AGAINST (${"moonlight"} IN NATURAL LANGUAGE MODE)
    `;

    expect(rows.map((row) => row.id)).toEqual([match.id]);
  });
});

describe("text columns of 255 characters", () => {
  const tooLong = "x".repeat(256);

  it("reject an artist name that is too long", async () => {
    await expect(createArtist("long-name", tooLong)).rejects.toMatchObject(VALUE_TOO_LONG);
  });

  it("reject an album title that is too long", async () => {
    const artist = await createArtist();
    const album = prisma.album.create({
      data: { title: tooLong, artistId: artist.id, externalSource: "JAMENDO", externalId: "long-title" },
    });

    await expect(album).rejects.toMatchObject(VALUE_TOO_LONG);
  });

  it("reject a track title that is too long", async () => {
    const artist = await createArtist();

    await expect(createTrack(artist.id, "long-title", tooLong)).rejects.toMatchObject(VALUE_TOO_LONG);
  });

  it("reject an external id longer than 64 characters", async () => {
    await expect(createArtist("e".repeat(65))).rejects.toMatchObject(VALUE_TOO_LONG);
  });
});

describe("search on names", () => {
  it("finds artists and albums by words in their name", async () => {
    const artist = await createArtist("sigur", "Sigur Ros");
    await prisma.album.create({
      data: { title: "Takk Together", artistId: artist.id, externalSource: "JAMENDO", externalId: "takk" },
    });

    const artists = await prisma.$queryRaw<{ id: string }[]>`
      SELECT id FROM Artist WHERE MATCH(name) AGAINST (${"sigur"} IN NATURAL LANGUAGE MODE)
    `;
    const albums = await prisma.$queryRaw<{ id: string }[]>`
      SELECT id FROM Album WHERE MATCH(title) AGAINST (${"takk"} IN NATURAL LANGUAGE MODE)
    `;

    expect(artists.map((row) => row.id)).toEqual([artist.id]);
    expect(albums).toHaveLength(1);
  });
});

describe("storage rules", () => {
  it("creates every table with the utf8mb4 unicode collation", async () => {
    const tables = await prisma.$queryRaw<{ tableName: string; collation: string }[]>`
      SELECT TABLE_NAME AS tableName, TABLE_COLLATION AS collation
      FROM information_schema.TABLES
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_TYPE = 'BASE TABLE'
        AND TABLE_NAME <> '_prisma_migrations'
    `;

    expect(tables.length).toBeGreaterThan(0);
    expect(tables.filter((table) => table.collation !== "utf8mb4_unicode_ci")).toEqual([]);
  });
});

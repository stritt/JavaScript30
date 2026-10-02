import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { archiveWeek } from "../src/cron/weeklyReset";
import { boardName } from "../src/do/BoardDO";
import { boardStub } from "../src/lib/boards";
import { currentWeek, isoWeek, parseDay } from "../src/lib/util";
import { api, daysAgo, deliverSteps, signUp, today } from "./helpers";

type Board = {
  entries: { rank: number; playerId: string; displayName: string; value: number; isMe: boolean }[];
  me: { rank: number; value: number } | null;
  region: string | null;
};

describe("util", () => {
  it("computes ISO weeks across year boundaries", () => {
    expect(isoWeek(parseDay("2026-10-02")!)).toBe("2026-W40");
    expect(isoWeek(parseDay("2026-01-01")!)).toBe("2026-W01");
    expect(isoWeek(parseDay("2027-01-01")!)).toBe("2026-W53");
    expect(isoWeek(parseDay("2024-12-30")!)).toBe("2025-W01");
  });

  it("rejects impossible dates", () => {
    expect(parseDay("2026-02-30")).toBeNull();
    expect(parseDay("2026-2-3")).toBeNull();
  });
});

describe("config", () => {
  it("serves the shared formulas publicly", async () => {
    const res = await api("GET", "/v1/config");
    expect(res.status).toBe(200);
    const json = (await res.json()) as { zones: unknown[]; stride: { gateStepMultiplier: number } };
    expect(json.zones.length).toBeGreaterThanOrEqual(3);
    expect(json.stride.gateStepMultiplier).toBe(1.5);
  });
});

describe("auth", () => {
  it("rejects requests without a token", async () => {
    expect((await api("GET", "/v1/me")).status).toBe(401);
    expect((await api("GET", "/v1/me", { token: "garbage" })).status).toBe(401);
  });

  it("dev login is idempotent per device", async () => {
    const body = { deviceId: "device-stable-1234", displayName: "Ava" };
    const a = (await (await api("POST", "/v1/auth/dev", { body })).json()) as { player: { id: string } };
    const b = (await (await api("POST", "/v1/auth/dev", { body })).json()) as { player: { id: string } };
    expect(a.player.id).toBe(b.player.id);
  });

  it("rejects an unverifiable Apple token", async () => {
    const res = await api("POST", "/v1/auth/apple", { body: { identityToken: "not.a.jwt" } });
    expect(res.status).toBe(401);
  });
});

describe("me", () => {
  it("returns the player and lets progress only move forward", async () => {
    const { token } = await signUp("Bran", "US-CA-San Francisco");
    const res = await api("GET", "/v1/me", { token });
    const json = (await res.json()) as { player: { displayName: string; heroLevel: number; region: string } };
    expect(json.player.displayName).toBe("Bran");
    expect(json.player.region).toBe("US-CA-San Francisco");

    let patch = await api("PATCH", "/v1/me", { token, body: { heroLevel: 7, zone: 2 } });
    expect(((await patch.json()) as any).player).toMatchObject({ heroLevel: 7, zone: 2 });

    patch = await api("PATCH", "/v1/me", { token, body: { heroLevel: 3, zone: 1 } });
    expect(((await patch.json()) as any).player).toMatchObject({ heroLevel: 7, zone: 2 });

    patch = await api("PATCH", "/v1/me", { token, body: { heroLevel: 500 } });
    expect(((await patch.json()) as any).player.heroLevel).toBe(99);
  });

  it("validates input", async () => {
    const { token } = await signUp("Val");
    expect((await api("PATCH", "/v1/me", { token, body: { heroLevel: "9" } })).status).toBe(400);
    expect((await api("PATCH", "/v1/me", { token, body: { displayName: "   " } })).status).toBe(400);
    expect((await api("PATCH", "/v1/me", { token, body: { localOptIn: "yes" } })).status).toBe(400);
  });
});

describe("steps upload", () => {
  it("accepts valid days", async () => {
    const { token } = await signUp("Walker");
    const res = await api("POST", "/v1/steps", {
      token,
      body: { days: [{ day: today(), steps: 4200, flights: 3 }, { day: daysAgo(1), steps: 9000 }] },
    });
    expect(res.status).toBe(202);
    expect(await res.json()).toEqual({ accepted: 2 });
  });

  it.each([
    ["empty", { days: [] }],
    ["bad date", { days: [{ day: "yesterday", steps: 1 }] }],
    ["future", { days: [{ day: "2999-01-01", steps: 1 }] }],
    ["too old", { days: [{ day: daysAgo(30), steps: 1 }] }],
    ["negative", { days: [{ day: today(), steps: -5 }] }],
    ["fractional", { days: [{ day: today(), steps: 1.5 }] }],
    ["duplicate", { days: [{ day: today(), steps: 1 }, { day: today(), steps: 2 }] }],
  ])("rejects %s", async (_label, body) => {
    const { token } = await signUp("Bad");
    expect((await api("POST", "/v1/steps", { token, body })).status).toBe(400);
  });
});

describe("step ingestion + leaderboards", () => {
  it("keeps the max per day and ranks the global weekly board", async () => {
    const ava = await signUp("Ava");
    const ben = await signUp("Ben");

    await deliverSteps({ playerId: ava.id, days: [{ day: today(), steps: 5000, flights: 0 }], receivedAt: "" });
    await deliverSteps({ playerId: ava.id, days: [{ day: today(), steps: 3000, flights: 0 }], receivedAt: "" }); // stale re-upload
    await deliverSteps({ playerId: ben.id, days: [{ day: today(), steps: 12000, flights: 2 }], receivedAt: "" });

    const me = (await (await api("GET", "/v1/me", { token: ava.token })).json()) as { weekSteps: number };
    expect(me.weekSteps).toBe(5000);

    const board = (await (await api("GET", "/v1/boards/global", { token: ava.token })).json()) as Board;
    const ids = board.entries.map((e) => e.playerId);
    expect(ids.indexOf(ben.id)).toBeLessThan(ids.indexOf(ava.id));
    expect(board.entries.find((e) => e.playerId === ava.id)).toMatchObject({ value: 5000, isMe: true });
    expect(board.me?.value).toBe(5000);
    expect(board.me!.rank).toBeGreaterThan(1);
  });

  it("flags implausible totals and drops the player from public boards", async () => {
    const cheat = await signUp("Shaker");
    await deliverSteps({ playerId: cheat.id, days: [{ day: today(), steps: 250000, flights: 0 }], receivedAt: "" });

    const me = (await (await api("GET", "/v1/me", { token: cheat.token })).json()) as {
      player: { flagged: boolean };
      weekSteps: number;
    };
    expect(me.player.flagged).toBe(true);
    expect(me.weekSteps).toBe(100000); // clamped to maxStepsPerDay

    const rank = await boardStub(env, boardName("global", "steps", currentWeek())).rankOf(cheat.id);
    expect(rank).toBeNull();
  });

  it("serves local boards only to opted-in players in the same region", async () => {
    const sf1 = await signUp("Sf1", "US-CA-San Francisco");
    const sf2 = await signUp("Sf2", "US-CA-San Francisco");
    const nyc = await signUp("Nyc", "US-NY-New York");

    expect((await api("GET", "/v1/boards/local", { token: sf1.token })).status).toBe(409);

    for (const p of [sf1, sf2, nyc]) {
      await api("PATCH", "/v1/me", { token: p.token, body: { localOptIn: true } });
    }
    await deliverSteps({ playerId: sf1.id, days: [{ day: today(), steps: 7000, flights: 0 }], receivedAt: "" });
    await deliverSteps({ playerId: sf2.id, days: [{ day: today(), steps: 9000, flights: 0 }], receivedAt: "" });
    await deliverSteps({ playerId: nyc.id, days: [{ day: today(), steps: 20000, flights: 0 }], receivedAt: "" });

    const board = (await (await api("GET", "/v1/boards/local", { token: sf1.token })).json()) as Board;
    expect(board.region).toBe("US-CA-San Francisco");
    expect(board.entries.map((e) => e.displayName)).toEqual(["Sf2", "Sf1"]);
    expect(board.me).toEqual({ rank: 2, value: 7000 });

    // Opting out removes you from the local board.
    await api("PATCH", "/v1/me", { token: sf2.token, body: { localOptIn: false } });
    const rank = await boardStub(env, boardName("local:US-CA-San Francisco", "steps", currentWeek())).rankOf(sf2.id);
    expect(rank).toBeNull();
  });

  it("ranks level and zone boards", async () => {
    const a = await signUp("Lvl");
    await api("PATCH", "/v1/me", { token: a.token, body: { heroLevel: 42, zone: 3 } });
    const level = (await (await api("GET", "/v1/boards/global?metric=level", { token: a.token })).json()) as Board;
    expect(level.me?.value).toBe(42);
    expect((await api("GET", "/v1/boards/global?metric=gold", { token: a.token })).status).toBe(400);
    expect((await api("GET", "/v1/boards/galaxy", { token: a.token })).status).toBe(404);
  });
});

describe("friends", () => {
  it("invites, accepts, ranks friends and unfriends", async () => {
    const host = await signUp("Host");
    const guest = await signUp("Guest");
    const stranger = await signUp("Stranger");

    const invite = (await (await api("POST", "/v1/friends/invite", { token: host.token })).json()) as { code: string; url: string };
    expect(invite.code).toMatch(/^[A-Z2-9]{6}$/);
    expect(invite.url).toContain(invite.code);

    expect((await api("POST", "/v1/friends/accept", { token: host.token, body: { code: invite.code } })).status).toBe(400);
    expect((await api("POST", "/v1/friends/accept", { token: guest.token, body: { code: "ZZZZZZ" } })).status).toBe(404);

    const accepted = await api("POST", "/v1/friends/accept", { token: guest.token, body: { code: invite.code.toLowerCase() } });
    expect(accepted.status).toBe(200);
    expect(((await accepted.json()) as any).friend.id).toBe(host.id);

    await deliverSteps({ playerId: host.id, days: [{ day: today(), steps: 3000, flights: 0 }], receivedAt: "" });
    await deliverSteps({ playerId: guest.id, days: [{ day: today(), steps: 8000, flights: 0 }], receivedAt: "" });
    await deliverSteps({ playerId: stranger.id, days: [{ day: today(), steps: 50000, flights: 0 }], receivedAt: "" });

    const board = (await (await api("GET", "/v1/boards/friends", { token: host.token })).json()) as Board;
    expect(board.entries.map((e) => e.displayName)).toEqual(["Guest", "Host"]);
    expect(board.me).toEqual({ rank: 2, value: 3000 });

    const list = (await (await api("GET", "/v1/friends", { token: guest.token })).json()) as { friends: { id: string; weekSteps: number }[] };
    expect(list.friends).toEqual([expect.objectContaining({ id: host.id, weekSteps: 3000 })]);

    expect((await api("DELETE", `/v1/friends/${host.id}`, { token: guest.token })).status).toBe(204);
    const after = (await (await api("GET", "/v1/friends", { token: host.token })).json()) as { friends: unknown[] };
    expect(after.friends).toEqual([]);
  });
});

describe("weekly archive cron", () => {
  it("archives the finished week's top players and clears the board", async () => {
    const week = "2020-W10";
    const stub = boardStub(env, boardName("global", "steps", week));
    await stub.upsert({ playerId: "p_a", displayName: "A", value: 100, heroLevel: 1 });
    await stub.upsert({ playerId: "p_b", displayName: "B", value: 300, heroLevel: 1 });

    const result = await archiveWeek(env, week);
    expect(result.rows).toBeGreaterThanOrEqual(2);

    const { results } = await env.DB.prepare(
      "SELECT player_id, rank, value FROM season_results WHERE week = ? AND board = 'global|steps' ORDER BY rank",
    )
      .bind(week)
      .all();
    expect(results).toEqual([
      { player_id: "p_b", rank: 1, value: 300 },
      { player_id: "p_a", rank: 2, value: 100 },
    ]);
    expect(await stub.size()).toBe(0);
  });
});

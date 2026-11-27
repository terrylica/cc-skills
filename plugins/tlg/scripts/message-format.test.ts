import { describe, expect, test } from "bun:test";
import { climb, formatLine, recordOf, stamp, viewOf } from "./message-format.ts";

// Plain objects shaped like GramJS's Api.Message (duck-typed; no network).
const T = 1764187191; // 2025-11-26T19:59:51Z
const reply = (id: number, parent: number, extra: Record<string, unknown> = {}) => ({
  id,
  date: T,
  message: `text ${id}`,
  replyTo: { className: "MessageReplyHeader", replyToMsgId: parent, ...extra },
});

describe("viewOf", () => {
  test("a plain message has no reply, topic, quote or media", () => {
    const v = viewOf({ id: 5, date: T, message: "hi" }, "Ann");
    expect(v.replyToId).toBeUndefined();
    expect(v.topicId).toBeUndefined();
    expect(v.quote).toBeUndefined();
    expect(v.media).toBeUndefined();
    expect(v.out).toBe(false);
  });

  test("a reply names its parent and the quoted part", () => {
    const v = viewOf(reply(812, 805, { quote: true, quoteText: "只看第三张图" }), "Ann Lee");
    expect(v.replyToId).toBe(805);
    expect(v.quote).toBe("只看第三张图");
  });

  test("quoteText without the quote flag is not shown", () => {
    expect(viewOf(reply(2, 1, { quoteText: "x" }), "A").quote).toBeUndefined();
  });

  test("in a forum topic, a message that only sits in the topic is not a reply", () => {
    const v = viewOf(reply(40, 7, { forumTopic: true }), "A");
    expect(v.topicId).toBe(7);
    expect(v.replyToId).toBeUndefined();
  });

  test("in a forum topic, a reply keeps its parent and the topic", () => {
    const v = viewOf(reply(41, 40, { forumTopic: true, replyToTopId: 7 }), "A");
    expect(v.topicId).toBe(7);
    expect(v.replyToId).toBe(40);
  });

  test("a parent in another chat is labelled", () => {
    const v = viewOf(reply(3, 99, { replyToPeerId: { channelId: 123 } }), "A");
    expect(v.replyToPeer).toBe("channel:123");
  });

  test("a story reply header is not a message reply", () => {
    const v = viewOf({ id: 4, date: T, message: "", replyTo: { className: "MessageReplyStoryHeader", storyId: 1 } }, "A");
    expect(v.replyToId).toBeUndefined();
  });

  test("media, album, edit, forward and service action are read from their fields", () => {
    const v = viewOf(
      {
        id: 6,
        date: T,
        message: "caption",
        media: { className: "MessageMediaPhoto" },
        groupedId: 13_975_000_000_000_000n,
        editDate: T + 60,
        fwdFrom: { fromName: "Bob" },
        out: true,
      },
      "me",
    );
    expect(v.media).toBe("photo");
    expect(v.album).toBe("13975000000000000");
    expect(v.edited).toBe(T + 60);
    expect(v.fwdFrom).toBe("Bob");
    expect(v.out).toBe(true);
    const s = viewOf({ id: 7, date: T, action: { className: "MessageActionChatAddUser" } }, "A");
    expect(s.action).toBe("chat add user");
  });

  test("a forward with neither name nor peer has an empty origin", () => {
    expect(viewOf({ id: 8, date: T, message: "x", fwdFrom: {} }, "A").fwdFrom).toBe("");
    expect(viewOf({ id: 8, date: T, message: "x", fwdFrom: { fromId: { userId: 9 } } }, "A").fwdFrom).toBe("user:9");
  });
});

describe("stamp", () => {
  test("local time carries the zone's label; --utc says UTC", () => {
    expect(stamp(T, { zone: "UTC", utc: true })).toBe("2025-11-26 19:59:51 UTC");
    expect(stamp(T, { zone: "Asia/Shanghai" })).toMatch(/^2025-11-27 03:59:51 /);
    expect(stamp(T, { utc: true, seconds: false })).toBe("2025-11-26 19:59 UTC");
  });

  test("no date gives an empty stamp", () => {
    expect(stamp(undefined)).toBe("");
  });
});

describe("formatLine", () => {
  const utc = { utc: true };

  test("a plain message keeps the old shape", () => {
    expect(formatLine(viewOf({ id: 5, date: T, message: "hi" }, "Ann"), utc)).toBe("[2025-11-26 19:59:51 UTC] (id:5) Ann: hi");
  });

  test("a reply shows ↩parent and the quote on its own line", () => {
    const line = formatLine(viewOf(reply(812, 805, { quote: true, quoteText: "只看第三张图" }), "Ann Lee"), utc);
    expect(line).toBe("[2025-11-26 19:59:51 UTC] (id:812) Ann Lee: ↩805 text 812\n    ❝只看第三张图❞");
  });

  test("markers for topic, album, edit, forward and media", () => {
    const v = viewOf(
      {
        ...reply(41, 40, { forumTopic: true, replyToTopId: 7 }),
        groupedId: 9,
        editDate: T,
        fwdFrom: {},
        media: { className: "MessageMediaDocument" },
        message: "cap",
      },
      "A",
    );
    expect(formatLine(v, utc)).toBe("[2025-11-26 19:59:51 UTC] (id:41) A: ↩40 topic:7 album:9 (edited) [fwd] [document] cap");
  });

  test("a service message shows its action and no media marker; an empty body renders nothing", () => {
    const v = viewOf({ id: 7, date: T, message: "", action: { className: "MessageActionPinMessage" }, media: { className: "MessageMediaPhoto" } }, "A");
    expect(formatLine(v, utc)).toBe("[2025-11-26 19:59:51 UTC] (id:7) A: [service: pin message]");
  });

  test("preview flattens and cuts the body; multi-line bodies indent under the indent", () => {
    const v = viewOf({ id: 1, date: T, message: "a\nb\nc" }, "A");
    expect(formatLine(v, { ...utc, preview: 4 })).toBe("[2025-11-26 19:59:51 UTC] (id:1) A: a ⏎ …");
    expect(formatLine(v, { ...utc, indent: "  " })).toBe("  [2025-11-26 19:59:51 UTC] (id:1) A: a\n      b\n      c");
  });

  test("a chat label comes first in a listing across chats", () => {
    expect(formatLine(viewOf({ id: 1, date: T, message: "x" }, "A"), { ...utc, chat: "Team -1001" })).toBe(
      "[2025-11-26 19:59:51 UTC] (id:1) A: {Team -1001} x",
    );
  });
});

describe("formatLine line contract", () => {
  // Scripts that poll `read` (a reply watcher) match this header and then require the sender label right after it.
  const HEADER = /^\[[^\]]+\] \(id:[0-9]+\) /;
  const cases = [
    viewOf({ id: 1, date: T, message: "plain" }, "Ann"),
    viewOf({ ...reply(41, 40, { forumTopic: true, replyToTopId: 7, quote: true, quoteText: "q" }), groupedId: 9, editDate: T, fwdFrom: { fromName: "B" }, media: { className: "MessageMediaPhoto" } }, "Ann"),
    viewOf({ id: 7, date: T, message: "", action: { className: "MessageActionPinMessage" } }, "Ann"),
  ];
  for (const v of cases) {
    for (const opts of [{}, { utc: true }, { preview: 20 }]) {
      test(`id ${v.id} ${JSON.stringify(opts)} keeps "[time] (id:N) Sender: "`, () => {
        const line = formatLine(v, opts).split("\n")[0] ?? "";
        const m = HEADER.exec(line);
        expect(m).not.toBeNull();
        expect(line.slice(m?.[0].length).startsWith("Ann:")).toBe(true);
      });
    }
  }
});

describe("formatLine mark", () => {
  test("the mark prefixes the first line only, not continuation or quote lines", () => {
    const v = viewOf({ ...reply(9, 5, { quote: true, quoteText: "q" }), message: "a\nb" }, "X");
    expect(formatLine(v, { utc: true, indent: "  ", mark: "▶ " })).toBe(
      "  ▶ [2025-11-26 19:59:51 UTC] (id:9) X: ↩5 a\n      b\n      ❝q❞",
    );
  });
});

describe("recordOf", () => {
  test("reply_to_msg_id is Telegram's stored value, reply_parent the real parent (as in dump)", () => {
    const r = recordOf(viewOf(reply(40, 7, { forumTopic: true }), "A"));
    expect(r.reply_to_msg_id).toBe(7);
    expect(r.reply_parent).toBeNull();
    expect(r.forum_topic_id).toBe(7);
  });

  test("carries every field, null when absent", () => {
    const r = recordOf(viewOf(reply(2, 1, { quote: true, quoteText: "q" }), "A", 77), { extra: 1 });
    expect(r).toMatchObject({
      id: 2,
      date: "2025-11-26T19:59:51.000Z",
      reply_to_msg_id: 1,
      reply_parent: 1,
      quote_text: "q",
      forum_topic_id: null,
      fwd_from: null,
      sender_name: "A",
      sender_id: 77,
      extra: 1,
    });
  });
});

describe("climb", () => {
  const store = (msgs: any[]) => {
    const byId = new Map(msgs.map((m) => [m.id, m]));
    const asked: number[] = [];
    return { fetch: async (id: number) => (asked.push(id), byId.get(id)), asked };
  };

  test("climbs to the start of the conversation", async () => {
    const s = store([{ id: 1, date: T, message: "root" }, reply(2, 1), reply(3, 2)]);
    const { chain, stop } = await climb(3, s.fetch);
    expect(chain.map((m) => m.id)).toEqual([3, 2, 1]);
    expect(stop).toBe("start of the conversation");
  });

  test("stops at a deleted parent", async () => {
    const s = store([reply(3, 2)]);
    const { chain, stop } = await climb(3, s.fetch);
    expect(chain.map((m) => m.id)).toEqual([3]);
    expect(stop).toBe("message 2 is deleted or not in this chat");
  });

  test("a missing start says not found", async () => {
    expect((await climb(9, store([]).fetch)).stop).toBe("message 9 not found");
  });

  test("stops at the depth limit and on a cycle", async () => {
    const s = store([reply(1, 2), reply(2, 1)]);
    expect((await climb(1, s.fetch)).stop).toBe("cycle at 1");
    const d = store([reply(4, 3), reply(3, 2), reply(2, 1), { id: 1, date: T }]);
    const r = await climb(4, d.fetch, 2);
    expect(r.chain.map((m) => m.id)).toEqual([4, 3]);
    expect(r.stop).toMatch(/^depth 2 reached/);
  });

  test("stops at a forum topic's root and at a parent in another chat", async () => {
    const t = store([reply(41, 7, { forumTopic: true })]);
    expect((await climb(41, t.fetch)).stop).toBe("topic 7 root");
    const p = store([reply(3, 99, { replyToPeerId: { channelId: 5 } })]);
    expect((await climb(3, p.fetch)).stop).toBe("parent 99 is in channel:5");
  });
});

describe("tg-cli count flags", () => {
  // GramJS reads a limit of 0 or NaN as no limit, so these must be refused before any connection is made.
  for (const args of [["read", "me", "-n", "0"], ["read", "me", "-n", "abc"], ["thread", "me", "5", "--scan", "0"], ["thread", "me", "5", "--depth", "x"], ["search", "q", "-n", "0"]]) {
    test(`${args.join(" ")} is a usage error`, () => {
      const r = Bun.spawnSync(["bun", `${import.meta.dir}/tg-cli.ts`, ...args], { env: { ...process.env, HOME: "/nonexistent" } });
      expect(r.exitCode).toBe(2);
      expect(r.stderr.toString()).toMatch(/--(limit|scan|depth)/);
    });
  }
});

import { describe, expect, test } from "bun:test";
import { Api, bigInt, Logger, LogLevel, StringSession, TelegramClient } from "./vendor/telegram.js";
import { editableEntities, inputUserFromPeer, relinkedEntities, withExactLinkEntities } from "./link-entities.ts";
import { exactOutgoing } from "./tg-cli.ts";

// Never connected: only its default parse mode (GramJS markdown) is used.
const offline = new TelegramClient(new StringSession(""), 1, "offline", { baseLogger: new Logger(LogLevel.NONE) });

const textUrls = (entities: readonly Api.TypeMessageEntity[] | undefined) =>
  (entities ?? [])
    .filter((e) => e instanceof Api.MessageEntityTextUrl)
    .map((e) => ({ offset: e.offset, length: e.length, url: (e as Api.MessageEntityTextUrl).url }));

describe("withExactLinkEntities", () => {
  test("adds one exact TextUrl per bare link", () => {
    const raw = "打开 github.com/login/device，用你自己的账号";
    expect(textUrls(withExactLinkEntities(raw, []))).toEqual([
      { offset: 3, length: 23, url: "https://github.com/login/device" },
    ]);
  });

  test("returns undefined when there is nothing to link", () => {
    expect(withExactLinkEntities("没有链接 tg-cli.ts", [])).toBeUndefined();
  });

  test("leaves links inside code alone and keeps other entities, sorted", () => {
    const raw = "github.com/a 和 github.com/b";
    const code = new Api.MessageEntityCode({ offset: 0, length: 12 });
    const bold = new Api.MessageEntityBold({ offset: 15, length: 12 });
    const out = withExactLinkEntities(raw, [bold, code]) ?? [];
    expect(out.map((e) => e.className)).toEqual(["MessageEntityCode", "MessageEntityBold", "MessageEntityTextUrl"]);
    expect(textUrls(out)).toEqual([{ offset: 15, length: 12, url: "https://github.com/b" }]);
  });
});

describe("exactOutgoing — the CLI's send/edit/caption preparation", () => {
  test("HTML: explicit <a> per bare link, parse mode kept", () => {
    expect(exactOutgoing(offline, "<b>打开</b> github.com/login/device，用", "html")).toEqual({
      message: '<b>打开</b> <a href="https://github.com/login/device">github.com/login/device</a>，用',
      parseMode: "html",
    });
  });

  test("plain: unchanged when there is no link", () => {
    expect(exactOutgoing(offline, "**粗** 没有链接", undefined)).toEqual({ message: "**粗** 没有链接" });
  });

  test("plain: the client's markdown parse is kept and an exact TextUrl added", () => {
    const out = exactOutgoing(offline, "**打开** github.com/login/device，用你自己的账号", undefined);
    expect(out.message).toBe("打开 github.com/login/device，用你自己的账号");
    expect(out.parseMode).toBeUndefined();
    expect(out.formattingEntities?.map((e) => e.className)).toEqual(["MessageEntityBold", "MessageEntityTextUrl"]);
    expect(textUrls(out.formattingEntities)).toEqual([{ offset: 3, length: 23, url: "https://github.com/login/device" }]);
  });

  test("plain: a link in a markdown code span is not linked", () => {
    expect(exactOutgoing(offline, "运行 `github.com/x，好`", undefined).formattingEntities).toBeUndefined();
  });
});

describe("relinkedEntities — fixing a message as the server stored it", () => {
  const text = "打开 github.com/login/device，用你自己的账号";

  test("a swallowing Url is replaced by an exact TextUrl", () => {
    const { entities, changed } = relinkedEntities({
      message: text,
      entities: [new Api.MessageEntityUrl({ offset: 3, length: text.length - 3 })],
    });
    expect(changed).toBe(true);
    expect(entities.map((e) => e.className)).toEqual(["MessageEntityTextUrl"]);
    expect(textUrls(entities)).toEqual([{ offset: 3, length: 23, url: "https://github.com/login/device" }]);
  });

  test("an exact Url needs no edit", () => {
    const stored = [new Api.MessageEntityUrl({ offset: 3, length: 23 })];
    expect(relinkedEntities({ message: text, entities: stored })).toEqual({ entities: stored, changed: false });
  });

  test("a mention beside the bad link is kept", () => {
    const mention = new Api.MessageEntityMentionName({ offset: 0, length: 2, userId: bigInt(42) });
    const { entities } = relinkedEntities({
      message: text,
      entities: [mention, new Api.MessageEntityUrl({ offset: 3, length: text.length - 3 })],
    });
    expect(entities[0]).toBe(mention);
  });
});

describe("editableEntities — mentions survive messages.EditMessage", () => {
  test("MessageEntityMentionName becomes InputMessageEntityMentionName with an InputUser", async () => {
    const bold = new Api.MessageEntityBold({ offset: 5, length: 2 });
    const asked: string[] = [];
    const out = await editableEntities(
      [new Api.MessageEntityMentionName({ offset: 0, length: 4, userId: bigInt(42) }), bold],
      async (userId) => {
        asked.push(userId.toString());
        return new Api.InputUser({ userId, accessHash: bigInt(7) });
      },
    );
    expect(asked).toEqual(["42"]);
    expect(out[0]).toBeInstanceOf(Api.InputMessageEntityMentionName);
    const m = out[0] as Api.InputMessageEntityMentionName;
    expect([m.offset, m.length]).toEqual([0, 4]);
    expect(m.userId).toBeInstanceOf(Api.InputUser);
    expect((m.userId as Api.InputUser).accessHash.toString()).toBe("7");
    expect(out[1]).toBe(bold);
  });

  test("inputUserFromPeer converts user peers and refuses others", () => {
    const peer = new Api.InputPeerUser({ userId: bigInt(42), accessHash: bigInt(7) });
    const user = inputUserFromPeer(peer) as Api.InputUser;
    expect(user).toBeInstanceOf(Api.InputUser);
    expect(user.userId.toString()).toBe("42");
    expect(inputUserFromPeer(new Api.InputPeerSelf())).toBeInstanceOf(Api.InputUserSelf);
    expect(() => inputUserFromPeer(new Api.InputPeerChat({ chatId: bigInt(1) }))).toThrow("not a user");
  });
});

describe("relinkedEntities — a greedy e-mail entity", () => {
  test("is replaced by one over the address alone", () => {
    const text = "联系方式是ann@example.com，谢谢";
    const at = text.indexOf("ann");
    const { entities, changed } = relinkedEntities({
      message: text,
      entities: [new Api.MessageEntityEmail({ offset: at - 1, length: 16 })],
    });
    expect(changed).toBe(true);
    expect(entities.map((e) => [e.className, e.offset, e.length])).toEqual([["MessageEntityEmail", at, 15]]);
  });
});

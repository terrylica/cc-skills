/**
 * semantic-release configuration (CommonJS).
 *
 * Converted from .releaserc.yml (2026-07-21) so the release-notes generator can
 * carry a body-preserving `writerOpts.transform` — a JavaScript function that
 * YAML cannot express. The default Angular preset's transform returns only
 * { notes, type, scope, shortHash, subject, references } and DROPS the commit
 * body, so multi-paragraph Conventional-Commit bodies never reach the published
 * notes. This config restores the body in both the transform and the commit
 * template, so the extensive commit bodies the itp-hooks
 * release-notes-extensiveness-guard enforces actually appear in the release.
 *
 * IMPORTANT: exec command strings use SINGLE quotes (or double-quoted outer +
 * single inner) so the literal `${nextRelease.version}` survives to
 * @semantic-release/exec's lodash template step — it must NOT be interpreted as
 * a JS template expression. (This is the same lodash-vs-shell hazard iter-142
 * documented; keep every `${...}` inside a non-template-literal string.)
 *
 * Config discovery: semantic-release finds `.releaserc.{yaml,yml}` BEFORE
 * `release.config.{js,cjs}`, so the old `.releaserc.yml` was DELETED in the same
 * commit — leaving it in place would shadow this file.
 *
 * ADR: /docs/adr/2026-07-21-release-notes-extensiveness-guard.md
 */

const COMMIT_HASH_DISPLAY_LENGTH = 7;

/**
 * The literal `${nextRelease.version}` token that @semantic-release/exec expands
 * via lodash template at release time. Built by concatenation so it is NOT a JS
 * template placeholder here (that would resolve to `undefined` at require time,
 * and also trips biome's noTemplateCurlyInString). Interpolate it into exec
 * command strings via a template literal — the value below is what survives to
 * lodash. (Assembled from a variable + literal so neither biome's
 * noTemplateCurlyInString nor oxlint's no-useless-concat fires.)
 */
const DOLLAR_SIGN = "$";
const RELEASE_VERSION_PLACEHOLDER = DOLLAR_SIGN + "{nextRelease.version}";

/**
 * Body-preserving clone of conventional-changelog-angular's writerOpts.transform
 * (node_modules/conventional-changelog-angular/src/writer.js). Reproduced inline
 * — rather than imported — because the preset ships ESM and this config is CJS.
 * The ONLY functional change vs. upstream is the added `body` field on the
 * returned object (marked below); everything else mirrors the preset so grouping
 * (Features / Bug Fixes / …), scope handling, issue/user autolinking, and
 * reference de-duplication stay byte-for-byte identical to the default output.
 */
function transformCommitPreservingBody(commit, context) {
  let discard = true;
  const issues = [];

  const notes = commit.notes.map((note) => {
    discard = false;
    return { ...note, title: "BREAKING CHANGES" };
  });

  let { type } = commit;
  if (commit.type === "feat") type = "Features";
  else if (commit.type === "fix") type = "Bug Fixes";
  else if (commit.type === "perf") type = "Performance Improvements";
  else if (commit.type === "revert" || commit.revert) type = "Reverts";
  else if (discard) return undefined;
  else if (commit.type === "docs") type = "Documentation";
  else if (commit.type === "style") type = "Styles";
  else if (commit.type === "refactor") type = "Code Refactoring";
  else if (commit.type === "test") type = "Tests";
  else if (commit.type === "build") type = "Build System";
  else if (commit.type === "ci") type = "Continuous Integration";

  const scope = commit.scope === "*" ? "" : commit.scope;
  const shortHash =
    typeof commit.hash === "string"
      ? commit.hash.substring(0, COMMIT_HASH_DISPLAY_LENGTH)
      : commit.shortHash;

  let { subject } = commit;
  if (typeof subject === "string") {
    let url = context.repository
      ? `${context.host}/${context.owner}/${context.repository}`
      : context.repoUrl;
    if (url) {
      url = `${url}/issues/`;
      subject = subject.replace(/#([0-9]+)/g, (_, issue) => {
        issues.push(issue);
        return `[#${issue}](${url}${issue})`;
      });
    }
    if (context.host) {
      subject = subject.replace(/\B@([a-z0-9](?:-?[a-z0-9/]){0,38})/g, (_, username) =>
        username.includes("/") ? `@${username}` : `[@${username}](${context.host}/${username})`,
      );
    }
  }

  const references = commit.references.filter((reference) => !issues.includes(reference.issue));

  return {
    notes,
    type,
    scope,
    shortHash,
    subject,
    references,
    body: commit.body, // ← the one addition: surface the multi-paragraph body
  };
}

/**
 * commit partial = the upstream Angular commit.hbs (verbatim, so the subject
 * line, commit link, and "closes #N" references render identically) followed by
 * a body block that prints the full multi-paragraph body underneath the bullet.
 */
const COMMIT_PARTIAL_WITH_BODY = `*{{#if scope}} **{{scope}}:**
{{~/if}} {{#if subject}}
  {{~subject}}
{{~else}}
  {{~header}}
{{~/if}}

{{~!-- commit link --}} {{#if @root.linkReferences~}}
  ([{{shortHash}}](
  {{~#if @root.repository}}
    {{~#if @root.host}}
      {{~@root.host}}/
    {{~/if}}
    {{~#if @root.owner}}
      {{~@root.owner}}/
    {{~/if}}
    {{~@root.repository}}
  {{~else}}
    {{~@root.repoUrl}}
  {{~/if}}/
  {{~@root.commit}}/{{hash}}))
{{~else}}
  {{~shortHash}}
{{~/if}}

{{~!-- commit references --}}
{{~#if references~}}
  , closes
  {{~#each references}} {{#if @root.linkReferences~}}
    [
    {{~#if this.owner}}
      {{~this.owner}}/
    {{~/if}}
    {{~this.repository}}#{{this.issue}}](
    {{~#if @root.repository}}
      {{~#if @root.host}}
        {{~@root.host}}/
      {{~/if}}
      {{~#if this.repository}}
        {{~#if this.owner}}
          {{~this.owner}}/
        {{~/if}}
        {{~this.repository}}
      {{~else}}
        {{~#if @root.owner}}
          {{~@root.owner}}/
        {{~/if}}
          {{~@root.repository}}
        {{~/if}}
    {{~else}}
      {{~@root.repoUrl}}
    {{~/if}}/
    {{~@root.issue}}/{{this.issue}})
  {{~else}}
    {{~#if this.owner}}
      {{~this.owner}}/
    {{~/if}}
    {{~this.repository}}#{{this.issue}}
  {{~/if}}{{/each}}
{{~/if}}
{{~!-- extensive body (release-notes-extensiveness doctrine) --}}
{{~#if body}}

{{body}}
{{~/if}}

`;

module.exports = {
  branches: ["main"],
  plugins: [
    // Preflight: Block release if working directory is dirty
    // ADR: 2025-12-23-semantic-release-preflight-guard
    ["@semantic-release/exec", { verifyConditionsCmd: "./scripts/release-preflight.sh" }],

    // Marketplace plugins require a version bump for ANY change.
    // Default: feat=minor, fix=patch, perf=patch, revert=patch.
    // Added: all other types trigger a patch release.
    [
      "@semantic-release/commit-analyzer",
      {
        releaseRules: [
          { type: "docs", release: "patch" },
          { type: "chore", release: "patch" },
          { type: "style", release: "patch" },
          { type: "refactor", release: "patch" },
          { type: "test", release: "patch" },
          { type: "build", release: "patch" },
          { type: "ci", release: "patch" },
          { type: "revert", release: "patch" },
        ],
      },
    ],

    // Notes generator with the body-preserving writerOpts (the reason this
    // config exists). transform + commitPartial are merged OVER the Angular
    // preset's writerOpts; all other preset opts (mainTemplate, headerPartial,
    // groupBy, sorts) are inherited unchanged.
    [
      "@semantic-release/release-notes-generator",
      {
        writerOpts: {
          transform: transformCommitPreservingBody,
          commitPartial: COMMIT_PARTIAL_WITH_BODY,
        },
      },
    ],

    // Version sync only. The previous generateNotesCmd pointed at a script in
    // the now-removed itp:semantic-release skill; notes are generated by
    // @semantic-release/release-notes-generator above.
    // ADR: 2025-12-06-release-notes-adr-linking
    // ADR: 2025-12-05-centralized-version-management
    ["@semantic-release/exec", { prepareCmd: `node scripts/sync-versions.mjs ${RELEASE_VERSION_PLACEHOLDER}` }],

    "@semantic-release/changelog",

    // marketplace.json-only versioning: no individual plugin.json files.
    // Hook definition files (hooks.json) explicitly listed for release asset
    // tracking so hooks.json changes ship with the release commit.
    [
      "@semantic-release/git",
      {
        assets: [
          "CHANGELOG.md",
          "plugin.json",
          "package.json",
          ".claude-plugin/plugin.json",
          ".claude-plugin/marketplace.json",
          "plugins/itp-hooks/plugin.json",
          "plugins/itp-hooks/hooks/hooks.json",
          "plugins/link-tools/hooks/hooks.json",
          "plugins/dotfiles-tools/hooks/hooks.json",
          "plugins/statusline-tools/hooks/hooks.json",
          "plugins/gh-tools/hooks/hooks.json",
          "plugins/mise/skills/run-full-release/SKILL.md",
          "plugins/mise/skills/show-env-status/SKILL.md",
          "plugins/mise/skills/list-repo-tasks/SKILL.md",
        ],
        message: `chore(release): ${RELEASE_VERSION_PLACEHOLDER} [skip ci]`,
      },
    ],

    // Push commit and tags after @semantic-release/git creates them.
    // Belt-and-suspenders: ensures push happens even in --no-ci mode.
    [
      "@semantic-release/exec",
      {
        successCmd:
          "/usr/bin/env bash -c 'git push --follow-tags origin main && git update-index --refresh && echo ✓ Git index refreshed'",
      },
    ],

    // Iter-143: explicit @semantic-release/github config to skip the four
    // community-documented bottleneck features that target cc-skills's
    // non-use-cases. ALL FOUR flags are LOAD-BEARING for performance;
    // reintroducing any of them re-adds GitHub API-call cost.
    //
    //   1. successComment:false — disables the per-resolved-commit
    //      `GET /search/issues` API storm (semantic-release/github#542, #867,
    //      #2204). cc-skills uses tag-driven releases, not PR-driven, so there
    //      are no resolved PRs/issues to comment on.
    //   2. failComment:false — no auto-opened GitHub issue on release failure;
    //      failures surface via local release-pipeline logs instead.
    //   3. releasedLabels:false — no `released` label on resolved PRs/issues;
    //      the tag + GitHub release page is the SSoT.
    //   4. addReleases:false — no "previous releases" back-reference block;
    //      CHANGELOG.md already links inter-version diffs.
    //
    // The iter-143 regression test pins these four flags to forbid a silent
    // revert in future config edits.
    [
      "@semantic-release/github",
      {
        successComment: false,
        failComment: false,
        releasedLabels: false,
        addReleases: false,
      },
    ],

    // Post-release: auto-update local plugin + verify cache. Fully automated.
    //
    // Iter-142: the post-release bash body was EXTRACTED to an external script
    // to resolve the lodash-template-vs-bash-parameter-expansion conflict —
    // @semantic-release/exec runs lodash template() on the successCmd string
    // before invoking the shell, so bash `${VAR:-default}` syntax inside the
    // command collided with lodash JS-eval. Passing the version as argv[1] to a
    // real .sh file keeps one well-formed `${nextRelease.version}` token here
    // while the script keeps normal bash semantics. Do NOT reintroduce inline
    // `${VAR:-default}` in any command string in this file.
    [
      "@semantic-release/exec",
      {
        successCmd: `./scripts/iter142-post-release-verification-with-iter140-per-step-timing-instrumentation-extracted-from-releaserc-yml-yaml-literal-to-avoid-lodash-template-versus-bash-parameter-expansion-syntax-conflict.sh ${RELEASE_VERSION_PLACEHOLDER}`,
      },
    ],
  ],
};

"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { issueNumberForBranch, syncRoadmapStatus } = require("./roadmap_status.cjs");

function fixture({ state = "OPEN", status = "Todo", member = true,
                   branch = "feat/pipo-48-goal-photo-hero-v1",
                   headRepo = "muhammadihsan-byte/pipo-gamification" } = {}) {
  const calls = [];
  const logs = [];
  const item = { id: "ITEM", project: { id: "PROJECT" },
                 fieldValueByName: status ? { name: status } : null };
  const data = {
    repository: { issue: { id: "ISSUE", state,
      projectItems: { nodes: member ? [item] : [] } } },
    user: { projectV2: { id: "PROJECT", field: { id: "FIELD",
      options: [{ id: "ACTIVE", name: "In Progress" },
                { id: "TODO", name: "Todo" }] } } }
  };
  return {
    calls, logs,
    context: {
      repo: { owner: "muhammadihsan-byte", repo: "pipo-gamification" },
      payload: { pull_request: { head: { ref: branch,
        repo: { full_name: headRepo } } } }
    },
    core: { info: x => logs.push(x), notice: x => logs.push(x) },
    github: { graphql: async (query, variables) => {
      calls.push({ query, variables });
      return query.includes("mutation(") ?
        { updateProjectV2ItemFieldValue: { projectV2Item: { id: "ITEM" } } } : data;
    } }
  };
}

test("identifies only explicit Pipo issue branches", () => {
  assert.equal(issueNumberForBranch("feat/pipo-48-goal-photo-hero-v1"), 48);
  assert.equal(issueNumberForBranch("fix/pipo-42-financial-preview"), 42);
  for (const value of ["feat/pipo-p1-all-approved-cards", "other/issue-42",
    "main", "feat/48-overview", "feat/pipo-0-fake", "feat/pipo-48"]) {
    assert.equal(issueNumberForBranch(value), null, value);
  }
});

test("only existing Todo issue item becomes In Progress", async () => {
  const f = fixture();
  assert.equal(await syncRoadmapStatus(f), "updated");
  assert.equal(f.calls.length, 2);
  assert.equal(f.calls[0].variables.issue, 48);
  assert.deepEqual(
    { project: f.calls[1].variables.project,
      item: f.calls[1].variables.item,
      field: f.calls[1].variables.field,
      choice: f.calls[1].variables.choice },
    { project: "PROJECT", item: "ITEM", field: "FIELD", choice: "ACTIVE" }
  );
});

test("never changes Done, In Progress, or a custom status", async () => {
  for (const status of ["Done", "In Progress", "Blocked", "In review"]) {
    const f = fixture({ status });
    assert.equal(await syncRoadmapStatus(f), "skipped-already-active");
    assert.equal(f.calls.length, 1, status);
  }
});

test("does not change closed issues or off-project issues", async () => {
  const closed = fixture({ state: "CLOSED" });
  assert.equal(await syncRoadmapStatus(closed), "skipped-closed");
  assert.equal(closed.calls.length, 1);
  const missing = fixture({ member: false });
  assert.equal(await syncRoadmapStatus(missing), "skipped-not-in-project");
  assert.equal(missing.calls.length, 1);
  assert.match(missing.logs.join(" "), /Auto-add/);
});

test("rejects forked pull requests and unmapped branches", async () => {
  const fork = fixture({ headRepo: "outsider/pipo-gamification" });
  assert.equal(await syncRoadmapStatus(fork), "skipped-untrusted");
  assert.equal(fork.calls.length, 0);
  const unknown = fixture({ branch: "feat/pipo-p1-all-approved-cards" });
  assert.equal(await syncRoadmapStatus(unknown), "skipped-unmapped");
  assert.equal(unknown.calls.length, 0);
});

test("empty project status can advance, but no other fields are written", async () => {
  const f = fixture({ status: null });
  assert.equal(await syncRoadmapStatus(f), "updated");
  assert.match(f.calls[1].query, /updateProjectV2ItemFieldValue/);
  assert.doesNotMatch(f.calls[1].query, /closeIssue|updateIssue|addProjectV2Item/);
});
